-- =====================================================================
-- Grandback (EBS) Bot — Select AI configuration (optional)
--
-- This script is OPTIONAL. The bot package compiles and runs without it
-- (the static help message is the documented fallback). Run this only
-- when you have an LLM key and want NL → SQL translation enabled.
--
-- Edit the three DEFINE values below, then run via SQLcl as ADMIN or as
-- the GRANDBACK_SCHEMA user with the CLOUD_AI privileges granted.
-- =====================================================================

DEFINE llm_provider = 'openai'        -- one of: openai, oci, cohere, google, azure
DEFINE llm_model    = 'gpt-4o-mini'
DEFINE llm_api_key  = 'REPLACE_ME_WITH_REAL_KEY'

SET DEFINE ON
SET SERVEROUTPUT ON SIZE UNLIMITED

-- 1) Drop + recreate the credential (idempotent)
BEGIN
    BEGIN
        DBMS_CLOUD.DROP_CREDENTIAL(credential_name => 'GRANDBACK_LLM_CREDENTIAL');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    DBMS_CLOUD.CREATE_CREDENTIAL(
        credential_name => 'GRANDBACK_LLM_CREDENTIAL',
        username        => 'API_KEY',
        password        => '&llm_api_key'
    );
    DBMS_OUTPUT.PUT_LINE('✓ Credential GRANDBACK_LLM_CREDENTIAL ready.');
END;
/

-- 2) Drop + recreate the Select AI profile, grounded to the GRANDBACK_* tables
--    so the LLM only sees objects it should be reasoning about.
BEGIN
    BEGIN
        DBMS_CLOUD_AI.DROP_PROFILE(profile_name => 'GRANDBACK_BOT_PROFILE');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    DBMS_CLOUD_AI.CREATE_PROFILE(
        profile_name => 'GRANDBACK_BOT_PROFILE',
        attributes   => '{
            "provider":        "&llm_provider",
            "model":           "&llm_model",
            "credential_name": "GRANDBACK_LLM_CREDENTIAL",
            "object_list": [
                {"owner":"GRANDBACK_SCHEMA","name":"GRANDBACK_PROPERTIES"},
                {"owner":"GRANDBACK_SCHEMA","name":"GRANDBACK_VENDORS"},
                {"owner":"GRANDBACK_SCHEMA","name":"GRANDBACK_CUSTOMERS"},
                {"owner":"GRANDBACK_SCHEMA","name":"GRANDBACK_AP_INVOICES"},
                {"owner":"GRANDBACK_SCHEMA","name":"GRANDBACK_AR_INVOICES"},
                {"owner":"GRANDBACK_SCHEMA","name":"GRANDBACK_GL_ACCOUNTS"},
                {"owner":"GRANDBACK_SCHEMA","name":"GRANDBACK_JOURNAL_ENTRIES"},
                {"owner":"GRANDBACK_SCHEMA","name":"GRANDBACK_JOURNAL_LINES"},
                {"owner":"GRANDBACK_SCHEMA","name":"GRANDBACK_BANK_ACCOUNTS"},
                {"owner":"GRANDBACK_SCHEMA","name":"GRANDBACK_BANK_TXNS"},
                {"owner":"GRANDBACK_SCHEMA","name":"GRANDBACK_FIXED_ASSETS"}
            ],
            "comments": "true",
            "system_message": "You are the Grandback Corporate Finance assistant. You query AP, AR, GL and journal data. You only generate SELECT statements — never DML or DDL. Always filter by the user''s current property scope. Refuse cross-property queries when the user is not an admin."
        }'
    );
    DBMS_OUTPUT.PUT_LINE('✓ Profile GRANDBACK_BOT_PROFILE created and grounded.');
END;
/

-- 3) Smoke test (commented out — uncomment after the credential is real).
-- DECLARE v_out CLOB;
-- BEGIN
--     v_out := DBMS_CLOUD_AI.GENERATE(
--         prompt       => 'Which property has the highest total unpaid AR amount?',
--         profile_name => 'GRANDBACK_BOT_PROFILE',
--         action       => 'narrate'
--     );
--     DBMS_OUTPUT.PUT_LINE(v_out);
-- END;
-- /

UNDEFINE llm_provider
UNDEFINE llm_model
UNDEFINE llm_api_key
