# RFP Traceability Matrix — ACCOR Grandback Conversational Bot POC

> Maps the RFP scope (3 phases · 80/30/12 use cases · 4 personas · 6 test dimensions) to the concrete
> POC artifact that satisfies it. "POC" = built in this trial build; "Roadmap" = Phase 2/3, designed
> not built. See **[POC_IMPLEMENTATION_PLAN.md](POC_IMPLEMENTATION_PLAN.md)** for the build steps.

---

## A. Phase coverage

| Phase | RFP theme | Count | POC status |
|---|---|---|---|
| **Phase 1** | API‑first / Dynamic financial analytics | 80 use cases | **Representative subset built** — keyword formatters for every module + Select AI/NLQ for the long tail + ORDS API |
| **Phase 2** | Knowledge & Context Intelligence (Vector Search, forecasting) | 30 | Roadmap (architecture page 3) |
| **Phase 3** | Agentic AI (autonomous workflows) | 12 agents | Roadmap (architecture page 3) |

---

## B. Phase‑1 use‑case categories → POC artifact

The RFP lists 80 Phase‑1 use cases by category. The POC implements at least one concrete, tested
intent per category, across all five EBS modules (AP/AR/GL/CM/FA). Remaining variations are served by
the **Select AI / NLQ fallback** (grounded, SELECT‑only).

| RFP Phase‑1 category | Module | POC intent / artifact | Backed by |
|---|---|---|---|
| Invoice inquiry | AP/AR | `ap_aging`, `ar_aging`, `overdue` | `format_ap_aging`, `format_ar_aging`, `format_overdue` |
| Supplier balance / Supplier risk (>60d) | AP | `supplier_balance`, `supplier_risk` | new `format_supplier_risk` |
| Customer balance / Receipts | AR | `customer_balance`, `receipts` | new `format_customer_balance` |
| Bank balances / Cash position | CM | `cash_position`, `bank_balance` | new `format_cash_position` (new `GRANDBACK_BANK_ACCOUNTS`) |
| Reconciliation / Unreconciled txns | CM | `unreconciled` | new `format_unreconciled` (new `GRANDBACK_BANK_TXNS`) |
| GL account balance | GL | `gl_balances` | `format_gl_balances` |
| Trial balance summary | GL | `trial_balance` | new `format_trial_balance` |
| Journal status | GL | `journal_status` | `format_journal_status` |
| Asset details / Depreciation status | FA | `asset_register`, `depreciation` | new `format_assets` (new `GRANDBACK_FIXED_ASSETS`) |
| Aging analysis | AP/AR | `ap_aging`, `ar_aging` | existing formatters |
| Expense / revenue trend; growth | GL | `expense_trend` | new `format_expense_trend` |
| Consolidated / portfolio; multi‑country compare | Cross | `consolidated_summary`, `property_summary` | `format_consolidated_summary`, `format_property_summary` |
| Vendor lookup | AP | `vendor_lookup` | `format_vendor_lookup` |
| Gated payment (write) | AP | `payment_approval` → `CONFIRM` | gated handshake on `GRANDBACK_PENDING_APPROVALS` |
| Anything else ("dynamic analytics") | Any | NLQ | Select AI `GRANDBACK_BOT_PROFILE`, SELECT‑only, grounded |

**Module coverage check:** AP ✅ · AR ✅ · GL ✅ · CM ✅ (new) · FA ✅ (new). Every RFP module is exercised.

---

## C. Personas → access model & test evidence

| Persona (RFP) | Seed user | role / ebs_role | Scope | Can write? |
|---|---|---|---|---|
| Finance Analyst | `analyst@accor.com` | finance_analyst / analyst | 2 properties | No (read‑only) |
| Cash Manager | `cashmgr@accor.com` | finance_manager / cash_manager | CM scope | Yes, in scope |
| Controller | `controller@accor.com` | finance_manager / controller | GL/close scope | Yes, in scope |
| Executive | `exec@accor.com` | finance_analyst / executive | all properties | No (read‑only, consolidated) |
| Admin | `admin@accor.com` | admin / admin | all (bypass) | Yes |

Persona enforcement is the existing `GRANDBACK_IAM_PKG.validate_action` (role + property scope) — no
new security logic, just additional seed users + ebs_role labels.

---

## D. Six RFP test dimensions → how the POC proves each

| Dimension | How proven in POC | Evidence source |
|---|---|---|
| **Compliance** | Read‑only personas (analyst, executive) blocked from write; property‑scope enforced | `validate_action`; `GRANDBACK_AUDIT_LOG` rows status='blocked' |
| **Data Accuracy** | Formatter output reconciled to seed values (e.g. AP aging totals = sum of seeded invoices) | Test assertions in `07_test_grandback_bot.sql`; manual vs seed |
| **Bias & Fairness** | Same question across personas → identical numbers with role‑appropriate filtering, no favouritism | Cross‑persona run; compare ORDS `/chat` responses |
| **Performance** | Repeated ORDS `/chat` + `/aging/ap` calls under simple load; response under target | `curl`/loop against ORDS endpoints; ATP SQL monitoring |
| **Data Security & Privacy** | Injection/prompt‑injection/XSS blocked; bot replies sanitised by JS allowlist; audit autonomous‑tx | `detect_injection`; `ebs-bot.js` ALLOWED_TAGS; audit log |
| **Hallucination** | NLQ is SELECT‑only & grounded to `GRANDBACK_*`; unknown → static help, never invented data | Select AI `system_message`; fallback path |

---

## E. Application‑scope items (RFP) → artifact

| RFP application‑scope item | POC artifact |
|---|---|
| Oracle APEX conversational UI | APEX app 43171 (chat p2 + admin p3) + `ebs-bot.css/js` |
| ORDS‑based API integration layer | `05_ords_rest_grandback.sql` → `grandback/v1/*` + `clients/grandback-chat.html` |
| EBS PL/SQL APIs & business services exposure | `GRANDBACK_BOT_PKG` formatters wrapped by `GRANDBACK_BOT_API_PKG` and ORDS |
| Oracle AI (Select AI, NLQ) | `06_setup_select_ai.sql` → `GRANDBACK_BOT_PROFILE` (optional key) |
| Oracle AI (Vector Search) | Roadmap (Phase 2) — architecture page 3 |

---

## F. Activities (RFP) → coverage

| RFP activity | POC coverage |
|---|---|
| Validation (scope, governance, integration) | This matrix + `apexlang validate` + test suite |
| Map requirements to APIs | §B and §E above |
| Setup & configure APEX | Stage A & D of the implementation plan |
| Setup Local SLM / NLP (intent & entity extraction) | Keyword intent routing today; Select AI/NLQ for entities; Local SLM = roadmap |
| Develop EBS PL/SQL APIs & ORDS REST services | `GRANDBACK_BOT_PKG/_API_PKG` + `05_ords_rest_grandback.sql` |
| Testing & training | `07_test_grandback_bot.sql` + persona runbook (§C/§D) |
| Go‑live / post‑go‑live | Trial deploy = pilot; production path = architecture roadmap (Phases 1–3) |

---

## G. Explicit non‑goals for this POC (set expectations)

- Live EBS 12.2.12 connectivity (GoldenGate read / OIC write) — **roadmap**, mocked by `GRANDBACK_*` tables.
- Oracle Vector Search / RAG, Local SLM hosting — **roadmap (Phase 2/3)**.
- Autonomous multi‑step agents — **roadmap (Phase 3)**.
- All 80 Phase‑1 use cases hand‑coded — POC ships a representative subset + NLQ for the tail.
