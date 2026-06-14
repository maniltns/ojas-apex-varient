# Technical Requirements Document (TRD) — ACCOR EBS Conversational Bot

> **RFP alignment note.** This document refers to **ACCOR Grandback** (the client's Oracle EBS 12.2.12
> landscape). Code identifiers use the `GRANDBACK_*` prefix. The solution is delivered in three RFP
> phases — Phase 1 (API-first / dynamic analytics, 80 use cases), Phase 2 (Knowledge & Context /
> Vector Search, 30), Phase 3 (Agentic AI, 12). This POC builds a representative **Phase 1** subset.
> Canonical references: [POC_IMPLEMENTATION_PLAN.md](POC_IMPLEMENTATION_PLAN.md) ·
> [RFP_TRACEABILITY.md](RFP_TRACEABILITY.md).

This document outlines the technical specification, database structures, and PL/SQL integration layers for the native Oracle APEX and OCI Autonomous Database solution.

---

## 1. Technical Stack

* **Platform Hosting:** OCI Autonomous Database 23ai Serverless & Oracle APEX Service (Always Free / Enterprise Tier).
* **Database Schema:** `GRANDBACK_SCHEMA`
* **Orchestrator Backend:** Stored PL/SQL Packages (`GRANDBACK_BOT_PKG` and `GRANDBACK_IAM_PKG`).
* **Generative AI Integration:** Native `DBMS_CLOUD_AI` (Select AI) executing stateless prompt translation via private endpoint to LLM (OCI Generative AI or external APIs like OpenAI).
* **APEX App Specification:** APEXlang declaratives (`.apx`) managed in local files.

---

## 2. Database Models & Schema

The schema includes the following tables defined in `01_schema_install.sql`:

```mermaid
classDiagram
    class GRANDBACK_PROPERTIES {
        VARCHAR2 property_id
        VARCHAR2 name
        VARCHAR2 brand
        VARCHAR2 city
        VARCHAR2 country
        VARCHAR2 currency
        VARCHAR2 status
    }
    class GRANDBACK_USERS {
        VARCHAR2 user_id
        VARCHAR2 email
        VARCHAR2 name
        VARCHAR2 password_hash
        VARCHAR2 role
        VARCHAR2 ebs_role
        VARCHAR2 property_access
        VARCHAR2 org_id
        TIMESTAMP created_at
    }
    class GRANDBACK_AP_INVOICES {
        VARCHAR2 invoice_id
        VARCHAR2 invoice_number
        VARCHAR2 vendor_id
        VARCHAR2 property_id
        NUMBER amount
        VARCHAR2 currency
        DATE invoice_date
        DATE due_date
        VARCHAR2 status
        VARCHAR2 description
    }
    class GRANDBACK_CONVERSATIONS {
        VARCHAR2 conversation_id
        VARCHAR2 user_id
        VARCHAR2 thread_id
        VARCHAR2 role
        VARCHAR2 message_content
        TIMESTAMP timestamp
    }
    class GRANDBACK_AUDIT_LOG {
        VARCHAR2 log_id
        VARCHAR2 user_id
        VARCHAR2 email
        VARCHAR2 action_type
        VARCHAR2 query_text
        VARCHAR2 status
        VARCHAR2 reason
        TIMESTAMP timestamp
    }

    GRANDBACK_AP_INVOICES --> GRANDBACK_PROPERTIES : references
    GRANDBACK_CONVERSATIONS --> GRANDBACK_USERS : references
```

---

## 3. IAM Validation & Security Logic (`GRANDBACK_IAM_PKG`)

Every request processed by the orchestrator is validated by `GRANDBACK_IAM_PKG.validate_action(p_email, p_ebs_role, p_action, p_property_id)`:

1. **Role Gating:**
   * User role `finance_analyst` (EBS Role: `Finance Analyst`) is locked to read-only queries. If an analyst requests a `write` operation (e.g. approve invoice, confirm transaction), the package immediately rejects the request.
   * User role `finance_manager` is authorized to initiate payment workflows.
2. **Property Boundaries:**
   * A user's assigned property scope is stored as a comma-separated list of IDs in `GRANDBACK_USERS.property_access`.
   * The package checks if `p_property_id` is contained within the access string. If not found, access is denied.
   * Admins (`admin` role) bypass property restrictions.
3. **Injection Guardrails:**
   * `GRANDBACK_IAM_PKG.detect_injection` inspects the text body.
   * Blocks payloads containing:
     * SQL Injection signatures (`OR 1=1`, `UNION SELECT`, `DROP TABLE`, `--`).
     * Jailbreak attempt phrases (`IGNORE PREVIOUS INSTRUCTIONS`, `IGNORE SYSTEM RULES`, `SYS.DBMS_OUTPUT`).
   * Threat incidents are logged inside `GRANDBACK_AUDIT_LOG` using an **Autonomous Transaction** (safeguarding threat records from rollback operations).

---

## 4. Chat State & LLM Integration (`GRANDBACK_BOT_PKG`)

Conversation state is managed statelessly in the database:
* Conversation threads are stored in `GRANDBACK_CONVERSATIONS`.
* The main loop parses predefined keywords for quick-action reports:
  * `"AP Aging"` -> Runs local sub-queries returning overdue AP markdown lists.
  * `"GL Balance"` -> Summarizes Chart of Accounts balances.
  * `"Consolidated Summary"` -> Compiles multi-property portfolio statistics.
* **Gated Payment Confirmation:**
  * Managers requesting to pay/approve an invoice receive an inline confirmation modal response.
  * Actual database DML modifications only execute when the manager replies with an explicit `CONFIRM` prompt on the same thread.
* **Select AI Fallback:**
  * Generic prompts fall back to `DBMS_CLOUD_AI.GENERATE` which interfaces directly with the tenancy's configured Select AI Profile (`GRANDBACK_BOT_PROFILE`) to return dynamic LLM responses.
