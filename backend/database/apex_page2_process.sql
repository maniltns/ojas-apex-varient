-- ============================================================
-- ACCOR EBS Finance Bot — APEX Page 2 AJAX Process
-- Name this process: PROCESS_CHAT
-- Type: AJAX Callback (Execute Code)
-- Run in: Processing tab of Page 2
-- ============================================================
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
    v_msg       := APEX_APPLICATION.G_X01;   -- sent via x01
    v_prop      := :P2_PROPERTY_ID;

    -- Get user EBS role
    BEGIN
        SELECT ebs_role INTO v_role
        FROM ACCOR_USERS
        WHERE UPPER(email) = UPPER(v_email);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_role := 'Finance Analyst';
    END;

    -- If message empty, fall back to page item
    IF v_msg IS NULL OR TRIM(v_msg) = '' THEN
        v_msg := :P2_USER_MESSAGE;
    END IF;

    -- Call the bot orchestrator
    v_result := ACCOR_EBS_BOT_PKG.process_chat_message(
        p_email       => v_email,
        p_ebs_role    => v_role,
        p_message     => v_msg,
        p_property_id => NVL(v_prop, 'prop_novotel_paris'),
        p_thread_id   => v_thread_id
    );

    -- Parse the JSON result to extract fields for the UI
    DECLARE
        v_json         APEX_JSON.T_VALUES;
        v_reply        VARCHAR2(32767);
        v_intent       VARCHAR2(200);
        v_req_approval VARCHAR2(10);
        v_ap_payload   VARCHAR2(4000);
    BEGIN
        APEX_JSON.PARSE(v_json, v_result);
        v_reply        := APEX_JSON.GET_VARCHAR2(v_json, 'reply');
        v_intent       := APEX_JSON.GET_VARCHAR2(v_json, 'intent');
        v_req_approval := APEX_JSON.GET_VARCHAR2(v_json, 'requires_approval');
        v_ap_payload   := APEX_JSON.GET_VARCHAR2(v_json, 'approval_payload');

        -- Output structured JSON for JavaScript handler
        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('status', 'success');
        APEX_JSON.WRITE('intent', NVL(v_intent, ''));
        APEX_JSON.WRITE('requires_approval', NVL(v_req_approval, 'false') = 'true');
        IF v_ap_payload IS NOT NULL THEN
            APEX_JSON.WRITE_RAW('approval_payload', v_ap_payload);
        END IF;
        APEX_JSON.CLOSE_OBJECT;
    EXCEPTION
        WHEN OTHERS THEN
            -- Fallback: return raw result
            APEX_JSON.OPEN_OBJECT;
            APEX_JSON.WRITE('status', 'success');
            APEX_JSON.WRITE('raw', v_result);
            APEX_JSON.CLOSE_OBJECT;
    END;

EXCEPTION
    WHEN OTHERS THEN
        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('status', 'error');
        APEX_JSON.WRITE('message', SQLERRM);
        APEX_JSON.CLOSE_OBJECT;
END;
