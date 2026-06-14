-- =====================================================================
-- Grandback (EBS) Finance Bot — single deploy entrypoint
--
-- Run from SQLcl (or Database Actions → SQL) AS the GRANDBACK_SCHEMA user
-- (or ADMIN, for the trial). Installs schema + packages, runs the test
-- suite, then publishes the ORDS REST module.
--
--   sql /nolog
--   SQL> connect grandback_schema/<pwd>@<tns>
--   SQL> @deploy_all.sql
--
-- Select AI (06) is intentionally NOT auto-run — it needs a real LLM key.
-- Run it manually after editing the DEFINEs:  @06_setup_select_ai.sql
-- =====================================================================

SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR CONTINUE

PROMPT ====================================================================
PROMPT 1/5  Schema + seed data ...
@@01_schema_install.sql

PROMPT ====================================================================
PROMPT 2/5  Security / IAM package ...
@@02_grandback_iam_pkg.sql

PROMPT ====================================================================
PROMPT 3/5  Bot engine package ...
@@03_grandback_bot_pkg.sql

PROMPT ====================================================================
PROMPT 4/5  AJAX wrapper package ...
@@04_grandback_bot_api_pkg.sql

PROMPT ====================================================================
PROMPT 5/5  Unit test suite (review for ALL TESTS PASSED) ...
@@07_test_grandback_bot.sql

PROMPT ====================================================================
PROMPT Compilation status (expect no rows / all VALID):
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name LIKE 'GRANDBACK\_%' ESCAPE '\'
   AND status != 'VALID';

PROMPT ====================================================================
PROMPT Now publish the ORDS REST API (requires ORDS on the instance):
PROMPT    @@05_ords_rest_grandback.sql
PROMPT Optional NLQ (needs LLM key):
PROMPT    edit + @@06_setup_select_ai.sql
PROMPT ====================================================================
