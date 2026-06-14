# Phase-1 Use-Case Catalogue (80) — Coverage Map

> Phase 1 of the RFP is **API-first / dynamic financial analytics, ~80 use cases**. This POC's design
> answer is **NLQ-first**: Oracle **Select AI** (`DBMS_CLOUD_AI.GENERATE`, SELECT-only, grounded to the
> `GRANDBACK_*` tables) is the engine that answers arbitrary finance questions; the **curated
> formatters** are fast, deterministic, demo-safe renderings of the highest-value questions.
>
> **Coverage key:**
> **F** = curated formatter (deterministic HTML, works with **no LLM**) ·
> **N** = answered by NLQ / Select AI (**requires an LLM key**; SELECT-only, grounded) ·
> **D** = deferred (needs data/feature not in the POC seed).
>
> Counts are indicative, per the RFP ("the list is indicative … detailing and finalization … at the
> beginning of the phases"). **Honest status:** F items are statically built (unrun); N items depend
> on configuring `06_setup_select_ai.sql` and are unverified without a key. See
> [GAP_REGISTER.md](GAP_REGISTER.md).

## How NLQ covers the long tail (the important part)

Without hand-coding 80 procedures, the POC answers open-ended questions because Select AI translates
NL → SQL against the grounded schema. Example questions that need **no new code**:

- "Which vendor has the largest unpaid balance across my properties?"
- "Compare AP liabilities between France and the UK."
- "Show suppliers with payment delays over 60 days, sorted by amount."
- "What's the total open AR by customer segment?"

These are **N** in the table below. The curated **F** set guarantees the marquee answers render
perfectly even when no LLM is configured (the demo never dead-ends).

---

## AP — Accounts Payable (18)

| # | Use case | Coverage | Backed by |
|---|---|---|---|
| AP-01 | AP aging by property | F | `format_ap_aging` |
| AP-02 | Overdue AP invoices ranked | F | `format_overdue` |
| AP-03 | Supplier risk — delays > 60 days | F | `format_supplier_risk` |
| AP-04 | Supplier balance / open AP by vendor | F | `format_vendor_lookup` + N |
| AP-05 | Vendor lookup / details | F | `format_vendor_lookup` |
| AP-06 | Invoice inquiry by number/status | N | NLQ |
| AP-07 | Invoices due in next N days | N | NLQ |
| AP-08 | AP by currency | N | NLQ |
| AP-09 | Top N vendors by exposure | N | NLQ |
| AP-10 | Payment terms breach analysis | N | NLQ |
| AP-11 | Duplicate-invoice candidates | N | NLQ |
| AP-12 | AP totals by month | N | NLQ |
| AP-13 | Pending-approval invoices | N | NLQ |
| AP-14 | Compare AP liabilities across countries | N | NLQ |
| AP-15 | Vendor concentration (% of AP) | N | NLQ |
| AP-16 | Invoices by category/vendor type | N | NLQ |
| AP-17 | Gated payment (write) | F | gated handshake |
| AP-18 | AP forecast / predicted run | D | Phase 3 |

## AR — Accounts Receivable (15)

| # | Use case | Coverage | Backed by |
|---|---|---|---|
| AR-01 | AR aging by property | F | `format_ar_aging` |
| AR-02 | Overdue AR (in overdue view) | F | `format_overdue` |
| AR-03 | Customer balances (open AR) | F | `format_customer_balance` |
| AR-04 | Receipts / collections inquiry | F/N | `format_customer_balance` + NLQ |
| AR-05 | AR by customer segment | N | NLQ |
| AR-06 | Largest receivables | N | NLQ |
| AR-07 | Days-sales-outstanding (DSO) | N | NLQ |
| AR-08 | AR by currency | N | NLQ |
| AR-09 | Credit-limit utilisation | N | NLQ |
| AR-10 | Invoice status by number | N | NLQ |
| AR-11 | AR due next N days | N | NLQ |
| AR-12 | Top customers by revenue | N | NLQ |
| AR-13 | Collection-risk ranking | D | Phase 3 |
| AR-14 | Revenue trend analysis | N | NLQ |
| AR-15 | Cross-country AR compare | N | NLQ |

## GL — General Ledger (16)

| # | Use case | Coverage | Backed by |
|---|---|---|---|
| GL-01 | GL account balances | F | `format_gl_balances` |
| GL-02 | Trial balance summary | F | `format_trial_balance` |
| GL-03 | Journal status by property | F | `format_journal_status` |
| GL-04 | Expense trend by account | F | `format_expense_trend` |
| GL-05 | Balance by account type | N | NLQ |
| GL-06 | Account detail by code | N | NLQ |
| GL-07 | Pending journals (close blockers) | N | NLQ |
| GL-08 | Period status | D | needs period table |
| GL-09 | Largest expense accounts | N | NLQ |
| GL-10 | Income vs expense summary | N | NLQ |
| GL-11 | Journal lines for an entry | N | NLQ |
| GL-12 | Dr/Cr balance check | F | `format_trial_balance` |
| GL-13 | Account summaries | N | NLQ |
| GL-14 | Expense growth % QoQ | D | needs time series |
| GL-15 | Revenue recognition status | N | NLQ |
| GL-16 | Liability analysis (dynamic) | N | NLQ |

## CM — Cash Management (16)

| # | Use case | Coverage | Backed by |
|---|---|---|---|
| CM-01 | Cash position / bank balances | F | `format_cash_position` |
| CM-02 | Book vs bank balance delta | F | `format_cash_position` |
| CM-03 | Unreconciled transactions | F | `format_unreconciled` |
| CM-04 | Reconciliation status by account | F/N | `format_unreconciled` + NLQ |
| CM-05 | Cash by currency | N | NLQ |
| CM-06 | Bank transaction history | N | NLQ |
| CM-07 | Receipts vs payments | N | NLQ |
| CM-08 | Net cash movement period | N | NLQ |
| CM-09 | Largest unreconciled items | N | NLQ |
| CM-10 | Cash by property | N | NLQ |
| CM-11 | Idle-cash identification | N | NLQ |
| CM-12 | Bank account inventory | N | NLQ |
| CM-13 | Reconciliation worklist | D | Phase 3 |
| CM-14 | Cash forecast | D | Phase 3 |
| CM-15 | FX exposure across accounts | N | NLQ |
| CM-16 | Days-cash-on-hand | N | NLQ |

## FA — Fixed Assets (15)

| # | Use case | Coverage | Backed by |
|---|---|---|---|
| FA-01 | Asset register by property | F | `format_assets` |
| FA-02 | Net book value | F | `format_assets` |
| FA-03 | Depreciation status | F | `format_assets` |
| FA-04 | Assets by category | N | NLQ |
| FA-05 | Fully-depreciated assets | N | NLQ |
| FA-06 | Asset cost totals | N | NLQ |
| FA-07 | Assets near end-of-life | N | NLQ |
| FA-08 | Accumulated depreciation totals | N | NLQ |
| FA-09 | Assets by acquisition date | N | NLQ |
| FA-10 | Asset count by status | N | NLQ |
| FA-11 | Highest-value assets | N | NLQ |
| FA-12 | Depreciation schedule forecast | D | needs schedule calc |
| FA-13 | Disposed assets | N | NLQ |
| FA-14 | Asset register by currency | N | NLQ |
| FA-15 | Capex summary | N | NLQ |

---

## Tally

| Module | Total | F (formatter) | N (NLQ) | D (deferred) |
|---|---|---|---|---|
| AP | 18 | 6 | 11 | 1 |
| AR | 15 | 3 | 10 | 2 |
| GL | 16 | 5 | 9 | 2 |
| CM | 16 | 4 | 10 | 2 |
| FA | 15 | 3 | 11 | 1 |
| **Total** | **80** | **21** | **51** | **8** |

**Reading this honestly:** ~21 use cases are guaranteed even with no LLM (curated formatters);
~51 are reachable via NLQ **once a key is configured and verified**; ~8 are deferred (need seed
data/features not in the POC). The "80 use cases" claim is credible **only** with Select AI enabled —
without it, the demo covers the 21 curated ones. Configure `06_setup_select_ai.sql` and run
SECURITY_TESTING §5 before claiming N coverage.
