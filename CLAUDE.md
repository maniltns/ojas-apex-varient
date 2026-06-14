# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Native Oracle APEX + OCI Autonomous Database 23ai POC for the **ACCOR Grandback (EBS) Finance Conversational Bot**. Everything runs inside the database — there is no separate API/middle tier. The "agent" is a PL/SQL package; the UI is an APEXlang-declared APEX app loading a custom HTML/JS chat shell that talks to four AJAX callbacks (and an ORDS REST API for the API-first layer) on the application.

## Common Commands

APEXlang validation/lint (run from repo root, requires `node`):

```bash
node .agents/skills/apex/apexlang/tools/apexctl.mjs apexlang validate --app-path applications/accor_ebs_bot
node .agents/skills/apex/apexlang/tools/apexctl.mjs apexlang compiler-truth audit --app-path applications/accor_ebs_bot
```

Database deploy order (run via SQLcl or APEX SQL Workshop → SQL Commands against `GRANDBACK_SCHEMA`):

1. `backend/database/01_schema_install.sql` — drops/recreates 15 `GRANDBACK_*` tables (AP/AR/GL/CM/FA) and reseeds demo data incl. 5 RFP personas
2. `backend/database/02_grandback_iam_pkg.sql` — `GRANDBACK_IAM_PKG`
3. `backend/database/03_grandback_bot_pkg.sql` — `GRANDBACK_BOT_PKG`
4. `backend/database/04_grandback_bot_api_pkg.sql` — `GRANDBACK_BOT_API_PKG` (thin AJAX wrapper)
5. `backend/database/05_ords_rest_grandback.sql` — publishes ORDS REST module `grandback/v1` (run as `GRANDBACK_SCHEMA`)
6. `backend/database/07_test_grandback_bot.sql` — runs the assertion suite via `DBMS_OUTPUT`
   *(or just run `backend/database/deploy_all.sql` which `@`-includes 01–04 and 07 in order)*
7. *(optional)* `backend/database/06_setup_select_ai.sql` — only when you have an LLM API key; the bot package compiles and runs without it

## Architecture

### Request flow
APEX page → `apex.server.process('LOAD_BOOTSTRAP' | 'PROCESS_CHAT' | 'CANCEL_APPROVAL' | 'LOAD_GOV_KPIS', ...)` → application-process callback (`shared-components/app-processes.apx`) → `GRANDBACK_BOT_API_PKG.<proc>` → JSON response. The four AJAX callbacks are application-process scoped (point: `ajaxCallback`), each gated by an authorization scheme.

`process_chat` flow inside the package follows a fixed pipeline:

1. **User-context resolve** — `GRANDBACK_IAM_PKG.get_user_context` looks up `GRANDBACK_USERS` by email *or* short username (`UPPER(email) = UPPER(p_email) OR UPPER(email) LIKE UPPER(p_email) || '@%'`). The short-username case is load-bearing and the test suite asserts it.
2. **Length guard** — `is_message_too_long` rejects > 4000 chars.
3. **Injection screen** — `detect_injection` matches SQLi (`OR 1=1`, `UNION SELECT`, `EXECUTE IMMEDIATE`, `DBMS_SQL`, `--`, …), prompt-injection (`IGNORE PREVIOUS INSTRUCTIONS`, `YOU ARE NOW`, `DEVELOPER MODE`, …), and HTML-vector patterns (`<script`, `javascript:`, `onerror=`). Hits go to `GRANDBACK_AUDIT_LOG` via an autonomous transaction so the threat record survives later rollback.
4. **Action classification** — keywords `APPROVE`/`CONFIRM`/`PAY` flag the action as `write`, otherwise `read`.
5. **IAM gate** — `validate_action`: analysts can only `read`; non-admins must have `property_id` inside `GRANDBACK_USERS.property_access` (comma-separated); `admin` bypasses property checks.
6. **Intent dispatch** — keyword routing to: `format_ap_aging`, `format_ar_aging`, `format_overdue`, `format_gl_balances`, `format_consolidated_summary`, `format_journal_status`, `format_property_summary`, `format_vendor_lookup`, plus Phase-1 module formatters (`format_cash_position`, `format_unreconciled`, `format_assets`, `format_trial_balance`, `format_supplier_risk`, `format_customer_balance`, `format_expense_trend`), gated payment, `CONFIRM` handler, or Select AI fallback.

### Gated payment flow
**Two-step handshake** backed by the `GRANDBACK_PENDING_APPROVALS` table (replaces the old conversation-string-scan approach):

- First message (`approve payment for ap_inv_1001`) → bot inserts a `pending` row keyed on `(thread_id, user_id)` with `expires_at = SYSTIMESTAMP + 15 min`, returns `requires_approval: true` and the payload (incl. `approval_id`). **No DML runs.**
- Follow-up `CONFIRM` → bot picks the most recent non-expired `pending` row for the thread/user, marks it `confirmed`, runs the UPDATE. Expired rows return a clean error. Cancellation goes through `cancel_pending_approval` (the modal Esc/Cancel handler).
- Sending a new approve-request automatically cancels any prior pending row on the same thread.

