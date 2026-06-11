-- ============================================================
-- ACCOR EBS Finance Bot - APEX Application Builder Script
-- Application ID: 43171
-- Run in: APEX SQL Workshop > SQL Commands
-- ============================================================

DECLARE
    v_app_id     NUMBER := 43171;
    v_page_id    NUMBER;
    v_region_id  NUMBER;
    v_item_id    NUMBER;
    v_button_id  NUMBER;
    v_process_id NUMBER;
    v_da_id      NUMBER;
    v_da_act_id  NUMBER;
    v_ws_id      NUMBER;
BEGIN
    -- Get workspace ID
    SELECT workspace_id INTO v_ws_id 
    FROM apex_applications 
    WHERE application_id = v_app_id;
    
    APEX_UTIL.SET_WORKSPACE(
        p_workspace => (SELECT workspace FROM apex_workspaces WHERE workspace_id = v_ws_id)
    );
    
    -- ============================================================
    -- UPDATE PAGE 2: Chat Workspace
    -- ============================================================
    UPDATE apex_application_pages
    SET page_title    = 'Chat Workspace',
        page_name     = 'Chat Workspace',
        page_alias    = 'CHAT-WORKSPACE'
    WHERE application_id = v_app_id
    AND   page_id        = 2;
    
    DBMS_OUTPUT.PUT_LINE('Page 2 updated.');

EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
