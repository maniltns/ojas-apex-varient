-- ============================================================
-- ACCOR EBS Finance Bot - Short Username Fixes & Updates
-- Run this entire script in APEX SQL Workshop > SQL Commands
-- to update the backend database package and get the updated APEX PL/SQL code.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- STEP 1: Re-compile ACCOR_IAM_VALIDATOR_PKG Body
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE PACKAGE BODY ACCOR_IAM_VALIDATOR_PKG AS

    FUNCTION detect_injection (
        p_text IN VARCHAR2
    ) RETURN BOOLEAN IS
        v_upper_text VARCHAR2(4000);
    BEGIN
        IF p_text IS NULL THEN
            RETURN FALSE;
        END IF;

        v_upper_text := UPPER(p_text);

        -- 1. SQL Injection Signatures
        IF v_upper_text LIKE '%OR 1=1%'
           OR v_upper_text LIKE '%UNION SELECT%'
           OR v_upper_text LIKE '%DROP TABLE%'
           OR v_upper_text LIKE '%--%'
           OR v_upper_text LIKE '%OR ''%''=''%''%'
           -- 2. Prompt Injection Signatures
           OR v_upper_text LIKE '%IGNORE PREVIOUS INSTRUCTIONS%'
           OR v_upper_text LIKE '%IGNORE SYSTEM%'
           OR v_upper_text LIKE '%SYS.DBMS_OUTPUT%'
        THEN
            RETURN TRUE;
        END IF;

        RETURN FALSE;
    END detect_injection;

    PROCEDURE log_audit (
        p_email       IN VARCHAR2,
        p_action_type IN VARCHAR2,
        p_query_text  IN VARCHAR2,
        p_status      IN VARCHAR2,
        p_reason      IN VARCHAR2
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_user_id VARCHAR2(50);
    BEGIN
        -- Attempt to resolve user_id
        BEGIN
            SELECT user_id INTO v_user_id 
              FROM ACCOR_USERS 
             WHERE UPPER(email) = UPPER(p_email) OR UPPER(email) LIKE UPPER(p_email) || '@%';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_user_id := 'accor_usr_unknown';
        END;

        INSERT INTO ACCOR_AUDIT_LOG (user_id, email, action_type, query_text, status, reason, timestamp)
        VALUES (v_user_id, p_email, p_action_type, p_query_text, p_status, p_reason, SYSTIMESTAMP);

        COMMIT;
    END log_audit;

    FUNCTION validate_action (
        p_email       IN VARCHAR2,
        p_ebs_role    IN VARCHAR2,
        p_action      IN VARCHAR2,
        p_property_id IN VARCHAR2
    ) RETURN VARCHAR2 IS
        v_role            VARCHAR2(50);
        v_property_access VARCHAR2(4000);
    BEGIN
        -- Find user context
        BEGIN
            SELECT role, property_access 
              INTO v_role, v_property_access
              FROM ACCOR_USERS 
             WHERE UPPER(email) = UPPER(p_email) OR UPPER(email) LIKE UPPER(p_email) || '@%';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN 'BLOCKED: User not found in OCI IAM Directory';
        END;

        -- Admins bypass property validation
        IF v_role = 'admin' THEN
            RETURN 'ALLOWED';
        END IF;

        -- Validate property boundary (comma-separated list search)
        IF INSTR(v_property_access, p_property_id) = 0 THEN
            RETURN 'BLOCKED: EBS role has no permission context for property ID: ' || p_property_id;
        END IF;

        -- Validate analyst role write restrictions
        IF LOWER(p_action) = 'write' AND v_role = 'finance_analyst' THEN
            RETURN 'BLOCKED: Write operation denied: Finance Analyst role is restricted to READ queries only';
        END IF;

        RETURN 'ALLOWED';
    END validate_action;

END ACCOR_IAM_VALIDATOR_PKG;
/

-- ─────────────────────────────────────────────────────────────
-- STEP 2: Re-compile ACCOR_EBS_BOT_PKG Body
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE PACKAGE BODY ACCOR_EBS_BOT_PKG AS

    -- Helper to format AP aging results for a property into an HTML table
    FUNCTION format_ap_aging (p_property_id IN VARCHAR2) RETURN VARCHAR2 IS
        v_table VARCHAR2(32767);
        v_count INTEGER := 0;
    BEGIN
        v_table := '<h3>Accounts Payable (AP) Aging Report</h3>' ||
                   '<table>' ||
                   '<thead><tr>' ||
                   '<th>Invoice ID</th><th>Invoice Number</th><th>Vendor</th><th>Amount</th><th>Due Date</th><th>Status</th>' ||
                   '</tr></thead><tbody>';

        FOR r IN (
            SELECT i.invoice_id, i.invoice_number, v.name AS vendor_name, i.amount, i.currency, i.due_date, i.status
              FROM ACCOR_AP_INVOICES i
              JOIN ACCOR_VENDORS v ON i.vendor_id = v.vendor_id
             WHERE i.property_id = p_property_id
             ORDER BY i.due_date ASC
        ) LOOP
            v_count := v_count + 1;
            v_table := v_table || '<tr>' ||
                       '<td>' || r.invoice_id || '</td>' ||
                       '<td>' || r.invoice_number || '</td>' ||
                       '<td>' || r.vendor_name || '</td>' ||
                       '<td>' || TO_CHAR(r.amount, 'FM999,999,990.00') || ' ' || r.currency || '</td>' ||
                       '<td>' || TO_CHAR(r.due_date, 'YYYY-MM-DD') || '</td>' ||
                       '<td>' || r.status || '</td>' ||
                       '</tr>';
        END LOOP;

        v_table := v_table || '</tbody></table>';

        IF v_count = 0 THEN
            RETURN '<p>No accounts payable invoices found for this property.</p>';
        END IF;

        RETURN v_table;
    END format_ap_aging;

    -- Helper to format GL balances into an HTML table
    FUNCTION format_gl_balances RETURN VARCHAR2 IS
        v_table VARCHAR2(32767);
        v_count INTEGER := 0;
    BEGIN
        v_table := '<h3>General Ledger Cash & Balances Summary</h3>' ||
                   '<table>' ||
                   '<thead><tr>' ||
                   '<th>Account Code</th><th>Account Name</th><th>Type</th><th>Balance</th><th>Currency</th>' ||
                   '</tr></thead><tbody>';

        FOR r IN (
            SELECT code, name, type, balance, currency
              FROM ACCOR_GL_ACCOUNTS
              ORDER BY code ASC
        ) LOOP
            v_count := v_count + 1;
            v_table := v_table || '<tr>' ||
                       '<td>' || r.code || '</td>' ||
                       '<td>' || r.name || '</td>' ||
                       '<td>' || r.type || '</td>' ||
                       '<td>' || TO_CHAR(r.balance, 'FM999,999,990.00') || '</td>' ||
                       '<td>' || r.currency || '</td>' ||
                       '</tr>';
        END LOOP;

        v_table := v_table || '</tbody></table>';

        IF v_count = 0 THEN
            RETURN '<p>No Chart of Accounts found.</p>';
        END IF;

        RETURN v_table;
    END format_gl_balances;

    -- Helper to format consolidated summary into an HTML table
    FUNCTION format_consolidated_summary RETURN VARCHAR2 IS
        v_table VARCHAR2(32767);
    BEGIN
        v_table := '<h3>Consolidated Portfolio Financial Summary</h3>' ||
                   '<table>' ||
                   '<thead><tr>' ||
                   '<th>Property Name</th><th>Currency</th><th>Total AP (Unpaid)</th><th>Total AR (Unpaid)</th>' ||
                   '</tr></thead><tbody>';

        FOR r IN (
            SELECT p.name AS property_name, p.currency,
                   NVL((SELECT SUM(amount) FROM ACCOR_AP_INVOICES WHERE property_id = p.property_id AND status != 'paid'), 0) AS total_ap,
                   NVL((SELECT SUM(amount) FROM ACCOR_AR_INVOICES WHERE property_id = p.property_id AND status != 'paid'), 0) AS total_ar
              FROM ACCOR_PROPERTIES p
             ORDER BY p.name ASC
        ) LOOP
            v_table := v_table || '<tr>' ||
                       '<td>' || r.property_name || '</td>' ||
                       '<td>' || r.currency || '</td>' ||
                       '<td>' || TO_CHAR(r.total_ap, 'FM999,999,990.00') || '</td>' ||
                       '<td>' || TO_CHAR(r.total_ar, 'FM999,999,990.00') || '</td>' ||
                       '</tr>';
        END LOOP;

        v_table := v_table || '</tbody></table>';
        RETURN v_table;
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
        -- Find user_id case-insensitively with prefix pattern matching for short usernames
        SELECT user_id INTO v_user_id 
          FROM ACCOR_USERS 
         WHERE UPPER(email) = UPPER(p_email) OR UPPER(email) LIKE UPPER(p_email) || '@%';

        -- Save user query in conversation log
        INSERT INTO ACCOR_CONVERSATIONS (conversation_id, user_id, thread_id, role, message_content, timestamp)
        VALUES ('chat_msg_' || SYS_GUID(), v_user_id, p_thread_id, 'user', p_message, SYSTIMESTAMP);

        -- 1. Threat Detection (SQL/Prompt Injection)
        IF ACCOR_IAM_VALIDATOR_PKG.detect_injection(p_message) THEN
            ACCOR_IAM_VALIDATOR_PKG.log_audit(p_email, 'INJECTION_ATTEMPT', p_message, 'blocked', 'SQL or Prompt injection signatures detected.');
            v_reply := '⚠️ <strong>Security Threat Detected:</strong> The input query contains illegal SQL segments or jailbreak signatures and has been blocked. This incident has been logged in the audit trail.';
            
            INSERT INTO ACCOR_CONVERSATIONS (conversation_id, user_id, thread_id, role, message_content, timestamp)
            VALUES ('chat_msg_' || SYS_GUID(), v_user_id, p_thread_id, 'bot', v_reply, SYSTIMESTAMP);
            
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
            v_reply := '❌ <strong>Access Denied (OCI IAM Validator Refusal):</strong> ' || SUBSTR(v_validation_res, 9);
            
            INSERT INTO ACCOR_CONVERSATIONS (conversation_id, user_id, thread_id, role, message_content, timestamp)
            VALUES ('chat_msg_' || SYS_GUID(), v_user_id, p_thread_id, 'bot', v_reply, SYSTIMESTAMP);
            
            RETURN JSON_OBJECT(
                'reply' VALUE v_reply,
                'requires_approval' VALUE false,
                'approval_payload' VALUE NULL,
                'intent' VALUE 'security_violation'
            );
        END IF;

        -- 4. Parse Intent & Execute
        IF UPPER(p_message) LIKE '%AP AGING%' OR UPPER(p_message) LIKE '%AGING%' OR UPPER(p_message) LIKE '%OVERDUE%' THEN
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
                    v_reply := '❌ <strong>Error:</strong> Invoice ID `' || v_invoice_id || '` was not found in the Autonomous Database.';
                    RETURN JSON_OBJECT('reply' VALUE v_reply, 'requires_approval' VALUE false, 'approval_payload' VALUE NULL, 'intent' VALUE v_intent);
            END;

            IF v_invoice_status = 'paid' THEN
                v_reply := 'ℹ️ <strong>Status Check:</strong> Invoice `' || v_invoice_num || '` (ID: ' || v_invoice_id || ') is already marked as <strong>paid</strong>.';
                ACCOR_IAM_VALIDATOR_PKG.log_audit(p_email, 'PAYMENT_APPROVAL', 'Payment check for ' || v_invoice_id, 'allowed', 'Invoice already paid');
            ELSE
                -- Enforce Gated Confirmation payload
                v_requires_approval := 'true';
                v_reply := '💼 <strong>Payment Approval Confirmation Required:</strong> You are requesting to approve payment for invoice <strong>' || v_invoice_num || '</strong> (ID: ' || v_invoice_id || ') in amount of <strong>EUR ' || TO_CHAR(v_invoice_amount, 'FM999,990.00') || '</strong>. Please authorize the transaction in the APEX confirmation dialog.';
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
                SELECT invoice_id
                  INTO v_invoice_id
                  FROM (
                      SELECT REGEXP_SUBSTR(message_content, 'ap_inv_[0-9]+') AS invoice_id
                        FROM ACCOR_CONVERSATIONS
                       WHERE thread_id = p_thread_id 
                         AND role = 'bot' 
                         AND message_content LIKE '%Payment Approval Confirmation Required%'
                       ORDER BY timestamp DESC
                  )
                 WHERE ROWNUM = 1;
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
                
                v_reply := '✅ <strong>Payment Approved Successfully:</strong> Invoice `' || v_invoice_num || '` (ID: ' || v_invoice_id || ') for <strong>EUR ' || TO_CHAR(v_invoice_amount, 'FM999,990.00') || '</strong> has been paid. Status updated in Autonomous ATP Database.';
                ACCOR_IAM_VALIDATOR_PKG.log_audit(p_email, 'DML_EXECUTION', 'Payment confirmed and updated for ' || v_invoice_id, 'allowed', 'Success');
                COMMIT;
            END IF;

        ELSE
            -- Attempt Select AI Translation (OpenAI/OCI GenAI)
            BEGIN
                -- Execute dynamically so it compiles even on shared sandbox instances lacking DBMS_CLOUD_AI
                EXECUTE IMMEDIATE 'BEGIN :1 := DBMS_CLOUD_AI.GENERATE(prompt => :2, profile_name => :3); END;'
                USING OUT v_reply, IN p_message, IN 'ACCOR_BOT_PROFILE';
                
                v_intent := 'select_ai_response';
                ACCOR_IAM_VALIDATOR_PKG.log_audit(p_email, 'READ_QUERY', 'Select AI Prompt: ' || SUBSTR(p_message, 1, 1000), 'allowed', 'Success via Select AI');
            EXCEPTION
                WHEN OTHERS THEN
                    -- Catch-all fallback if Select AI profile is not configured, is restricted, or LLM fails
                    v_reply := 'Hello! I am the **ACCOR EBS Finance Orchestrator**. I can securely assist you with your Corporate Finance tasks:' || CHR(10) || CHR(10) ||
                                '* **Analyze AP:** Click **📊 AP Aging** or type `"Show AP aging"` to inspect overdue vendor invoices.' || CHR(10) ||
                                '* **Check GL:** Click **💰 GL Balances** or type `"Show GL cash balance"` to view account summaries.' || CHR(10) ||
                                '* **Portfolio Health:** Click **🏢 Portfolio** or type `"Check consolidated summary"` to query multi-property scopes.' || CHR(10) ||
                                '* **Approve Payments:** Type `"Approve payment for ap_inv_1001"` to execute gated DML transaction runs (Manager role only).' || CHR(10) || CHR(10) ||
                                '*(Note: Database Select AI translation is disabled on this sandbox schema. Running in offline pattern-route mode.)*';
            END;
        END IF;

        -- Save bot reply in conversation log
        INSERT INTO ACCOR_CONVERSATIONS (conversation_id, user_id, thread_id, role, message_content, timestamp)
        VALUES ('chat_msg_' || SYS_GUID(), v_user_id, p_thread_id, 'bot', v_reply, SYSTIMESTAMP);
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


-- ─────────────────────────────────────────────────────────────
-- STEP 3: APEX Page 2 PL/SQL Definitions (For reference & copy-paste)
-- ─────────────────────────────────────────────────────────────

-- A. APEX Page 2 AJAX Callback: LOAD_CHAT
-- Go to Page Designer > Page 2 > Ajax Callbacks > LOAD_CHAT > PL/SQL Code
-- Paste the code below:

-- DECLARE
--     v_user_id   VARCHAR2(100);
--     v_thread_id VARCHAR2(100);
-- BEGIN
--     v_thread_id := 'thread_' || :APP_SESSION;
--     BEGIN
--         SELECT user_id INTO v_user_id
--         FROM ACCOR_USERS 
--         WHERE UPPER(email) = UPPER(:APP_USER) OR UPPER(email) LIKE UPPER(:APP_USER) || '@%';
--     EXCEPTION WHEN NO_DATA_FOUND THEN v_user_id := NULL; END;
-- 
--     APEX_JSON.OPEN_OBJECT;
--     APEX_JSON.OPEN_ARRAY('messages');
--     IF v_user_id IS NOT NULL THEN
--         FOR r IN (
--             SELECT role, message_content AS content
--             FROM ACCOR_CONVERSATIONS
--             WHERE user_id = v_user_id
--             AND thread_id = v_thread_id
--             ORDER BY timestamp ASC
--         ) LOOP
--             APEX_JSON.OPEN_OBJECT;
--             APEX_JSON.WRITE('role',    r.role);
--             APEX_JSON.WRITE('content', r.content);
--             APEX_JSON.CLOSE_OBJECT;
--         END LOOP;
--     END IF;
--     APEX_JSON.CLOSE_ARRAY;
--     APEX_JSON.CLOSE_OBJECT;
-- END;


-- B. APEX Page 2 AJAX Callback: PROCESS_CHAT
-- Go to Page Designer > Page 2 > Ajax Callbacks > PROCESS_CHAT > PL/SQL Code
-- Paste the code below:

-- DECLARE
--     v_result     VARCHAR2(32767);
--     v_email      VARCHAR2(200);
--     v_role       VARCHAR2(100);
--     v_thread_id  VARCHAR2(100);
--     v_msg        VARCHAR2(4000);
--     v_prop       VARCHAR2(100);
-- BEGIN
--     v_email     := :APP_USER;
--     v_thread_id := 'thread_' || :APP_SESSION;
--     v_msg       := APEX_APPLICATION.G_X01;
--     v_prop      := APEX_APPLICATION.G_X02;
-- 
--     BEGIN
--         SELECT ebs_role INTO v_role
--         FROM ACCOR_USERS 
--         WHERE UPPER(email) = UPPER(v_email) OR UPPER(email) LIKE UPPER(v_email) || '@%';
--     EXCEPTION WHEN NO_DATA_FOUND THEN v_role := 'Finance Analyst'; END;
-- 
--     IF v_prop IS NULL OR TRIM(v_prop) = '' THEN
--         v_prop := 'prop_novotel_paris';
--     END IF;
-- 
--     v_result := ACCOR_EBS_BOT_PKG.process_chat_message(
--         p_email       => v_email,
--         p_ebs_role    => v_role,
--         p_message     => v_msg,
--         p_property_id => v_prop,
--         p_thread_id   => v_thread_id
--     );
-- 
--     -- Parse JSON result and forward to UI
--     DECLARE
--         v_reply   VARCHAR2(32767);
--         v_intent  VARCHAR2(200);
--         v_req_ap  VARCHAR2(10);
--         v_ap_json VARCHAR2(4000);
--     BEGIN
--         v_reply   := JSON_VALUE(v_result, '$.reply');
--         v_intent  := JSON_VALUE(v_result, '$.intent');
--         v_req_ap  := JSON_VALUE(v_result, '$.requires_approval');
-- 
--         APEX_JSON.OPEN_OBJECT;
--         APEX_JSON.WRITE('status', 'success');
--         APEX_JSON.WRITE('reply',  NVL(v_reply, v_result));
--         APEX_JSON.WRITE('intent', NVL(v_intent, ''));
--         APEX_JSON.WRITE('requires_approval', NVL(v_req_ap, 'false') = 'true');
-- 
--         -- Include approval payload if present
--         BEGIN
--             v_ap_json := JSON_QUERY(v_result, '$.approval_payload');
--             IF v_ap_json IS NOT NULL THEN
--                 APEX_JSON.WRITE_RAW('approval_payload', v_ap_json);
--             END IF;
--         EXCEPTION WHEN OTHERS THEN NULL; END;
-- 
--         APEX_JSON.CLOSE_OBJECT;
--     EXCEPTION WHEN OTHERS THEN
--         APEX_JSON.OPEN_OBJECT;
--         APEX_JSON.WRITE('status', 'success');
--         APEX_JSON.WRITE('reply',  v_result);
--         APEX_JSON.WRITE('requires_approval', FALSE);
--         APEX_JSON.CLOSE_OBJECT;
--     END;
-- 
-- EXCEPTION WHEN OTHERS THEN
--     APEX_JSON.OPEN_OBJECT;
--     APEX_JSON.WRITE('status',  'error');
--     APEX_JSON.WRITE('message', SQLERRM);
--     APEX_JSON.CLOSE_OBJECT;
-- END;


-- C. APEX Page 2 Chat Feed Region: PL/SQL Function Body
-- Go to Page Designer > Page 2 > CHAT_FEED region > Source > PL/SQL Function Body
-- Paste the code below:

-- DECLARE
--     v_html      CLOB := '';
--     v_user_id   VARCHAR2(100);
--     v_thread_id VARCHAR2(100);
-- BEGIN
--     v_thread_id := 'thread_' || :APP_SESSION;
-- 
--     -- Get logged-in user ID
--     BEGIN
--         SELECT user_id INTO v_user_id
--         FROM ACCOR_USERS
--         WHERE UPPER(email) = UPPER(:APP_USER) OR UPPER(email) LIKE UPPER(:APP_USER) || '@%';
--     EXCEPTION
--         WHEN NO_DATA_FOUND THEN v_user_id := NULL;
--     END;
-- 
--     -- Render conversation history
--     IF v_user_id IS NOT NULL THEN
--         FOR r IN (
--             SELECT role, message_content
--             FROM ACCOR_CONVERSATIONS
--             WHERE user_id = v_user_id
--             AND thread_id = v_thread_id
--             ORDER BY timestamp ASC
--         ) LOOP
--             IF r.role = 'user' THEN
--                 v_html := v_html || '<div class="chat-msg-user">' 
--                           || APEX_ESCAPE.HTML(r.message_content) 
--                           || '</div>';
--             ELSE
--                 -- Bot messages may contain markdown tables — render raw HTML
--                 v_html := v_html || '<div class="chat-msg-bot">' 
--                           || r.message_content 
--                           || '</div>';
--             END IF;
--         END LOOP;
--     END IF;
-- 
--     -- Welcome message if empty
--     IF v_html IS NULL OR DBMS_LOB.GETLENGTH(v_html) = 0 THEN
--         v_html := '<div class="chat-msg-bot">'
--                || '<strong>👋 Welcome to ACCOR EBS Finance Bot!</strong><br/>'
--                || 'I can help you with:<br/>'
--                || '&bull; AP Aging reports by property<br/>'
--                || '&bull; GL Account balances<br/>'
--                || '&bull; Invoice payment approvals<br/>'
--                || '&bull; Consolidated portfolio summaries<br/><br/>'
--                || '<em>Select a property above and type your question below.</em>'
--                || '</div>';
--     END IF;
-- 
--     -- Render quick-action chips
--     v_html := '<div class="chat-chip-bar">'
--            || '<span class="chat-chip" onclick="sendChip(''Show AP Aging'')">📊 AP Aging</span>'
--            || '<span class="chat-chip" onclick="sendChip(''Show GL Balances'')">💰 GL Balances</span>'
--            || '<span class="chat-chip" onclick="sendChip(''Consolidated Summary'')">🏨 Portfolio</span>'
--            || '</div>'
--            || '<div id="chat-feed-container" class="chat-feed">'
--            || v_html
--            || '</div>'
--            || '<script>var f=document.getElementById("chat-feed-container");if(f)f.scrollTop=f.scrollHeight;</script>';
-- 
--     RETURN TO_CLOB(v_html);
-- 
-- EXCEPTION
--     WHEN OTHERS THEN
--         RETURN TO_CLOB('<div class="chat-msg-bot" style="color:#f85149;">Error loading chat: ' 
--                        || APEX_ESCAPE.HTML(SQLERRM) || '</div>');
-- END;
