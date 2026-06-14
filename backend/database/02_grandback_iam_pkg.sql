CREATE OR REPLACE PACKAGE GRANDBACK_IAM_PKG AS
    -- Hardened user-context record (single source of truth for GRANDBACK_USERS lookups).
    TYPE user_context_t IS RECORD (
        user_id          VARCHAR2(50),
        email            VARCHAR2(100),
        name             VARCHAR2(100),
        role             VARCHAR2(50),
        ebs_role         VARCHAR2(50),
        property_access  VARCHAR2(4000),
        org_id           VARCHAR2(50),
        is_resolved      BOOLEAN
    );

    -- Resolves a user from APEX :APP_USER (full email or short username).
    FUNCTION get_user_context (
        p_email IN VARCHAR2
    ) RETURN user_context_t;

    -- Authorization gate. Returns 'ALLOWED' or 'BLOCKED: <reason>'.
    FUNCTION validate_action (
        p_email       IN VARCHAR2,
        p_ebs_role    IN VARCHAR2,
        p_action      IN VARCHAR2,
        p_property_id IN VARCHAR2
    ) RETURN VARCHAR2;

    -- Threat detection.
    FUNCTION detect_injection (
        p_text IN VARCHAR2
    ) RETURN BOOLEAN;

    -- Length guard for inbound user messages.
    FUNCTION is_message_too_long (
        p_text IN VARCHAR2
    ) RETURN BOOLEAN;

    -- Audit logger (extended). All later parameters are optional so legacy
    -- callers continue to compile.
    PROCEDURE log_audit (
        p_email       IN VARCHAR2,
        p_action_type IN VARCHAR2,
        p_query_text  IN VARCHAR2,
        p_status      IN VARCHAR2,
        p_reason      IN VARCHAR2,
        p_role        IN VARCHAR2 DEFAULT NULL,
        p_property_id IN VARCHAR2 DEFAULT NULL,
        p_intent      IN VARCHAR2 DEFAULT NULL,
        p_session_id  IN VARCHAR2 DEFAULT NULL,
        p_request_ip  IN VARCHAR2 DEFAULT NULL
    );

    -- Maximum allowed inbound user message length.
    C_MAX_MESSAGE_LEN CONSTANT PLS_INTEGER := 4000;
END GRANDBACK_IAM_PKG;
/

