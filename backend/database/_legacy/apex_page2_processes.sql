-- ============================================================
-- ACCOR EBS Bot — Page 2 ALL THREE AJAX Processes
-- Run once each as separate AJAX Callback processes on Page 2
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- PROCESS 1: LOAD_PROPERTIES
-- Name: LOAD_PROPERTIES  |  Type: Execute Code  |  Point: Ajax Callback
-- ─────────────────────────────────────────────────────────────
DECLARE
BEGIN
    APEX_JSON.OPEN_OBJECT;
    APEX_JSON.OPEN_ARRAY('properties');
    FOR r IN (
        SELECT property_id, name
        FROM ACCOR_PROPERTIES
        WHERE status = 'active'
        ORDER BY name
    ) LOOP
        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('id',   r.property_id);
        APEX_JSON.WRITE('name', r.name);
        APEX_JSON.CLOSE_OBJECT;
    END LOOP;
    APEX_JSON.CLOSE_ARRAY;
    APEX_JSON.CLOSE_OBJECT;
END;

-- ─────────────────────────────────────────────────────────────
-- PROCESS 2: LOAD_CHAT
-- Name: LOAD_CHAT  |  Type: Execute Code  |  Point: Ajax Callback
-- ─────────────────────────────────────────────────────────────
DECLARE
    v_user_id   VARCHAR2(100);
    v_thread_id VARCHAR2(100);
BEGIN
    v_thread_id := 'thread_' || :APP_SESSION;
    BEGIN
        SELECT user_id INTO v_user_id
        FROM ACCOR_USERS WHERE UPPER(email) = UPPER(:APP_USER) OR UPPER(email) LIKE UPPER(:APP_USER) || '@%';
    EXCEPTION WHEN NO_DATA_FOUND THEN v_user_id := NULL; END;

    APEX_JSON.OPEN_OBJECT;
    APEX_JSON.OPEN_ARRAY('messages');
    IF v_user_id IS NOT NULL THEN
        FOR r IN (
            SELECT role, message_content AS content
            FROM ACCOR_CONVERSATIONS
            WHERE user_id = v_user_id
            AND thread_id = v_thread_id
            ORDER BY timestamp ASC
        ) LOOP
            APEX_JSON.OPEN_OBJECT;
            APEX_JSON.WRITE('role',    r.role);
            APEX_JSON.WRITE('content', r.content);
            APEX_JSON.CLOSE_OBJECT;
        END LOOP;
    END IF;
    APEX_JSON.CLOSE_ARRAY;
    APEX_JSON.CLOSE_OBJECT;
END;

-- ─────────────────────────────────────────────────────────────
-- PROCESS 3: PROCESS_CHAT
-- Name: PROCESS_CHAT  |  Type: Execute Code  |  Point: Ajax Callback
-- ─────────────────────────────────────────────────────────────
DECLARE
    v_result     VARCHAR2(32767);
    v_email      VARCHAR2(200);
    v_role       VARCHAR2(100);
    v_thread_id  VARCHAR2(100);
    v_msg        VARCHAR2(4000);
    v_prop       VARCHAR2(100);
BEGIN
    v_email     := :APP_USER;
    v_thread_id := 'thread_' || :APP_SESSION;
    v_msg       := APEX_APPLICATION.G_X01;
    v_prop      := APEX_APPLICATION.G_X02;

    BEGIN
        SELECT ebs_role INTO v_role
        FROM ACCOR_USERS WHERE UPPER(email) = UPPER(v_email) OR UPPER(email) LIKE UPPER(v_email) || '@%';
    EXCEPTION WHEN NO_DATA_FOUND THEN v_role := 'Finance Analyst'; END;

    IF v_prop IS NULL OR TRIM(v_prop) = '' THEN
        v_prop := 'prop_novotel_paris';
    END IF;

    v_result := ACCOR_EBS_BOT_PKG.process_chat_message(
        p_email       => v_email,
        p_ebs_role    => v_role,
        p_message     => v_msg,
        p_property_id => v_prop,
        p_thread_id   => v_thread_id
    );

    -- Parse JSON result and forward to UI
    DECLARE
        v_reply   VARCHAR2(32767);
        v_intent  VARCHAR2(200);
        v_req_ap  VARCHAR2(10);
        v_ap_json VARCHAR2(4000);
    BEGIN
        v_reply   := JSON_VALUE(v_result, '$.reply');
        v_intent  := JSON_VALUE(v_result, '$.intent');
        v_req_ap  := JSON_VALUE(v_result, '$.requires_approval');

        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('status', 'success');
        APEX_JSON.WRITE('reply',  NVL(v_reply, v_result));
        APEX_JSON.WRITE('intent', NVL(v_intent, ''));
        APEX_JSON.WRITE('requires_approval', NVL(v_req_ap, 'false') = 'true');

        -- Include approval payload if present
        BEGIN
            v_ap_json := JSON_QUERY(v_result, '$.approval_payload');
            IF v_ap_json IS NOT NULL THEN
                APEX_JSON.WRITE_RAW('approval_payload', v_ap_json);
            END IF;
        EXCEPTION WHEN OTHERS THEN NULL; END;

        APEX_JSON.CLOSE_OBJECT;
    EXCEPTION WHEN OTHERS THEN
        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('status', 'success');
        APEX_JSON.WRITE('reply',  v_result);
        APEX_JSON.WRITE('requires_approval', FALSE);
        APEX_JSON.CLOSE_OBJECT;
    END;

EXCEPTION WHEN OTHERS THEN
    APEX_JSON.OPEN_OBJECT;
    APEX_JSON.WRITE('status',  'error');
    APEX_JSON.WRITE('message', SQLERRM);
    APEX_JSON.CLOSE_OBJECT;
END;
