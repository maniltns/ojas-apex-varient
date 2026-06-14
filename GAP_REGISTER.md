# Gap Register — RFP Requirement vs. POC Implementation

> Single auditable view of what is **Built**, **Partial**, **Not built (roadmap)**, and — critically —
> what is **Not tested**. "Built" here means *the code exists and was statically reviewed*; it does
> **not** mean executed on a database. **As of this writing, nothing has been run on a live ATP** —
> see the Test-status column and §Verification debt.
>
> Legend: ✅ Built · 🟡 Partial · 🟦 Roadmap (Phase 2/3, intentionally not built) · ⬜ Not built ·
> 🧪 status: `static` = reviewed only, `unit` = automated assertion exists (unrun), `none` = no test.

## A. Phase coverage

| RFP item | Status | Test | Notes |
|---|---|---|---|
| Phase 1 — API-first / dynamic analytics (80 use cases) | 🟡 | unit | NLQ-first engine + 15 curated formatters across AP/AR/GL/CM/FA. **Not 80 hand-built cases** — see [USE_CASE_CATALOGUE.md](USE_CASE_CATALOGUE.md). |
| Phase 2 — Knowledge & Context (Vector Search, 30) | 🟦 | none | Roadmap. On architecture diagram only. |
| Phase 3 — Agentic AI (12 agents) | 🟦 | none | Roadmap. Per-module formatters today; agent split is target. |

## B. Functional requirements

| Requirement | Status | Test | Evidence / file |
|---|---|---|---|
| Conversational chat UI (APEX) | ✅ | static | `p00002-chat.apx`, `ebs-bot.js/css` — **never imported/rendered** |
| Conversational client (API) | ✅ | static | `clients/grandback-chat.html` → ORDS |
| ORDS REST API (API-first layer) | ✅ | none | `05_ords_rest_grandback.sql` — **never published/called** |
| AP inquiries (aging, invoices, payments) | ✅ | unit | `format_ap_aging`, `format_overdue`, gated payment |
| AR inquiries (balances, receipts, aging) | ✅ | unit | `format_ar_aging`, `format_customer_balance` |
| GL inquiries (balances, trial balance, journals) | ✅ | unit | `format_gl_balances`, `format_trial_balance`, `format_journal_status` |
| CM inquiries (cash position, bank, reconciliation) | ✅ | unit | `format_cash_position`, `format_unreconciled` (+ new tables) |
| FA inquiries (assets, depreciation) | ✅ | unit | `format_assets` (+ `GRANDBACK_FIXED_ASSETS`) |
| Supplier risk / expense trend / consolidated | ✅ | unit/none | `format_supplier_risk`, `format_expense_trend`, `format_consolidated_summary` |
| Dynamic/NL analytics (the long tail) | 🟡 | none | Select AI NLQ — **requires LLM key; never run.** Falls back to static help. |
| Gated write (two-step CONFIRM) | ✅ | unit | `GRANDBACK_PENDING_APPROVALS` + handshake |
| Audit logging (autonomous tx) | ✅ | unit | `GRANDBACK_AUDIT_LOG`, `log_audit` |
| Admin governance page (KPIs + reports) | 🟡 | none | `p00003-admin.apx` — IR queries written, **never rendered** |

## C. Personas (RFP)

| Persona | Seeded | Access model | Test |
|---|---|---|---|
| Finance Analyst | ✅ | read-only, scoped | unit (write denied, scope denied) |
| Cash Manager | ✅ | write in scope | unit (gates payment) |
| Controller | ✅ | write in scope | static (no dedicated assertion beyond shared manager logic) |
| Executive | ✅ | read-only, all properties | unit (write denied) |
| Admin | ✅ | bypass | unit (scope bypass) |

## D. Six RFP test dimensions — evidence status

| Dimension | Coverage | Status | Honest gap |
|---|---|---|---|
| Compliance (RBAC, no unauthorized exposure) | Authz tests A1–A8 | 🟡 unit | Automated assertions exist but **unrun**; A7/A8 are manual. |
| Data Accuracy (vs EBS/source) | Numeric reconciliation to seed (exact `8,200.00` + invoice no.) | 🟡 unit | Assertion added; **unrun**. Covers one figure — broaden per use case. |
| Bias & Fairness (same Q across personas) | Cross-persona row-equality assertion (Manager vs Cash Manager) | 🟡 unit | Assertion added; **unrun**. Compares rendered table bodies. |
| Performance (latency/concurrency) | Repeated ORDS calls | ⬜ none | **Not implemented.** No load test, no latency target measured. Manual loop only. |
| Data Security & Privacy | Injection + sanitizer + audit | 🟡 unit | Injection unit tests exist (unrun); **PII masking not implemented**; transport/CORS hardening pending. |
| Hallucination (grounded, no invented data) | SELECT-only + grounding | 🟡 none | Controls exist in config; **no test executed** because NLQ needs a key. |

## E. Architecture / platform (roadmap vs built)

| Item | Status | Notes |
|---|---|---|
| OCI ATP 23ai (mock `GRANDBACK_*` data) | ✅ | POC data plane |
| APEX Accounts auth | ✅ | UI login; `GRANDBACK_USERS` is role registry |
| ORDS REST | ✅ | built; auth OPEN by default (W1) |
| Select AI / NLQ | 🟡 | optional, key-gated |
| Live EBS 12.2.12 (GoldenGate read / OIC write) | 🟦 | roadmap; mocked |
| Oracle Vector Search / RAG | 🟦 | roadmap |
| OCI Identity Domains federated SSO | 🟦 | roadmap (APEX Accounts today) |
| VPD row-level security | 🟦 | roadmap; scope is app-enforced (W5) |
| WAF / LB / OKE / Data Guard | 🟦 | roadmap |

## F. Known defects fixed during review

| ID | Defect | Fix |
|---|---|---|
| D1 | `get_user_context` could raise `TOO_MANY_ROWS` (short-username prefix matches multiple emails) — dangerous inside autonomous audit tx | Exact-match first, deterministic prefix fallback, `WHEN OTHERS` guard |
| D2 | Property scope used raw `INSTR(property_access, id)` → **substring authorization bypass** (e.g. `prop_ibis` ⊂ `prop_ibis_london`) | Comma-wrapped exact CSV membership in all 4 sites (IAM, API, ORDS, LOV) + regression test |
| D3 | ORDS trusted client `email` → **admin impersonation** | Handlers prefer `:current_user`; body email = demo-mode fallback only; OAuth2 guidance |

## G. Verification debt (must-do before claiming "done")

1. **Run `deploy_all.sql` on a real ATP** — confirm all packages compile VALID (static review cannot guarantee this).
2. **Run `07_test_grandback_bot.sql`** — confirm "ALL TESTS PASSED" (assertions are currently unrun).
3. **Publish ORDS + exercise endpoints** — confirm the 5 resources return expected JSON.
4. **Import the APEX app** (apexctl or Builder) — confirm pages render and processes fire.
5. **Add the missing tests**: numeric Data-Accuracy assertions, a Bias/Fairness cross-persona comparison, a Performance harness.
6. **Run the [SECURITY_TESTING.md](SECURITY_TESTING.md) checklist** and record evidence.
7. **Decide NLQ posture** — with no LLM key the "dynamic analytics / 80 use cases" claim rests on 15 formatters only; with a key, run N1–N4.

> Until §G items 1–4 are done, the correct status of this POC is **"implemented and statically
> reviewed, not yet verified on a database."** Do not represent it as tested.
