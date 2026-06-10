CREATE OR REPLACE PACKAGE ACCOR_EBS_BOT_PKG AS
    -- Main entrypoint to process chatbot conversation messages
    -- Returns a JSON string containing "reply", "requires_approval", "approval_payload", and "intent"
    FUNCTION process_chat_message (
        p_email       IN VARCHAR2,
        p_ebs_role    IN VARCHAR2,
        p_message     IN VARCHAR2,
        p_property_id IN VARCHAR2,
        p_thread_id   IN VARCHAR2
    ) RETURN VARCHAR2;
END ACCOR_EBS_BOT_PKG;
/

CREATE OR REPLACE PACKAGE BODY ACCOR_EBS_BOT_PKG AS

    -- Helper to format AP aging results for a property into a markdown table
    FUNCTION format_ap_aging (p_property_id IN VARCHAR2) RETURN VARCHAR2 IS
        v_table VARCHAR2(32767);
        v_count INTEGER := 0;
    BEGIN
        v_table := '| Invoice ID | Invoice Number | Vendor | Amount | Due Date | Status |' || CHR(10) ||
                   '| --- | --- | --- | --- | --- | --- |' || CHR(10);

        FOR r IN (
            SELECT i.invoice_id, i.invoice_number, v.name AS vendor_name, i.amount, i.currency, i.due_date, i.status
              FROM ACCOR_AP_INVOICES i
              JOIN ACCOR_VENDORS v ON i.vendor_id = v.vendor_id
             WHERE i.property_id = p_property_id
             ORDER BY i.due_date ASC
        ) LOOP
            v_count := v_count + 1;
            v_table := v_table || '| ' || r.invoice_id || ' | ' || r.invoice_number || ' | ' || r.vendor_name || ' | ' || 
                       TO_CHAR(r.amount, 'FM999,999,990.00') || ' ' || r.currency || ' | ' || 
                       TO_CHAR(r.due_date, 'YYYY-MM-DD') || ' | ' || r.status || ' |' || CHR(10);
        END LOOP;

        IF v_count = 0 THEN
            RETURN 'No accounts payable invoices found for this property.';
        END IF;

        RETURN '### Accounts Payable (AP) Aging Report' || CHR(10) || v_table;
    END format_ap_aging;

    -- Helper to format GL balances into a markdown table
    FUNCTION format_gl_balances RETURN VARCHAR2 IS
        v_table VARCHAR2(32767);
        v_count INTEGER := 0;
    BEGIN
        v_table := '| Account Code | Account Name | Type | Balance | Currency |' || CHR(10) ||
                   '| --- | --- | --- | --- | --- |' || CHR(10);

        FOR r IN (
            SELECT code, name, type, balance, currency
              FROM ACCOR_GL_ACCOUNTS
             ORDER BY code ASC
        ) LOOP
            v_count := v_count + 1;
            v_table := v_table || '| ' || r.code || ' | ' || r.name || ' | ' || r.type || ' | ' || 
                       TO_CHAR(r.balance, 'FM999,999,990.00') || ' | ' || r.currency || ' |' || CHR(10);
        END LOOP;

        IF v_count = 0 THEN
            RETURN 'No Chart of Accounts found.';
        END IF;

        RETURN '### General Ledger Cash & Balances Summary' || CHR(10) || v_table;
    END format_gl_balances;

    -- Helper to format consolidated summary
    FUNCTION format_consolidated_summary RETURN VARCHAR2 IS
        v_table VARCHAR2(32767);
    BEGIN
        v_table := '| Property Name | Currency | Total AP (Unpaid) | Total AR (Unpaid) |' || CHR(10) ||
                   '| --- | --- | --- | --- |' || CHR(10);

        FOR r IN (
            SELECT p.name AS property_name, p.currency,
                   NVL((SELECT SUM(amount) FROM ACCOR_AP_INVOICES WHERE property_id = p.property_id AND status != 'paid'), 0) AS total_ap,
                   NVL((SELECT SUM(amount) FROM ACCOR_AR_INVOICES WHERE property_id = p.property_id AND status != 'paid'), 0) AS total_ar
              FROM ACCOR_PROPERTIES p
             ORDER BY p.name ASC
        ) LOOP
            v_table := v_table || '| ' || r.property_name || ' | ' || r.currency || ' | ' || 
                       TO_CHAR(r.total_ap, 'FM999,999,990.00') || ' | ' || 
                       TO_CHAR(r.total_ar, 'FM999,999,990.00') || ' |' || CHR(10);
        END LOOP;

        RETURN '### Consolidated Portfolio Financial Summary' || CHR(10) || v_table;
    END format_consolidated_summary;

    -- Core chat message processing function
    FUNCTION process_chat_message (
        p_email       IN VARCHAR2,
        p_ebs_role    IN VARCHAR2,
        p_message     IN VARCHAR2,
        p_property_id IN VARCHAR2,
        p_thread_id   IN VARCHAR2
    ) RETURN VARCHAR2 IS
        v_user_id           VARCHAR2(50);
        v_action            VARCHAR2(10) := 'read';
        v_validation_res    VARCHAR2(1000);
        v_intent            VARCHAR2(50) := 'general';
        v_reply             VARCHAR2(32767);
        v_requires_approval VARCHAR2(10) := 'false';
        v_approval_payload  VARCHAR2(4000) := 'null';
        
        -- State for invoice workflow
        v_invoice_id        VARCHAR2(50);
        v_invoice_num       VARCHAR2(50);
        v_invoice_amount    NUMBER(15,2);
        v_invoice_status    VARCHAR2(30);
    BEGIN
        -- Find user_id
        SELECT user_id INTO v_user_id FROM ACCOR_USERS WHERE email = p_email;

        -- Save user query in conversation log
        INSERT INTO ACCOR_CONVERSATIONS (conversation_id, user_id, thread_id, role, message_content, timestamp)
        VALUES ('chat_msg_' || SUBSTR(SYS_GUID(), 1, 8), v_user_id, p_thread_id, 'user', p_message, SYSTIMESTAMP);

        -- 1. Threat Detection (SQL/Prompt Injection)
        IF ACCOR_IAM_VALIDATOR_PKG.detect_injection(p_message) THEN
            ACCOR_IAM_VALIDATOR_PKG.log_audit(p_email, 'INJECTION_ATTEMPT', p_message, 'blocked', 'SQL or Prompt injection signatures detected.');
            v_reply := '⚠️ **Security Threat Detected:** The input query contains illegal SQL segments or jailbreak signatures and has been blocked. This incident has been logged in the audit trail.';
            
            INSERT INTO ACCOR_CONVERSATIONS (conversation_id, user_id, thread_id, role, message_content, timestamp)
            VALUES ('chat_msg_' || SUBSTR(SYS_GUID(), 1, 8), v_user_id, p_thread_id, 'bot', v_reply, SYSTIMESTAMP);
            
            RETURN JSON_OBJECT(
                'reply' VALUE v_reply,
                'requires_approval' VALUE false,
                'approval_payload' VALUE NULL,
                'intent' VALUE 'security_violation'
            );
        END IF;

        -- 2. Determine Action Type (Read vs Write)
        IF UPPER(p_message) LIKE '%APPROVE%' OR UPPER(p_message) LIKE '%CONFIRM%' OR UPPER(p_message) LIKE '%PAY%' THEN
            v_action := 'write';
        END IF;

        -- 3. Run IAM Role & Boundary Validation
        v_validation_res := ACCOR_IAM_VALIDATOR_PKG.validate_action(p_email, p_ebs_role, v_action, p_property_id);
        IF v_validation_res != 'ALLOWED' THEN
            ACCOR_IAM_VALIDATOR_PKG.log_audit(p_email, CASE WHEN v_action = 'write' THEN 'PAYMENT_APPROVAL' ELSE 'READ_QUERY' END, p_message, 'blocked', v_validation_res);
            v_reply := '❌ **Access Denied (OCI IAM Validator Refusal):** ' || SUBSTR(v_validation_res, 9);
            
            INSERT INTO ACCOR_CONVERSATIONS (conversation_id, user_id, thread_id, role, message_content, timestamp)
            VALUES ('chat_msg_' || SUBSTR(SYS_GUID(), 1, 8), v_user_id, p_thread_id, 'bot', v_reply, SYSTIMESTAMP);
            
            RETURN JSON_OBJECT(
                'reply' VALUE v_reply,
                'requires_approval' VALUE false,
                'approval_payload' VALUE NULL,
                'intent' VALUE 'security_violation'
            );
        END IF;

        -- 4. Parse Intent & Execute
        IF UPPER(p_message) LIKE '%AP AGING%' OR UPPER(p_message) LIKE '%AGING%' THEN
            v_intent := 'ap_aging';
            v_reply := format_ap_aging(p_property_id);
            ACCOR_IAM_VALIDATOR_PKG.log_audit(p_email, 'READ_QUERY', 'AP Aging Query for property: ' || p_property_id, 'allowed', 'Success');

        ELSIF UPPER(p_message) LIKE '%GL BALANCE%' OR UPPER(p_message) LIKE '%CASH BALANCE%' THEN
            v_intent := 'gl_balances';
            v_reply := format_gl_balances;
            ACCOR_IAM_VALIDATOR_PKG.log_audit(p_email, 'READ_QUERY', 'GL Balances Query', 'allowed', 'Success');

        ELSIF UPPER(p_message) LIKE '%CONSOLIDATED%' OR UPPER(p_message) LIKE '%SUMMARY%' THEN
            v_intent := 'consolidated_summary';
            v_reply := format_consolidated_summary;
            ACCOR_IAM_VALIDATOR_PKG.log_audit(p_email, 'READ_QUERY', 'Consolidated Summary Query', 'allowed', 'Success');

        ELSIF UPPER(p_message) LIKE '%APPROVE%' OR UPPER(p_message) LIKE '%PAY%' THEN
            v_intent := 'payment_approval';
            
            -- Extract Invoice ID (simple regex-like extraction via REGEXP_SUBSTR)
            v_invoice_id := REGEXP_SUBSTR(p_message, 'ap_inv_[0-9]+');
            IF v_invoice_id IS NULL THEN
                v_invoice_id := 'ap_inv_1001'; -- Fallback if not specified
            END IF;

            -- Check if invoice exists
            BEGIN
                SELECT invoice_number, amount, status 
                  INTO v_invoice_num, v_invoice_amount, v_invoice_status
                  FROM ACCOR_AP_INVOICES
                 WHERE invoice_id = v_invoice_id;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_reply := '❌ **Error:** Invoice ID `' || v_invoice_id || '` was not found in the Autonomous Database.';
                    RETURN JSON_OBJECT('reply' VALUE v_reply, 'requires_approval' VALUE false, 'approval_payload' VALUE NULL, 'intent' VALUE v_intent);
            END;

            IF v_invoice_status = 'paid' THEN
                v_reply := 'ℹ️ **Status Check:** Invoice `' || v_invoice_num || '` (ID: ' || v_invoice_id || ') is already marked as **paid**.';
                ACCOR_IAM_VALIDATOR_PKG.log_audit(p_email, 'PAYMENT_APPROVAL', 'Payment check for ' || v_invoice_id, 'allowed', 'Invoice already paid');
            ELSE
                -- Enforce Gated Confirmation payload
                v_requires_approval := 'true';
                v_reply := '💼 **Payment Approval Confirmation Required:** You are requesting to approve payment for invoice **' || v_invoice_num || '** (ID: ' || v_invoice_id || ') in amount of **EUR ' || TO_CHAR(v_invoice_amount, 'FM999,990.00') || '**. Please authorize the transaction in the APEX confirmation dialog.';
                v_approval_payload := JSON_OBJECT(
                    'action' VALUE 'pay_invoice',
                    'invoice_id' VALUE v_invoice_id,
                    'invoice_number' VALUE v_invoice_num,
                    'amount' VALUE v_invoice_amount
                );
            END IF;

        ELSIF UPPER(p_message) = 'CONFIRM' THEN
            v_intent := 'payment_confirm';
            
            -- Find the last thread action details
            BEGIN
                SELECT REGEXP_SUBSTR(message_content, 'ap_inv_[0-9]+')
                  INTO v_invoice_id
                  FROM ACCOR_CONVERSATIONS
                 WHERE thread_id = p_thread_id 
                   AND role = 'bot' 
                   AND message_content LIKE '%Payment Approval Confirmation Required%'
                 ORDER BY timestamp DESC
                 FETCH FIRST 1 ROWS ONLY;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_invoice_id := NULL;
            END;

            IF v_invoice_id IS NULL THEN
                v_reply := '❌ **Error:** No pending transaction was found in the conversation context. Please request a new payment approval first.';
            ELSE
                -- Update invoice status to PAID
                UPDATE ACCOR_AP_INVOICES 
                   SET status = 'paid' 
                 WHERE invoice_id = v_invoice_id;
                 
                SELECT invoice_number, amount INTO v_invoice_num, v_invoice_amount FROM ACCOR_AP_INVOICES WHERE invoice_id = v_invoice_id;
                
                v_reply := '✅ **Payment Approved Successfully:** Invoice `' || v_invoice_num || '` (ID: ' || v_invoice_id || ') for **EUR ' || TO_CHAR(v_invoice_amount, 'FM999,990.00') || '** has been paid. Status updated in Autonomous ATP Database.';
                ACCOR_IAM_VALIDATOR_PKG.log_audit(p_email, 'DML_EXECUTION', 'Payment confirmed and updated for ' || v_invoice_id, 'allowed', 'Success');
                COMMIT;
            END IF;

        ELSE
            -- Attempt Select AI Translation (OpenAI/OCI GenAI)
            BEGIN
                -- Execute stateless generation using the configured Select AI profile
                v_reply := DBMS_CLOUD_AI.GENERATE(
                    prompt       => p_message,
                    profile_name => 'ACCOR_BOT_PROFILE'
                );
                v_intent := 'select_ai_response';
                ACCOR_IAM_VALIDATOR_PKG.log_audit(p_email, 'READ_QUERY', 'Select AI Prompt: ' || SUBSTR(p_message, 1, 1000), 'allowed', 'Success via Select AI');
            EXCEPTION
                WHEN OTHERS THEN
                    -- Catch-all fallback if Select AI profile is not configured or LLM fails
                    v_reply := 'Hello! I am the **ACCOR EBS Finance Orchestrator**. I can securely assist you with your Corporate Finance tasks.' || CHR(10) ||
                               '* **Analyze AP:** Type `"Show AP aging"` to inspect overdue vendor invoices.' || CHR(10) ||
                               '* **Check GL:** Type `"Show GL cash balance"` to view account summaries.' || CHR(10) ||
                               '* **Portfolio Health:** Type `"Check consolidated summary"` to query multi-property scopes.' || CHR(10) ||
                               '* **Approve Payments:** Type `"Approve payment for ap_inv_1001"` to execute transaction runs (Manager role only).' || CHR(10) ||
                               '(Note: Select AI / DBMS_CLOUD_AI translation profile ACCOR_BOT_PROFILE is not configured or raised: ' || SQLERRM || ')';
            END;
        END IF;

        -- Save bot reply in conversation log
        INSERT INTO ACCOR_CONVERSATIONS (conversation_id, user_id, thread_id, role, message_content, timestamp)
        VALUES ('chat_msg_' || SUBSTR(SYS_GUID(), 1, 8), v_user_id, p_thread_id, 'bot', v_reply, SYSTIMESTAMP);
        COMMIT;

        -- Return payload as JSON string
        RETURN JSON_OBJECT(
            'reply' VALUE v_reply,
            'requires_approval' VALUE CASE WHEN v_requires_approval = 'true' THEN true ELSE false END,
            'approval_payload' VALUE CASE WHEN v_requires_approval = 'true' THEN JSON_QUERY(v_approval_payload, '$') ELSE NULL END,
            'intent' VALUE v_intent
        );
    END process_chat_message;

END ACCOR_EBS_BOT_PKG;
/
