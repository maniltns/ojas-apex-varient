-- ============================================================
-- ACCOR EBS Finance Bot — Page 2 Chat Feed Dynamic Content
-- Region Type: Dynamic Content (PL/SQL)
-- Paste this in the Source > PL/SQL Function Body of Chat Feed region
-- ============================================================
DECLARE
    v_html      CLOB := '';
    v_user_id   VARCHAR2(100);
    v_thread_id VARCHAR2(100);
BEGIN
    v_thread_id := 'thread_' || :APP_SESSION;

    -- Get logged-in user ID
    BEGIN
        SELECT user_id INTO v_user_id
        FROM ACCOR_USERS
        WHERE UPPER(email) = UPPER(:APP_USER) OR UPPER(email) LIKE UPPER(:APP_USER) || '@%';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN v_user_id := NULL;
    END;

    -- Render conversation history
    IF v_user_id IS NOT NULL THEN
        FOR r IN (
            SELECT role, message_content
            FROM ACCOR_CONVERSATIONS
            WHERE user_id = v_user_id
            AND thread_id = v_thread_id
            ORDER BY timestamp ASC
        ) LOOP
            IF r.role = 'user' THEN
                v_html := v_html || '<div class="chat-msg-user">' 
                          || APEX_ESCAPE.HTML(r.message_content) 
                          || '</div>';
            ELSE
                -- Bot messages may contain markdown tables — render raw HTML
                v_html := v_html || '<div class="chat-msg-bot">' 
                          || r.message_content 
                          || '</div>';
            END IF;
        END LOOP;
    END IF;

    -- Welcome message if empty
    IF v_html IS NULL OR DBMS_LOB.GETLENGTH(v_html) = 0 THEN
        v_html := '<div class="chat-msg-bot">'
               || '<strong>👋 Welcome to ACCOR EBS Finance Bot!</strong><br/>'
               || 'I can help you with:<br/>'
               || '&bull; AP Aging reports by property<br/>'
               || '&bull; GL Account balances<br/>'
               || '&bull; Invoice payment approvals<br/>'
               || '&bull; Consolidated portfolio summaries<br/><br/>'
               || '<em>Select a property above and type your question below.</em>'
               || '</div>';
    END IF;

    -- Render quick-action chips
    v_html := '<div class="chat-chip-bar">'
           || '<span class="chat-chip" onclick="sendChip(''Show AP Aging'')">📊 AP Aging</span>'
           || '<span class="chat-chip" onclick="sendChip(''Show GL Balances'')">💰 GL Balances</span>'
           || '<span class="chat-chip" onclick="sendChip(''Consolidated Summary'')">🏨 Portfolio</span>'
           || '</div>'
           || '<div id="chat-feed-container" class="chat-feed">'
           || v_html
           || '</div>'
           || '<script>var f=document.getElementById("chat-feed-container");if(f)f.scrollTop=f.scrollHeight;</script>';

    RETURN TO_CLOB(v_html);

EXCEPTION
    WHEN OTHERS THEN
        RETURN TO_CLOB('<div class="chat-msg-bot" style="color:#f85149;">Error loading chat: ' 
                       || APEX_ESCAPE.HTML(SQLERRM) || '</div>');
END;