CREATE OR REPLACE PACKAGE BODY GRANDBACK_IAM_PKG AS

    FUNCTION get_user_context (
        p_email IN VARCHAR2
    ) RETURN user_context_t IS
        v_ctx user_context_t;
    BEGIN
        v_ctx.is_resolved := FALSE;
        IF p_email IS NULL THEN
            RETURN v_ctx;
        END IF;

        -- Case-insensitive match: full email OR short username (e.g. 'ANALYST' → 'analyst@accor.com').
        -- This pattern is load-bearing — covered by the test suite.
        BEGIN
            SELECT user_id, email, name, role, ebs_role, property_access, org_id
              INTO v_ctx.user_id, v_ctx.email, v_ctx.name, v_ctx.role,
                   v_ctx.ebs_role, v_ctx.property_access, v_ctx.org_id
              FROM GRANDBACK_USERS
             WHERE UPPER(email) = UPPER(p_email)
                OR UPPER(email) LIKE UPPER(p_email) || '@%';
            v_ctx.is_resolved := TRUE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_ctx.is_resolved := FALSE;
        END;

        RETURN v_ctx;
    END get_user_context;

    FUNCTION is_message_too_long (
        p_text IN VARCHAR2
    ) RETURN BOOLEAN IS
    BEGIN
        RETURN p_text IS NOT NULL AND LENGTH(p_text) > C_MAX_MESSAGE_LEN;
    END is_message_too_long;

    FUNCTION detect_injection (
        p_text IN VARCHAR2
    ) RETURN BOOLEAN IS
        v_upper VARCHAR2(4000);
    BEGIN
        IF p_text IS NULL THEN
            RETURN FALSE;
        END IF;

        v_upper := UPPER(p_text);

        -- SQL injection signatures
        IF v_upper LIKE '%OR 1=1%'
           OR v_upper LIKE '%UNION SELECT%'
           OR v_upper LIKE '%DROP TABLE%'
           OR v_upper LIKE '%DROP USER%'
           OR v_upper LIKE '%TRUNCATE TABLE%'
           OR v_upper LIKE '%ALTER TABLE%'
           OR v_upper LIKE '%--%'
           OR v_upper LIKE '%OR ''%''=''%''%'
           OR v_upper LIKE '%EXECUTE IMMEDIATE%'
           OR v_upper LIKE '%DBMS_SQL%'
           OR v_upper LIKE '%BEGIN TRANSACTION%'
           OR v_upper LIKE '%XP_CMDSHELL%'
           OR v_upper LIKE '%SYS.DBMS_OUTPUT%'
           OR v_upper LIKE '%UTL_FILE%'
           OR v_upper LIKE '%UTL_HTTP%'
        THEN
            RETURN TRUE;
        END IF;

        -- Prompt-injection / jailbreak signatures
        IF v_upper LIKE '%IGNORE PREVIOUS INSTRUCTIONS%'
           OR v_upper LIKE '%IGNORE ALL PREVIOUS%'
           OR v_upper LIKE '%IGNORE SYSTEM%'
           OR v_upper LIKE '%DISREGARD THE ABOVE%'
           OR v_upper LIKE '%YOU ARE NOW%'
           OR v_upper LIKE '%DEVELOPER MODE%'
           OR v_upper LIKE '%JAILBREAK%'
           OR v_upper LIKE '%ACT AS A%'
           OR v_upper LIKE '%PRETEND TO BE%'
        THEN
            RETURN TRUE;
        END IF;

        -- Embedded HTML / script vectors (replies are rendered as HTML).
        IF v_upper LIKE '%<SCRIPT%'
           OR v_upper LIKE '%JAVASCRIPT:%'
           OR v_upper LIKE '%ONERROR=%'
           OR v_upper LIKE '%ONLOAD=%'
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
        p_reason      IN VARCHAR2,
        p_role        IN VARCHAR2 DEFAULT NULL,
        p_property_id IN VARCHAR2 DEFAULT NULL,
        p_intent      IN VARCHAR2 DEFAULT NULL,
        p_session_id  IN VARCHAR2 DEFAULT NULL,
        p_request_ip  IN VARCHAR2 DEFAULT NULL
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_ctx user_context_t;
    BEGIN
        v_ctx := get_user_context(p_email);

        INSERT INTO GRANDBACK_AUDIT_LOG (
            user_id, email, action_type, query_text, status, reason,
            role, property_id, intent, session_id, request_ip, timestamp
        ) VALUES (
            NVL(v_ctx.user_id, 'gb_usr_unknown'),
            p_email,
            p_action_type,
            SUBSTR(p_query_text, 1, 4000),
            p_status,
            SUBSTR(p_reason, 1, 1000),
            NVL(p_role, v_ctx.role),
            p_property_id,
            p_intent,
            p_session_id,
            p_request_ip,
            SYSTIMESTAMP
        );

        COMMIT;
    END log_audit;

    FUNCTION validate_action (
        p_email       IN VARCHAR2,
        p_ebs_role    IN VARCHAR2,
        p_action      IN VARCHAR2,
        p_property_id IN VARCHAR2
    ) RETURN VARCHAR2 IS
        v_ctx user_context_t;
    BEGIN
        v_ctx := get_user_context(p_email);

        IF NOT v_ctx.is_resolved THEN
            RETURN 'BLOCKED: User not found in OCI IAM Directory';
        END IF;

        -- Admins bypass property validation.
        IF v_ctx.role = 'admin' THEN
            RETURN 'ALLOWED';
        END IF;

        -- Property boundary check.
        IF p_property_id IS NULL OR INSTR(v_ctx.property_access, p_property_id) = 0 THEN
            RETURN 'BLOCKED: EBS role has no permission context for property ID: ' || NVL(p_property_id, '<none>');
        END IF;

        -- Analyst write restriction.
        IF LOWER(p_action) = 'write' AND v_ctx.role = 'finance_analyst' THEN
            RETURN 'BLOCKED: Write operation denied: Finance Analyst role is restricted to READ queries only';
        END IF;

        RETURN 'ALLOWED';
    END validate_action;

END GRANDBACK_IAM_PKG;
/
