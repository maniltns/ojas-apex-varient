-- =====================================================================
-- Grandback (EBS) Bot — ORDS REST module  (RFP "API-first integration layer")
--
-- Publishes the SAME PL/SQL the APEX UI uses as REST endpoints under
--   /ords/<schema>/grandback/v1/...
-- so the bot is demoable with zero APEX import (see clients/grandback-chat.html).
--
-- Run AS the GRANDBACK_SCHEMA user (the schema that owns the packages/tables),
-- AFTER 01..04 have installed. Requires ORDS enabled on the ATP instance
-- (Always-Free ATP has ORDS on by default).
--
-- ⚠ SECURITY — READ BEFORE EXPOSING BEYOND A SANDBOX ⚠
--   As shipped, these resources are OPEN (no ORDS privilege) so a trial demo
--   works with zero auth setup. In this "demo mode" the caller's identity is
--   taken from the request body "email" — meaning ANYONE who can reach the URL
--   can act as ANY persona, including admin. This is acceptable ONLY for an
--   isolated, throwaway trial.
--   For ANY shared/persistent/internet-reachable deployment you MUST:
--     1. Uncomment the OAuth2 / DEFINE_PRIVILEGE block at the bottom to protect
--        the /grandback/v1/* pattern, AND
--     2. Rely on :current_user (the authenticated principal) for identity — the
--        handlers already prefer it and only fall back to body "email" when no
--        principal is present.
--   See SECURITY_TESTING.md for the authz/injection test checklist.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

BEGIN
    -- Enable REST on this schema (idempotent)
    BEGIN
        ORDS.ENABLE_SCHEMA(
            p_enabled             => TRUE,
            p_schema              => SYS_CONTEXT('USERENV','CURRENT_SCHEMA'),
            p_url_mapping_type    => 'BASE_PATH',
            p_url_mapping_pattern => 'grandback_schema',   -- /ords/grandback_schema/...
            p_auto_rest_auth      => FALSE
        );
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ENABLE_SCHEMA note: ' || SQLERRM);
    END;

    -- (Re)define the module
    BEGIN
        ORDS.DELETE_MODULE(p_module_name => 'grandback.v1');
    EXCEPTION WHEN OTHERS THEN NULL; END;

    ORDS.DEFINE_MODULE(
        p_module_name    => 'grandback.v1',
        p_base_path      => '/grandback/v1/',
        p_items_per_page => 25,
        p_status         => 'PUBLISHED',
        p_comments       => 'Grandback EBS Finance Bot — API-first Phase 1 layer'
    );

    -- ── POST /chat ────────────────────────────────────────────────────
    -- Body: {"email":"manager@accor.com","message":"Show AP aging","property_id":"prop_novotel_paris","thread_id":"api_thread_1"}
    -- Calls the bot engine directly (no APEX session needed). Persona is the
    -- "email" in the body, so persona-based validation works over REST.
    ORDS.DEFINE_TEMPLATE(p_module_name => 'grandback.v1', p_pattern => 'chat');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'grandback.v1',
        p_pattern     => 'chat',
        p_method      => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_source      => q'[
            DECLARE
                v_email    VARCHAR2(200);
                v_message  VARCHAR2(4000);
                v_prop     VARCHAR2(50);
                v_thread   VARCHAR2(100);
                v_ctx      GRANDBACK_IAM_PKG.user_context_t;
                v_result   VARCHAR2(32767);
            BEGIN
                -- IDENTITY: trust the authenticated ORDS principal first.
                -- :current_user is populated when the resource is protected
                -- (OAuth2 / first-party auth). Only when there is NO authenticated
                -- principal (open demo mode) do we fall back to the body email.
                -- This prevents admin impersonation via a forged "email" field.
                v_email   := :current_user;
                IF v_email IS NULL THEN
                    v_email := JSON_VALUE(:body_text, '$.email');   -- DEMO MODE ONLY
                END IF;
                v_message := JSON_VALUE(:body_text, '$.message');
                v_prop    := JSON_VALUE(:body_text, '$.property_id');
                v_thread  := NVL(JSON_VALUE(:body_text, '$.thread_id'), 'api_' || SYS_GUID());
                v_ctx     := GRANDBACK_IAM_PKG.get_user_context(v_email);

                IF v_prop IS NULL AND v_ctx.is_resolved AND v_ctx.property_access IS NOT NULL THEN
                    v_prop := REGEXP_SUBSTR(v_ctx.property_access, '[^,]+', 1, 1);
                END IF;

                v_result := GRANDBACK_BOT_PKG.process_chat_message(
                    p_email       => v_email,
                    p_ebs_role    => NVL(v_ctx.ebs_role, 'Finance Analyst'),
                    p_message     => v_message,
                    p_property_id => v_prop,
                    p_thread_id   => v_thread,
                    p_session_id  => 'ords'
                );

                :status_code := 200;
                OWA_UTIL.MIME_HEADER('application/json', FALSE);
                HTP.P('Access-Control-Allow-Origin: *');
                OWA_UTIL.HTTP_HEADER_CLOSE;
                HTP.PRN(v_result);
            END;
        ]'
    );

    -- ── GET /bootstrap?email=... ─────────────────────────────────────
    ORDS.DEFINE_TEMPLATE(p_module_name => 'grandback.v1', p_pattern => 'bootstrap');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'grandback.v1',
        p_pattern     => 'bootstrap',
        p_method      => 'GET',
        p_source_type => ORDS.source_type_plsql,
        p_source      => q'[
            DECLARE
                v_ctx   GRANDBACK_IAM_PKG.user_context_t;
                v_email VARCHAR2(200) := NVL(:current_user, :email);  -- principal first
            BEGIN
                v_ctx := GRANDBACK_IAM_PKG.get_user_context(v_email);
                OWA_UTIL.MIME_HEADER('application/json', FALSE);
                HTP.P('Access-Control-Allow-Origin: *');
                OWA_UTIL.HTTP_HEADER_CLOSE;
                APEX_JSON.OPEN_OBJECT;
                APEX_JSON.WRITE('resolved', v_ctx.is_resolved);
                APEX_JSON.OPEN_OBJECT('user');
                APEX_JSON.WRITE('email',    v_ctx.email);
                APEX_JSON.WRITE('name',     v_ctx.name);
                APEX_JSON.WRITE('role',     v_ctx.role);
                APEX_JSON.WRITE('ebs_role', v_ctx.ebs_role);
                APEX_JSON.CLOSE_OBJECT;
                APEX_JSON.OPEN_ARRAY('properties');
                FOR r IN (
                    SELECT property_id, name, city, currency
                      FROM GRANDBACK_PROPERTIES
                     WHERE status = 'active'
                       AND ( v_ctx.role = 'admin'
                             OR INSTR(',' || REPLACE(NVL(v_ctx.property_access,''),' ','') || ',',
                                      ',' || property_id || ',') > 0 )
                     ORDER BY name
                ) LOOP
                    APEX_JSON.OPEN_OBJECT;
                    APEX_JSON.WRITE('id',       r.property_id);
                    APEX_JSON.WRITE('name',     r.name);
                    APEX_JSON.WRITE('city',     r.city);
                    APEX_JSON.WRITE('currency', r.currency);
                    APEX_JSON.CLOSE_OBJECT;
                END LOOP;
                APEX_JSON.CLOSE_ARRAY;
                APEX_JSON.CLOSE_OBJECT;
            END;
        ]'
    );
    ORDS.DEFINE_PARAMETER(
        p_module_name        => 'grandback.v1',
        p_pattern            => 'bootstrap',
        p_method             => 'GET',
        p_name               => 'email',
        p_bind_variable_name => 'email',
        p_source_type        => 'URI',
        p_param_type         => 'STRING',
        p_access_method      => 'IN'
    );

    -- ── GET /aging/ap?email=...&property_id=... ──────────────────────
    -- Direct analytics resource — demonstrates API-first dynamic analytics.
    ORDS.DEFINE_TEMPLATE(p_module_name => 'grandback.v1', p_pattern => 'aging/ap');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'grandback.v1',
        p_pattern     => 'aging/ap',
        p_method      => 'GET',
        p_source_type => ORDS.source_type_plsql,
        p_source      => q'[
            DECLARE
                v_ctx   GRANDBACK_IAM_PKG.user_context_t;
                v_res   VARCHAR2(32767);
                v_email VARCHAR2(200) := NVL(:current_user, :email);  -- principal first
            BEGIN
                v_ctx := GRANDBACK_IAM_PKG.get_user_context(v_email);
                IF NOT v_ctx.is_resolved THEN
                    :status_code := 403;
                    OWA_UTIL.MIME_HEADER('application/json', FALSE);
                    OWA_UTIL.HTTP_HEADER_CLOSE;
                    HTP.PRN('{"error":"unknown user"}');
                    RETURN;
                END IF;
                -- route through the engine so IAM scope + audit still apply
                v_res := GRANDBACK_BOT_PKG.process_chat_message(
                    p_email => v_email, p_ebs_role => v_ctx.ebs_role,
                    p_message => 'Show AP aging', p_property_id => :property_id,
                    p_thread_id => 'api_aging', p_session_id => 'ords');
                OWA_UTIL.MIME_HEADER('application/json', FALSE);
                HTP.P('Access-Control-Allow-Origin: *');
                OWA_UTIL.HTTP_HEADER_CLOSE;
                HTP.PRN(v_res);
            END;
        ]'
    );
    ORDS.DEFINE_PARAMETER(p_module_name=>'grandback.v1', p_pattern=>'aging/ap', p_method=>'GET',
        p_name=>'email', p_bind_variable_name=>'email', p_source_type=>'URI', p_param_type=>'STRING', p_access_method=>'IN');
    ORDS.DEFINE_PARAMETER(p_module_name=>'grandback.v1', p_pattern=>'aging/ap', p_method=>'GET',
        p_name=>'property_id', p_bind_variable_name=>'property_id', p_source_type=>'URI', p_param_type=>'STRING', p_access_method=>'IN');

    -- ── GET /kpis ────────────────────────────────────────────────────
    ORDS.DEFINE_TEMPLATE(p_module_name => 'grandback.v1', p_pattern => 'kpis');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'grandback.v1',
        p_pattern     => 'kpis',
        p_method      => 'GET',
        p_source_type => ORDS.source_type_plsql,
        p_source      => q'[
            BEGIN
                OWA_UTIL.MIME_HEADER('application/json', FALSE);
                HTP.P('Access-Control-Allow-Origin: *');
                OWA_UTIL.HTTP_HEADER_CLOSE;
                APEX_JSON.OPEN_OBJECT;
                APEX_JSON.WRITE('blocked_24h',
                    (SELECT COUNT(*) FROM GRANDBACK_AUDIT_LOG WHERE status='blocked' AND timestamp >= SYSTIMESTAMP - INTERVAL '24' HOUR));
                APEX_JSON.WRITE('injection_24h',
                    (SELECT COUNT(*) FROM GRANDBACK_AUDIT_LOG WHERE action_type='INJECTION_ATTEMPT' AND timestamp >= SYSTIMESTAMP - INTERVAL '24' HOUR));
                APEX_JSON.WRITE('dml_24h',
                    (SELECT COUNT(*) FROM GRANDBACK_AUDIT_LOG WHERE action_type='DML_EXECUTION' AND timestamp >= SYSTIMESTAMP - INTERVAL '24' HOUR));
                APEX_JSON.WRITE('active_users',
                    (SELECT COUNT(DISTINCT email) FROM GRANDBACK_AUDIT_LOG WHERE timestamp >= SYSTIMESTAMP - INTERVAL '7' DAY));
                APEX_JSON.CLOSE_OBJECT;
            END;
        ]'
    );

    -- ── POST /approval/cancel ────────────────────────────────────────
    -- Body: {"email":"manager@accor.com","thread_id":"api_thread_1"}
    ORDS.DEFINE_TEMPLATE(p_module_name => 'grandback.v1', p_pattern => 'approval/cancel');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'grandback.v1',
        p_pattern     => 'approval/cancel',
        p_method      => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_source      => q'[
            BEGIN
                GRANDBACK_BOT_PKG.cancel_pending_approval(
                    p_email     => NVL(:current_user, JSON_VALUE(:body_text, '$.email')),
                    p_thread_id => JSON_VALUE(:body_text, '$.thread_id'));
                OWA_UTIL.MIME_HEADER('application/json', FALSE);
                HTP.P('Access-Control-Allow-Origin: *');
                OWA_UTIL.HTTP_HEADER_CLOSE;
                HTP.PRN('{"status":"cancelled"}');
            END;
        ]'
    );

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('✓ ORDS module grandback.v1 published.');
    DBMS_OUTPUT.PUT_LINE('  Base: https://<your-atp-host>/ords/grandback_schema/grandback/v1/');
    DBMS_OUTPUT.PUT_LINE('  Try:  POST .../chat  {"email":"manager@accor.com","message":"Show AP aging","property_id":"prop_novotel_paris"}');
END;
/

-- =====================================================================
-- OPTIONAL — lock the API down with an OAuth2 client-credentials role.
-- Uncomment to protect /grandback/v1/* and mint a client.
-- =====================================================================
-- BEGIN
--     ORDS.CREATE_ROLE(p_role_name => 'grandback_api');
--     ORDS.DEFINE_PRIVILEGE(
--         p_privilege_name => 'grandback.api.priv',
--         p_roles          => ORDS_TYPES.ORDS_VC2_LIST('grandback_api'),
--         p_patterns       => ORDS_TYPES.ORDS_VC2_LIST('/grandback/v1/*'),
--         p_label          => 'Grandback API',
--         p_comments       => 'Protects the Grandback bot REST module');
--     OAUTH.CREATE_CLIENT(
--         p_name            => 'grandback_demo_client',
--         p_grant_type      => 'client_credentials',
--         p_owner           => 'GRANDBACK',
--         p_description     => 'Demo client for Grandback bot API',
--         p_support_email   => 'admin@accor.com',
--         p_privilege_names => 'grandback.api.priv');
--     OAUTH.GRANT_CLIENT_ROLE(p_client_name => 'grandback_demo_client', p_role_name => 'grandback_api');
--     COMMIT;
-- END;
-- /
-- -- Retrieve client_id/secret:  SELECT name, client_id, client_secret FROM user_ords_clients;
