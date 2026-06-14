-- =====================================================================
-- GRANDBACK_BOT_API_PKG
--
-- Thin JSON wrapper sitting between the APEXlang AJAX page processes and
-- GRANDBACK_BOT_PKG. Page processes do `invokeApi` against this package
-- so the inline PL/SQL stays well below the APEXlang 4000-char ceiling.
-- =====================================================================

CREATE OR REPLACE PACKAGE GRANDBACK_BOT_API_PKG AS
    -- One-shot bootstrap returned to the chat client on page load.
    -- Emits {user, role, ebs_role, properties[], thread_id, recent[]}.
    PROCEDURE load_bootstrap;

    -- Wraps process_chat_message — reads message via APEX_APPLICATION.G_X01,
    -- property_id via G_X02. Emits the JSON the package returns plus a
    -- status envelope.
    PROCEDURE process_chat;

    -- Cancels the most recent pending approval on the thread.
    PROCEDURE cancel_approval;

    -- KPI strip for the admin governance page.
    PROCEDURE load_governance_kpis;
END GRANDBACK_BOT_API_PKG;
/

CREATE OR REPLACE PACKAGE BODY GRANDBACK_BOT_API_PKG AS

    FUNCTION current_thread RETURN VARCHAR2 IS
        v_thread VARCHAR2(100);
    BEGIN
        v_thread := APEX_UTIL.GET_SESSION_STATE('G_THREAD_ID');
        IF v_thread IS NULL THEN
            v_thread := 'thread_' || V('APP_SESSION');
            APEX_UTIL.SET_SESSION_STATE('G_THREAD_ID', v_thread);
        END IF;
        RETURN v_thread;
    END current_thread;

    PROCEDURE load_bootstrap IS
        v_ctx       GRANDBACK_IAM_PKG.user_context_t;
        v_thread    VARCHAR2(100);
        v_user_role VARCHAR2(50);
        v_user_acc  VARCHAR2(4000);
    BEGIN
        v_ctx := GRANDBACK_IAM_PKG.get_user_context(V('APP_USER'));
        v_thread := current_thread;

        IF v_ctx.is_resolved THEN
            v_user_role := v_ctx.role;
            v_user_acc  := v_ctx.property_access;
        END IF;

        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('thread_id', v_thread);
        APEX_JSON.WRITE('resolved',  v_ctx.is_resolved);

        APEX_JSON.OPEN_OBJECT('user');
        APEX_JSON.WRITE('email',    NVL(v_ctx.email, V('APP_USER')));
        APEX_JSON.WRITE('name',     v_ctx.name);
        APEX_JSON.WRITE('role',     v_user_role);
        APEX_JSON.WRITE('ebs_role', v_ctx.ebs_role);
        APEX_JSON.CLOSE_OBJECT;

        APEX_JSON.OPEN_ARRAY('properties');
        FOR r IN (
            SELECT property_id, name, brand, city, country, currency
              FROM GRANDBACK_PROPERTIES
             WHERE status = 'active'
               AND ( v_user_role = 'admin'
                     OR INSTR(',' || REPLACE(NVL(v_user_acc,''),' ','') || ',',
                              ',' || property_id || ',') > 0 )
             ORDER BY name
        ) LOOP
            APEX_JSON.OPEN_OBJECT;
            APEX_JSON.WRITE('id',       r.property_id);
            APEX_JSON.WRITE('name',     r.name);
            APEX_JSON.WRITE('brand',    r.brand);
            APEX_JSON.WRITE('city',     r.city);
            APEX_JSON.WRITE('country',  r.country);
            APEX_JSON.WRITE('currency', r.currency);
            APEX_JSON.CLOSE_OBJECT;
        END LOOP;
        APEX_JSON.CLOSE_ARRAY;

        APEX_JSON.OPEN_ARRAY('recent');
        IF v_ctx.is_resolved THEN
            FOR r IN (
                SELECT role, message_content, timestamp
                  FROM GRANDBACK_CONVERSATIONS
                 WHERE user_id   = v_ctx.user_id
                   AND thread_id = v_thread
                 ORDER BY timestamp ASC
                 FETCH FIRST 50 ROWS ONLY
            ) LOOP
                APEX_JSON.OPEN_OBJECT;
                APEX_JSON.WRITE('role',    r.role);
                APEX_JSON.WRITE('content', r.message_content);
                APEX_JSON.WRITE('ts',      TO_CHAR(r.timestamp, 'YYYY-MM-DD"T"HH24:MI:SS'));
                APEX_JSON.CLOSE_OBJECT;
            END LOOP;
        END IF;
        APEX_JSON.CLOSE_ARRAY;

        APEX_JSON.CLOSE_OBJECT;
    END load_bootstrap;

    PROCEDURE process_chat IS
        v_message    VARCHAR2(4000);
        v_property   VARCHAR2(50);
        v_thread     VARCHAR2(100);
        v_session    VARCHAR2(100);
        v_ctx        GRANDBACK_IAM_PKG.user_context_t;
        v_result     VARCHAR2(32767);
        v_reply      VARCHAR2(32767);
        v_intent     VARCHAR2(50);
        v_req_ap     VARCHAR2(10);
        v_payload    VARCHAR2(4000);
    BEGIN
        v_message  := APEX_APPLICATION.G_X01;
        v_property := APEX_APPLICATION.G_X02;
        v_thread   := current_thread;
        v_session  := V('APP_SESSION');
        v_ctx      := GRANDBACK_IAM_PKG.get_user_context(V('APP_USER'));

        IF v_property IS NULL OR LENGTH(TRIM(v_property)) = 0 THEN
            -- Default to the user's first allowed property.
            IF v_ctx.is_resolved AND v_ctx.property_access IS NOT NULL THEN
                v_property := REGEXP_SUBSTR(v_ctx.property_access, '[^,]+', 1, 1);
            END IF;
        END IF;

        v_result := GRANDBACK_BOT_PKG.process_chat_message(
            p_email       => V('APP_USER'),
            p_ebs_role    => NVL(v_ctx.ebs_role, 'Finance Analyst'),
            p_message     => v_message,
            p_property_id => v_property,
            p_thread_id   => v_thread,
            p_session_id  => v_session
        );

        v_reply   := JSON_VALUE(v_result, '$.reply');
        v_intent  := JSON_VALUE(v_result, '$.intent');
        v_req_ap  := JSON_VALUE(v_result, '$.requires_approval');
        BEGIN
            v_payload := JSON_QUERY(v_result, '$.approval_payload');
        EXCEPTION WHEN OTHERS THEN v_payload := NULL; END;

        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('status',            'success');
        APEX_JSON.WRITE('reply',             NVL(v_reply, v_result));
        APEX_JSON.WRITE('intent',            NVL(v_intent, ''));
        APEX_JSON.WRITE('requires_approval', NVL(v_req_ap, 'false') = 'true');
        IF v_payload IS NOT NULL THEN
            APEX_JSON.WRITE_RAW('approval_payload', v_payload);
        END IF;
        APEX_JSON.CLOSE_OBJECT;
    EXCEPTION WHEN OTHERS THEN
        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('status',  'error');
        APEX_JSON.WRITE('message', SQLERRM);
        APEX_JSON.CLOSE_OBJECT;
    END process_chat;

    PROCEDURE cancel_approval IS
        v_thread VARCHAR2(100);
    BEGIN
        v_thread := current_thread;
        GRANDBACK_BOT_PKG.cancel_pending_approval(
            p_email     => V('APP_USER'),
            p_thread_id => v_thread
        );
        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('status', 'cancelled');
        APEX_JSON.CLOSE_OBJECT;
    END cancel_approval;

    PROCEDURE load_governance_kpis IS
        v_blocked_24h   NUMBER;
        v_injection_24h NUMBER;
        v_dml_24h       NUMBER;
        v_active_users  NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_blocked_24h
          FROM GRANDBACK_AUDIT_LOG
         WHERE status = 'blocked'
           AND timestamp >= SYSTIMESTAMP - INTERVAL '24' HOUR;

        SELECT COUNT(*) INTO v_injection_24h
          FROM GRANDBACK_AUDIT_LOG
         WHERE action_type = 'INJECTION_ATTEMPT'
           AND timestamp >= SYSTIMESTAMP - INTERVAL '24' HOUR;

        SELECT COUNT(*) INTO v_dml_24h
          FROM GRANDBACK_AUDIT_LOG
         WHERE action_type = 'DML_EXECUTION'
           AND timestamp >= SYSTIMESTAMP - INTERVAL '24' HOUR;

        SELECT COUNT(DISTINCT email) INTO v_active_users
          FROM GRANDBACK_AUDIT_LOG
         WHERE timestamp >= SYSTIMESTAMP - INTERVAL '7' DAY;

        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('blocked_24h',   v_blocked_24h);
        APEX_JSON.WRITE('injection_24h', v_injection_24h);
        APEX_JSON.WRITE('dml_24h',       v_dml_24h);
        APEX_JSON.WRITE('active_users',  v_active_users);
        APEX_JSON.CLOSE_OBJECT;
    END load_governance_kpis;

END GRANDBACK_BOT_API_PKG;
/
