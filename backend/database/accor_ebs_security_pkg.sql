CREATE OR REPLACE PACKAGE ACCOR_IAM_VALIDATOR_PKG AS
    -- Main authorization check for database actions
    -- Returns 'ALLOWED' or a detailed error message explaining the refusal
    FUNCTION validate_action (
        p_email       IN VARCHAR2,
        p_ebs_role    IN VARCHAR2,
        p_action      IN VARCHAR2, -- read, write
        p_property_id IN VARCHAR2
    ) RETURN VARCHAR2;

    -- Threat detection: inspects query/prompt strings for SQL injection or prompt injection patterns
    -- Returns TRUE if injection attempt is detected, FALSE otherwise
    FUNCTION detect_injection (
        p_text IN VARCHAR2
    ) RETURN BOOLEAN;

    -- Logs audit entries into ACCOR_AUDIT_LOG
    PROCEDURE log_audit (
        p_email       IN VARCHAR2,
        p_action_type IN VARCHAR2,
        p_query_text  IN VARCHAR2,
        p_status      IN VARCHAR2,
        p_reason      IN VARCHAR2
    );
END ACCOR_IAM_VALIDATOR_PKG;
/

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
             WHERE UPPER(email) = UPPER(p_email);
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
             WHERE UPPER(email) = UPPER(p_email);
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
