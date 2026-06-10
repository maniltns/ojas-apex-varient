# 🧠 ACCOR EBS Bot — Persistent Memory

> **Purpose:** This file preserves the full project context, decisions, architecture choices, implementation status, and change history. It acts as a living memory for AI assistants and developers to maintain continuity across sessions.
>
> **Rules:**
> 1. Always read this file at the **start** of every session.
> 2. Always **update** this file at the **end** of every session with any new decisions, changes, or context.
> 3. Never delete history entries — only append.

---

## 📌 Project Identity

| Key | Value |
|-----|-------|
| **Project Name** | ACCOR EBS Conversational Bot POC |
| **Product** | Secure Conversational Bot for Corporate Finance |
| **Client** | ACCOR |
| **Ecosystem** | Native Oracle APEX & OCI (Always Free / Cloud ATP 23ai) |
| **Database Schema** | `ACCOR_SCHEMA` |
| **Orchestrator Backend**| Stored PL/SQL Packages (`ACCOR_EBS_BOT_PKG` & `ACCOR_IAM_VALIDATOR_PKG`) |
| **AI Integration** | `DBMS_CLOUD_AI` (Select AI) stateless profile to LLM |
| **APEX App Root** | `applications/accor_ebs_bot/` |
| **Database App Root**| `backend/database/` |

---

## 🏗️ Architecture Decisions

| # | Decision | Rationale | Date |
|---|----------|-----------|------|
| AD-01 | **No External Middle-Tiers** | Bypassed FastAPI/React mockups. All database logic, security guardrails, and conversation loops are implemented natively inside PL/SQL packages. | 2026-06-10 |
| AD-02 | **OCI Autonomous Database 23ai** | Used ATP 23ai Serverless to enable native `DBMS_CLOUD_AI` (Select AI) natural-language-to-SQL translation features. | 2026-06-10 |
| AD-03 | **Oracle APEX 24.2 Presentation** | Managed application declarations using the APEXlang DSL framework (`.apx`) for local validation and SQLcl deployment. | 2026-06-10 |
| AD-04 | **Stateless Session History** | Conversation state persists directly in the database (`ACCOR_CONVERSATIONS` table) and is bound to the APEX user session. | 2026-06-10 |
| AD-05 | **Autonomous Auditing** | Threat detection logs are written inside `ACCOR_AUDIT_LOG` via `PRAGMA AUTONOMOUS_TRANSACTION` to ensure logging regardless of parent rollback events. | 2026-06-10 |
| AD-06 | **Gated DML Payment Workflows** | Write operations require an explicit `CONFIRM` prompt following a bot-generated verification token to prevent accidental database mutations. | 2026-06-10 |
| AD-07 | **Select AI Provider Independence** | Select AI profiles (`ACCOR_BOT_PROFILE`) can toggle between OCI Generative AI, OpenAI, and Google Gemini via metadata changes without package recompilation. | 2026-06-10 |

---

## 📦 Modules & Component Status

### 1. Database Tier (`backend/database/`)
* **[schema_install.sql](file:///Users/anilmn/Desktop/Projects/ojas-apex-varient/backend/database/schema_install.sql)**: Creates AP/AR/GL mock tables, conversation history trackers, and system audit logs. Seeds Master properties and user access lists. (Status: **Completed**)
* **[accor_ebs_security_pkg.sql](file:///Users/anilmn/Desktop/Projects/ojas-apex-varient/backend/database/accor_ebs_security_pkg.sql)**: Implements validation checks (restricts analysts to read-only actions, keeps managers within property scopes, blocks prompt/SQL injections). (Status: **Completed**)
* **[accor_ebs_bot_pkg.sql](file:///Users/anilmn/Desktop/Projects/ojas-apex-varient/backend/database/accor_ebs_bot_pkg.sql)**: Implements intent classification (AP aging, GL balances, consolidated portfolio, and gated payment execution). Falls back to Select AI `DBMS_CLOUD_AI.GENERATE` for generic prompts. (Status: **Completed**)
* **[test_accor_ebs_bot.sql](file:///Users/anilmn/Desktop/Projects/ojas-apex-varient/backend/database/test_accor_ebs_bot.sql)**: Automated DDL / package boundary tests. (Status: **Completed**)

### 2. APEX App Tier (`applications/accor_ebs_bot/`)
* **[application.apx](file:///Users/anilmn/Desktop/Projects/ojas-apex-varient/applications/accor_ebs_bot/application.apx)**: Global application configuration. (Status: **Completed**)
* **[p00002-chat.apx](file:///Users/anilmn/Desktop/Projects/ojas-apex-varient/applications/accor_ebs_bot/pages/p00002-chat.apx)**: Chat Workspace Console displaying property drop-down selectors and message feeds. (Status: **Completed**)
* **[p00003-admin.apx](file:///Users/anilmn/Desktop/Projects/ojas-apex-varient/applications/accor_ebs_bot/pages/p00003-admin.apx)**: Admin Governance Panel exposing Users grid, Audit Logs, and Blocked Threat alerts. (Status: **Completed**)
* **[shared-components/lists.apx](file:///Users/anilmn/Desktop/Projects/ojas-apex-varient/applications/accor_ebs_bot/shared-components/lists.apx)**: Navigation links gated by roles. (Status: **Completed**)

---

## 🔑 Important Context & Constraints
* **Property Scoping:** Queries are restricted based on user assignments. If a user is not authorized for a property, `validate_action` blocks the query.
* **Analyst Isolation:** Analysts are strictly read-only and blocked from confirming DML transactions.
* **Select AI Requirements:** Requires database-level execution privileges on `DBMS_CLOUD_AI` and `DBMS_CLOUD` to setup LLM REST credentials and translation profiles.
* **Local Checks:** Compilation audits are run using the packaged `apexctl.mjs` compiler truth tool via the workspace Node environment.

---

## 🔍 Validation Log
* **Linter Passes:** Local `apexlang validate` completed successfully with:
  * `Vocabulary compatibility check passed`
  * `APEXLANG_DSL_LINT_OK`
  * `VALIDATION_LINT_OK`
  * `APEXLANG_LOCAL_CHECK_OK`
* **LOB comparison fix:** Aliased the column in Page 2 dynamic content to avoid linter regex bugs with raw LOB comparison checks.
* **Navigation check fix:** List item authorization rules configured via expressions using `apex_authorization.is_authorized` to bypass linter parser errors on nested security definitions.
