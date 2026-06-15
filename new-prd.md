# Grandback (EBS) Finance Conversational Assistant — Product Requirements (POC)

> **Scope note.** This PRD describes the **native Oracle** POC as actually built — Oracle APEX +
> OCI Autonomous Database 23ai, with all logic in PL/SQL packages and an ORDS REST API. It supersedes
> an earlier draft that described an external multi-agent (OpenAI/Anthropic) + MongoDB design; that
> design was **never built** and does not reflect the architecture. See
> [POC_IMPLEMENTATION_PLAN.md](POC_IMPLEMENTATION_PLAN.md) and [RFP_TRACEABILITY.md](RFP_TRACEABILITY.md).

## 1. Overview

A secure, role-aware conversational assistant over **ACCOR Grandback** (the client's Oracle **EBS
12.2.12** finance landscape — AP, AR, GL, CM, FA across a MOAC environment, 18 countries, 1000+
finance users). For the POC the EBS data is represented by seeded `GRANDBACK_*` tables in OCI ATP
23ai; the conversational layer, security guardrails, audit logging and gated‑write workflow are fully
implemented in PL/SQL and surfaced through both an **Oracle APEX** UI and an **ORDS REST API**.

The bot is delivered in three phases (RFP):

- **Phase 1 — API‑first / Dynamic financial analytics (80 use cases).** Semantic API/query access via
  ORDS + Select AI/NLQ. **This POC implements a representative Phase‑1 subset across all five modules.**
- **Phase 2 — Knowledge & Context Intelligence (30).** Oracle Vector Search, statistical reasoning,
  forecasting. *Roadmap.*
- **Phase 3 — Agentic AI (12 agents).** Autonomous workflow orchestration, self‑healing
  reconciliation, finance copilot. *Roadmap.*

## 2. Personas & user stories

| Persona (RFP) | Story |
|---|---|
| **Finance Analyst** (read‑only, scoped) | Query AP/AR aging, GL balances, invoice status conversationally without navigating EBS forms. |
| **Cash Manager** (write in scope) | Review cash position / bank balances, unreconciled items; act on payments via guided chat. |
| **Controller** (write in scope) | View trial balance, journal status, multi‑property consolidations; approve entries. |
| **Executive** (read‑only, all properties) | Monitor consolidated portfolio health across brands and countries. |
| **Admin** | Manage the user registry, review audit logs and blocked security events for compliance. |

Permissions are enforced automatically: read‑only personas cannot trigger writes; non‑admins are
limited to their `property_access` scope; admins bypass scope.

## 3. Architecture (as built)

**Pattern:** in‑database orchestration. There is no external agent runtime and no separate app tier.

```
Browser / REST client
   │  (APEX AJAX  |  ORDS REST /grandback/v1/*)
   ▼
GRANDBACK_BOT_API_PKG (APEX JSON wrapper)   ·   ORDS handlers (REST)
   ▼
GRANDBACK_BOT_PKG.process_chat_message  — 6-step pipeline:
   0 length guard → 1 injection screen → 2 action classify (read/write)
   → 3 IAM gate → 4 intent dispatch → 5/6 persist + audit
   ├── GRANDBACK_IAM_PKG  (get_user_context · validate_action · detect_injection · log_audit)
   ├── 15 HTML formatters (AP/AR/GL/CM/FA + consolidated/vendor/etc.)
   ├── gated-payment handshake  (GRANDBACK_PENDING_APPROVALS, two-step CONFIRM)
   └── Select AI / NLQ fallback (DBMS_CLOUD_AI.GENERATE, SELECT-only, grounded) → static help if absent
   ▼
GRANDBACK_* tables on OCI ATP 23ai  (+ GRANDBACK_AUDIT_LOG autonomous-tx)
```

The "agents" the RFP describes for Phase 3 map onto the per‑module formatters today (AP/AR/GL/CM/FA);
splitting them into independently‑versioned agent packages with a tool registry is the Phase‑3 target.

## 4. Data model (as built)

15 `GRANDBACK_*` tables. Core: `PROPERTIES`, `USERS` (profile/role registry — auth is APEX Accounts,
`password_hash` is a sentinel), `VENDORS`, `CUSTOMERS`, `AP_INVOICES`, `AR_INVOICES`, `GL_ACCOUNTS`,
`JOURNAL_ENTRIES`, `JOURNAL_LINES`. Conversational/governance: `CONVERSATIONS`, `AUDIT_LOG`
(role/property/intent/IP, autonomous tx), `PENDING_APPROVALS` (gated‑DML state machine). Phase‑1
module coverage: `BANK_ACCOUNTS`, `BANK_TXNS` (CM), `FIXED_ASSETS` (FA).

**Roles:** `admin` (full), `finance_manager` (read+write in scope — Cash Manager, Controller),
`finance_analyst` (read‑only — Analyst, Executive). `ebs_role` carries the RFP persona label.

## 5. Authentication

Oracle **APEX Accounts** (built‑in) for the UI; the ORDS API takes the persona via the request
(`email`) and can be locked behind an OAuth2 client‑credentials role. `GRANDBACK_USERS` is a
profile/role registry keyed on email, hydrated post‑login by `bootstrap_user_session`. Production path
is **OCI Identity Domains** federated SSO with EBS role mapping (roadmap).

## 6. Key flows

1. **Read query** — "Show AP aging for Novotel Paris" → guard → IAM (read allowed, property in scope)
   → `format_ap_aging` → HTML table rendered (sanitised by allowlist) + audit row.
2. **Gated write** — manager "Approve payment for ap_inv_1001" → IAM (write allowed in scope) →
   `create_pending_approval` (15‑min TTL, **no DML**) → confirmation modal → "CONFIRM" → UPDATE +
   `DML_EXECUTION` audit. Analyst/Executive are blocked at the IAM gate.
3. **Blocked** — injection / prompt‑injection / XSS or out‑of‑scope → denial message + `blocked` audit
   row (autonomous tx, survives rollback).
4. **NLQ fallback** — unmatched question → Select AI (SELECT‑only, grounded to `GRANDBACK_*`) →
   static help card if no LLM configured. Never invents data (hallucination control).

## 7. Surfaces

- **APEX UI** — Page 2 chat console (shell + approval modal), Page 3 admin governance (KPI strip +
  Users / Audit Log / Blocked Events interactive reports). Dark theme (`ebs-bot.css`), client
  sanitiser (`ebs-bot.js` tag allowlist).
- **ORDS REST API** — `POST /grandback/v1/chat`, `GET /bootstrap`, `GET /aging/ap`, `GET /kpis`,
  `POST /approval/cancel`. Demoable with the standalone `clients/grandback-chat.html` (no APEX import).

## 8. Test approach (RFP dimensions)

Persona‑based validation across AP/AR/GL/CM/FA, API‑first validation, and audit‑log review, covering
the six RFP dimensions: **Compliance, Data Accuracy, Bias & Fairness, Performance, Data Security &
Privacy, Hallucination**. Concrete mapping in [RFP_TRACEABILITY.md](RFP_TRACEABILITY.md) §D; automated
assertions in `backend/database/07_test_grandback_bot.sql`.

## 9. Out of scope for the POC

Live EBS 12.2.12 connectivity (GoldenGate read / OIC write), Oracle Vector Search / RAG, Local SLM
hosting, and autonomous multi‑step agents are **roadmap (Phase 2/3)**, represented on the architecture
diagram but not built in the trial POC.
