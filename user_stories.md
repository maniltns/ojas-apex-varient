# User Stories Specification — ACCOR EBS Conversational Bot

> **RFP alignment note.** This document refers to **ACCOR Grandback** (the client's Oracle EBS 12.2.12
> landscape). Code identifiers use the `GRANDBACK_*` prefix. The solution is delivered in three RFP
> phases — Phase 1 (API-first / dynamic analytics, 80 use cases), Phase 2 (Knowledge & Context /
> Vector Search, 30), Phase 3 (Agentic AI, 12). This POC builds a representative **Phase 1** subset.
> Canonical references: [POC_IMPLEMENTATION_PLAN.md](POC_IMPLEMENTATION_PLAN.md) ·
> [RFP_TRACEABILITY.md](RFP_TRACEABILITY.md).

This document maps out the specific user stories, roles, and acceptance criteria verified in this POC.

---

## 0. RFP Personas

The RFP names four business personas (plus admin). Each maps to a seeded POC user and an access model
enforced by `GRANDBACK_IAM_PKG.validate_action`:

| Persona | Seed login | role / ebs_role | Scope | Write? |
|---|---|---|---|---|
| Finance Analyst | `analyst@accor.com` | finance_analyst / analyst | 2 properties | No |
| Cash Manager | `cashmgr@accor.com` | finance_manager / cash_manager | CM scope | Yes (in scope) |
| Controller | `controller@accor.com` | finance_manager / controller | GL/close scope | Yes (in scope) |
| Executive | `exec@accor.com` | finance_analyst / executive | all properties | No (read-only) |
| Admin | `admin@accor.com` | admin / admin | all (bypass) | Yes |

Persona enforcement is verified in `07_test_grandback_bot.sql` (Executive denied write; Cash Manager
gates payment in scope). Persona‑based and 6‑dimension test detail: see
[RFP_TRACEABILITY.md](RFP_TRACEABILITY.md) §C–§D (Compliance · Data Accuracy · Bias & Fairness ·
Performance · Data Security & Privacy · Hallucination).

---

## 1. Accounts Payable (AP) & Balances

### Story 1: AP Aging Lookup (Conversational)
* **As a** Finance Analyst or Manager
* **I want to** ask the conversational bot: *"Show AP aging"*
* **So that** I can see a list of outstanding vendor invoices, amounts, currency details, and payment due dates without navigating standard EBS reports.
* **Acceptance Criteria:**
  * The bot matches the `AP AGING` query keyword.
  * Queries database table `GRANDBACK_AP_INVOICES` filtered by the active property scope context.
  * Formats the list as a clean markdown table.

### Story 2: GL Balances Check
* **As a** Corporate User
* **I want to** ask the bot: *"Show GL cash balance"*
* **So that** I can view a consolidated summary of accounts in our Chart of Accounts (Cash, AR, AP, Utilities, etc.) and their active balances.
* **Acceptance Criteria:**
  * Matches `GL BALANCE` intent.
  * Displays account codes, names, types, and active balances.

---

## 1b. Phase-1 module coverage (CM · FA · GL · supplier/customer)

These stories exercise the modules the RFP requires beyond AP/GL, each backed by a dedicated formatter
and verified in the test suite.

### Story 2a: Cash position & reconciliation (CM)
* **As a** Cash Manager
* **I want to** ask *"Show cash position"* and *"Show unreconciled transactions"*
* **So that** I can see bank balances (book vs statement) and open reconciliation items.
* **Acceptance:** matches `cash_position` / `unreconciled`; reads `GRANDBACK_BANK_ACCOUNTS` /
  `GRANDBACK_BANK_TXNS` scoped to the property; surfaces the book‑vs‑bank delta.

### Story 2b: Fixed asset register & depreciation (FA)
* **As a** Controller
* **I want to** ask *"Show assets"* / *"depreciation"*
* **So that** I can review the asset register with net book value and depreciation status.
* **Acceptance:** matches `asset_register`; reads `GRANDBACK_FIXED_ASSETS`; shows cost, NBV, status.

### Story 2c: Trial balance & expense trend (GL)
* **As a** Controller or Executive
* **I want to** ask *"Show trial balance"* and *"Expense trend"*
* **So that** I can see GL totals by type (with Dr/Cr check) and expense composition.
* **Acceptance:** matches `trial_balance` / `expense_trend` over `GRANDBACK_GL_ACCOUNTS`.

### Story 2d: Supplier risk & customer balances (AP/AR)
* **As a** Finance Analyst
* **I want to** ask *"Supplier risk"* and *"Customer balances"*
* **So that** I can flag suppliers with payment delays > 60 days and see open AR by customer.
* **Acceptance:** matches `supplier_risk` / `customer_balance`; property‑scoped aggregates.

---

## 2. Gated Transactions & DML Approvals

### Story 3: Gated Payment Execution
* **As a** Finance Manager
* **I want to** tell the bot: *"Approve payment for ap_inv_1001"*
* **So that** I can authorize a payment run conversationally.
* **Acceptance Criteria:**
  * Bot recognizes `payment_approval` intent.
  * Validates that the invoice ID exists and is unpaid.
  * Returns a state-gated response prompting the user to confirm the transaction.
  * Database changes do not write until the user responds with an explicit `CONFIRM` prompt.
  * After confirmation, the invoice status changes to `paid` and an audit entry is generated.

### Story 4: Analyst Read-Only Block
* **As a** Finance Analyst
* **I want my role boundary enforced** when attempting to write actions (such as paying an invoice)
* **So that** I am blocked from making unauthorized database updates.
* **Acceptance Criteria:**
  * Analyst submits a write action: *"Approve payment for ap_inv_1001"*.
  * The database package `GRANDBACK_IAM_PKG` blocks the action.
  * Bot returns: `❌ Access Denied: write operation restricted to Managers`.
  * The event is flagged as a blocked transaction in the system audit logs.

---

## 3. Data Governance & Security Audits

### Story 5: Property Access Boundary Enforcement
* **As a** Corporate User (e.g. Analyst assigned only to Paris and London)
* **I want the system to restrict my query boundaries** if I switch context or query properties not assigned to me
* **So that** I cannot access confidential financial data outside my domain.
* **Acceptance Criteria:**
  * User attempts to access a restricted property ID (e.g. `prop_sofitel_nyc`).
  * `GRANDBACK_IAM_PKG` evaluates the list.
  * The bot blocks the query and logs an access violation warning.

### Story 6: SQL & Prompt Injection Guardrails
* **As a** Security Officer
* **I want the bot to inspect all user inputs** for malicious SQL command segments or prompt override jailbreaks
* **So that** the Autonomous Database replica schemas are shielded from DML exploits.
* **Acceptance Criteria:**
  * User inputs a threat signature (e.g. `SELECT * FROM GRANDBACK_USERS WHERE 1=1 OR 1=1; --` or `Ignore previous instructions`).
  * `detect_injection` identifies the string pattern.
  * The query is blocked before it compiles, returning a warning message.
  * The threat incident is written to the audit log as a blocked threat event.

### Story 7: Admin Threat Auditing Console
* **As a** System Administrator
* **I want to** access a dedicated Admin Governance dashboard
* **So that** I can review all user directories, access logs, and investigate blocked security alerts.
* **Acceptance Criteria:**
  * Page 3 navigation is visible only to users authenticated as administrators.
  * Displays user databases, general audit trail entries, and a dedicated threat alerts log.