### Roles & session bootstrap
After APEX login (`afterAuthentication` app process) `GRANDBACK_BOT_PKG.bootstrap_user_session` populates application items: `G_USER_ID`, `G_USER_NAME`, `G_USER_ROLE`, `G_EBS_ROLE`, `G_PROPERTY_ACCESS`, `G_THREAD_ID`. The chat client and the user-scoped LOV (`properties-for-user-lov`) read from these — there are no hardcoded roles in page processes any more.

Roles: `finance_analyst` (read-only, scoped) · `finance_manager` (read+write within scope) · `admin` (bypasses property scope, sees admin nav). Authorizations live in `shared-components/authorizations.apx` — `administration-rights`, `manager-or-admin`, `authenticated-finance-user`, all `plSqlFunctionBody` against `GRANDBACK_USERS`.

### Authentication
APEX Accounts (built-in), not `GRANDBACK_USERS`. `GRANDBACK_USERS.password_hash` stores a sentinel value (`managed_by_apex_accounts`) and is unused — the table is a profile/role registry only. Don't add bcrypt or custom auth here unless you also rip out APEX Accounts.

### Select AI fallback (important)
`DBMS_CLOUD_AI.GENERATE` is invoked via `EXECUTE IMMEDIATE` so the package compiles cleanly on instances without `DBMS_CLOUD_AI` or with no `GRANDBACK_BOT_PROFILE`. The `WHEN OTHERS` branch returns a static help message styled to match the chat UI. Don't rewrite this as a static call.

### HTML, not Markdown
Bot replies are HTML (`<table class="ebs-table">`, `<span class="ebs-pill ebs-pill--success">`, etc.) injected into chat bubbles. The client (`static-files/js/ebs-bot.js`) sanitises every bot reply through a tag-allowlist before rendering — when adding new tags or attributes to PL/SQL formatters, remember to extend `ALLOWED_TAGS` in the JS or they'll be stripped. User messages are escaped server-side before persisting.

### Schema
15 tables, all prefixed `GRANDBACK_`. The drop loop in `01_schema_install.sql` targets `GRANDBACK_%` — any new table you add must follow this prefix or it'll be orphaned across re-runs. `GRANDBACK_AUDIT_LOG` was extended with `role`, `property_id`, `intent`, `session_id`, `request_ip` columns; `GRANDBACK_PENDING_APPROVALS` is the state table for gated DML. CM/FA coverage adds `GRANDBACK_BANK_ACCOUNTS`, `GRANDBACK_BANK_TXNS`, `GRANDBACK_FIXED_ASSETS`.

## UI

Single chat UI: **`pages/p00002-chat.apx`** with one static-content region hosting the entire shell, plus the modal at page level. Styling lives in [`shared-components/static-files/css/ebs-bot.css`](applications/accor_ebs_bot/shared-components/static-files/css/ebs-bot.css), client logic in [`shared-components/static-files/js/ebs-bot.js`](applications/accor_ebs_bot/shared-components/static-files/js/ebs-bot.js). Both are pulled into pages via inline `<link>` and `<script>` tags inside the static-content region (we don't hook them at the application level — that construct isn't in the APEXlang vocabulary).

Visual direction (as implemented in `ebs-bot.css`): **modern neutral dark** (linear.app/vercel) — `#0a0a0a` / `#111113` / `#ededed`, lime-green `#aac92a` accent. *(Note: `UI_UX_Design.md` documents an alternative navy+gold light theme; the dark theme in `ebs-bot.css` is the source of truth for the build.)*, white-on-black accent button, Inter + tabular numerals, status pills with semantic colour, monospace quick-action chips. The admin page (`p00003-admin.apx`) gets a KPI strip + three Interactive Reports (Users, Audit Log, Blocked Security Events), all themed via the same CSS through a `body.ebs-shell-active` class added by inline JS in the KPI region.

Superseded manual-paste scripts have been moved to `backend/database/_legacy/` — don't reference them from new work.

## APEXlang notes

- App is at `applications/accor_ebs_bot/` (declarative `.apx` files, mmdVersion `26.1.0+3102`, `compatibilityMode: 24.2`). Workspace `GRANDBACK_DEV`, app id 43171.
- The skill at `.agents/skills/apex/apexlang/` is the source of truth for valid syntax — read `apex/apexlang/references/workflows/apex-generation.md` and the `templates/` directory before adding new pages or shared components.
- **Keep inline PL/SQL under 4000 chars** — that's a hard validator failure. New AJAX callbacks should call `GRANDBACK_BOT_API_PKG` (or a similar wrapper), not inline logic.
- **`appProcess` only supports `type: executeCode`** — `invokeApi` is a *page* process type, not an app process type. Wrapper packages bridge the gap.
- **Static files** are referenced via `#APP_FILES#` (`#APP_FILES#css/ebs-bot.css`). They must be declared in `shared-components/static-files.apx` *and* the actual file must exist under `shared-components/static-files/`.
