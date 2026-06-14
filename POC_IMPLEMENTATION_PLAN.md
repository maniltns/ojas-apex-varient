# ACCOR Grandback Conversational Bot — POC Implementation Plan (OCI Trial)

> **Purpose.** Step-by-step plan to build and deploy a minimum, RFP-aligned Phase‑1 POC of the
> ACCOR **Grandback** (Oracle EBS 12.2.12) Finance Conversational Bot on a **free OCI trial**
> (Autonomous Database 23ai + APEX + ORDS). This plan supersedes the ad‑hoc deploy notes; it
> reflects the *actual* toolchain behaviour and the RFP scope (3 phases, 4 personas, ORDS API‑first,
> Select AI / NLQ, 6 test dimensions).

---

## 0. RFP framing this POC must satisfy

| RFP element | What it means here |
|---|---|
| **Product** | ACCOR **Grandback** = client Oracle **EBS 12.2.12**; MOAC environment, 18 countries, 1000+ finance users across **AP · AR · GL · CM · FA**. |
| **Phase 1 — API‑first / Dynamic financial analytics (80 use cases)** | Semantic API / query access via **ORDS REST + Select AI / NLQ**: invoice inquiry, supplier/customer balance, bank/GL balances, journal status, trial balance, aging, supplier risk, expense trends. **This POC implements a representative subset of Phase 1.** |
| **Phase 2 — Knowledge & Context Intelligence (30)** | Oracle **Vector Search**, statistical reasoning, forecasting ("why is invoice 2201 blocked?"). *Roadmap only.* |
| **Phase 3 — Agentic AI (12 agents)** | Autonomous workflow orchestration, self‑healing reconciliation, finance copilot. *Roadmap only.* |
| **Application scope** | Oracle **APEX** conversational UI · **ORDS**-based API integration layer · EBS PL/SQL APIs exposure · Oracle AI (Select AI, NLQ, Vector Search). |
| **Personas** | **Finance Analyst · Cash Manager · Controller · Executive** (plus admin). |
| **Test dimensions** | **Compliance · Data Accuracy · Bias & Fairness · Performance · Data Security & Privacy · Hallucination.** |

The companion **[RFP_TRACEABILITY.md](RFP_TRACEABILITY.md)** maps every Phase‑1 use case, persona, and
test dimension to the concrete artifact that satisfies it.

---

## 1. What already exists (reuse — do NOT rebuild)

A working native APEX + ATP 23ai POC is already in the repo. The build below **renames and extends**
it; it does not start over.

- **Schema** — `backend/database/schema_install.sql`: 12 tables + seed data, drop‑loop on `ACCOR_%`.
- **Security pkg** — `ACCOR_IAM_VALIDATOR_PKG` (`accor_ebs_security_pkg.sql`): `get_user_context`,
  `validate_action`, `detect_injection`, `is_message_too_long`, `log_audit` (autonomous tx).
- **Bot engine** — `ACCOR_EBS_BOT_PKG` (`accor_ebs_bot_pkg.sql`): `process_chat_message` 6‑step
  pipeline, 8 HTML formatters, gated‑payment handshake, `bootstrap_user_session`, Select AI fallback
  via `EXECUTE IMMEDIATE`.
- **AJAX wrapper** — `ACCOR_EBS_BOT_API_PKG` (`accor_ebs_bot_api_pkg.sql`): `load_bootstrap`,
  `process_chat`, `cancel_approval`, `load_governance_kpis`.
- **Tests** — `test_accor_ebs_bot.sql`: 32 assertions via `DBMS_OUTPUT`.
- **Select AI (optional)** — `setup_select_ai.sql`: profile `ACCOR_BOT_PROFILE`.
- **APEX app 43171** (`applications/accor_ebs_bot/`): chat page (p2), admin page (p3), 5 app
  processes, 3 authorization schemes, `ebs-bot.css` / `ebs-bot.js`.

**Legacy/superseded (ignore, will be removed):** `apex_page2_*.sql`, `apex_app_install.sql`,
`apex_page2_html_region.html`.

---

## 2. Critical deployment reality (read before estimating time)

**`apexctl` cannot emit a single installable `.sql` for the APEX app.** It validates `.apx` and
**imports them through a live SQLcl session** (`runtime roundtrip --import-intent
validate-and-import`, which runs SQLcl `apex import -input`). Consequence for the trial:

- You need **SQLcl ≥ 26.1.2** + **Java 17/21** locally, connected to the trial ATP.
- The APEX **workspace must be pre‑created** (`GRANDBACK_DEV`) and the schema mapped to it.
- There is **no blind one‑file app install**. DB objects install from `.sql`; the **app** installs via
  `apex import`.
- **Fallback if the toolchain is unavailable on the trial:** import the app manually in **APEX
  Builder** (App Builder → Import) after the DB scripts run — the bot still works because all logic
  lives in PL/SQL packages the pages merely call.

The **fastest demonstrable path** is therefore: DB scripts → enable **ORDS REST** → exercise the
**ORDS API** (and optional standalone HTML) immediately, then import the APEX app for the full UI.

---

## 3. Naming: `ACCOR_*` → `GRANDBACK_*` rename (approved)

Blast radius: **447 occurrences across 24 files.** Rename is mechanical but must be done in
dependency order and verified by recompile + tests.

| Identifier class | From | To |
|---|---|---|
| 12 tables | `ACCOR_*` | `GRANDBACK_*` |
| 8 indexes | `IDX_ACCOR_*` | `IDX_GRANDBACK_*` |
| Package: engine | `ACCOR_EBS_BOT_PKG` | `GRANDBACK_BOT_PKG` |
| Package: security | `ACCOR_IAM_VALIDATOR_PKG` | `GRANDBACK_IAM_PKG` |
| Package: API | `ACCOR_EBS_BOT_API_PKG` | `GRANDBACK_BOT_API_PKG` |
| Drop‑loop LIKE | `'ACCOR_%'` | `'GRANDBACK_%'` |
| Select AI profile / cred | `ACCOR_BOT_PROFILE` / `ACCOR_LLM_CREDENTIAL` | `GRANDBACK_BOT_PROFILE` / `GRANDBACK_LLM_CREDENTIAL` |
| Seed user IDs | `accor_usr_*` | `gb_usr_*` |

**Keep as‑is (data / external):** the `@accor.com` seed email domain (it's the client's domain).
**Structural (separate, set at provisioning time):** schema name → `GRANDBACK_SCHEMA`, APEX workspace
→ `GRANDBACK_DEV`, app alias → `GRANDBACK-EBS-BOT`.

Rename order: **schema → security pkg → bot pkg → api pkg → select AI → tests → APEX `.apx`
(authorizations, app‑processes, lovs) → docs.** Recompile after each package; run the test suite at the end.

---

## 4. Target file layout after this build

```
backend/database/
  01_schema_install.sql          # renamed tables + seed (incl. 5 persona users)
  02_grandback_iam_pkg.sql       # was accor_ebs_security_pkg.sql
  03_grandback_bot_pkg.sql       # was accor_ebs_bot_pkg.sql (+ new Phase-1 formatters)
  04_grandback_bot_api_pkg.sql   # was accor_ebs_bot_api_pkg.sql
  05_ords_rest_grandback.sql     # NEW — ORDS REST module (API-first Phase 1)
  06_setup_select_ai.sql         # renamed; optional NLQ
  07_test_grandback_bot.sql      # renamed + new assertions
  deploy_all.sql                 # NEW — @-runs 01..04,06,07 in order (single entrypoint)
applications/accor_ebs_bot/      # .apx updated to new package/table names
clients/
  grandback-chat.html            # NEW — standalone HTML/JS client hitting ORDS (zero-import demo)
POC_IMPLEMENTATION_PLAN.md       # this file
RFP_TRACEABILITY.md              # NEW — 80/30/12 + personas + 6 test dims → artifacts
```

> Numeric prefixes make deploy order unambiguous on the trial. Old unprefixed/legacy files are deleted.

---

## 5. Phase‑1 functional scope for the POC

The existing engine ships **8 formatters** (AP aging, AR aging, overdue, GL balances, consolidated
summary, journal status, property summary, vendor lookup). Phase‑1 RFP names 80 use cases across
AP/AR/GL/CM/FA; the POC implements a **representative, demoable subset** that covers every module and
every persona, plus the ORDS API and (optional) Select AI/NLQ for the long tail.

**New formatters / intents to add (module coverage):**

| Module | New intent(s) | Keyword(s) |
|---|---|---|
| GL | Trial balance summary | `TRIAL BALANCE` |
| CM | Cash position / bank balances; unreconciled items | `CASH POSITION`, `BANK BALANCE`, `UNRECONCILED` |
| FA | Asset register; depreciation status | `ASSET`, `DEPRECIATION` |
| AP | Supplier risk (delays > 60 days); supplier balance | `SUPPLIER RISK`, `SUPPLIER BALANCE` |
| AR | Customer balance; receipts | `CUSTOMER BALANCE`, `RECEIPTS` |
| Cross | Expense growth trend | `EXPENSE TREND`, `EXPENSE GROWTH` |

This requires **2 new tables** for CM/FA coverage: `GRANDBACK_BANK_ACCOUNTS` (+ `..._BANK_TXNS`) and
`GRANDBACK_FIXED_ASSETS`. Both follow the `GRANDBACK_%` prefix so the drop‑loop and Select AI
grounding pick them up. Everything else is added formatters in the bot package.

**NLQ for the long tail:** anything not matched by a keyword falls through to **Select AI**
(`DBMS_CLOUD_AI.GENERATE`, SELECT‑only, grounded to the `GRANDBACK_*` tables) — this is how the POC
credibly claims "80 use cases / dynamic analytics" without hand‑coding 80 formatters. Without an LLM
key it degrades to the static help card (unchanged behaviour).

---

## 6. ORDS REST layer (the RFP "API integration layer")

New module `05_ords_rest_grandback.sql` defines, under schema `GRANDBACK_SCHEMA`, a REST module
`grandback/v1` with resources that wrap the **same** PL/SQL the UI uses (no logic duplication):

| Method · URI | Maps to | Purpose |
|---|---|---|
| `POST /grandback/v1/chat` | `GRANDBACK_BOT_API_PKG.process_chat` (body → message/property) | API‑first conversational endpoint |
| `GET /grandback/v1/bootstrap` | `GRANDBACK_BOT_API_PKG.load_bootstrap` | user context + properties + history |
| `POST /grandback/v1/approval/cancel` | `GRANDBACK_BOT_API_PKG.cancel_approval` | cancel pending approval |
| `GET /grandback/v1/kpis` | `GRANDBACK_BOT_API_PKG.load_governance_kpis` | governance KPIs |
| `GET /grandback/v1/aging/ap` | `GRANDBACK_BOT_PKG.format_ap_aging` (param `property_id`) | direct analytics resource (demo of API‑first) |

- Auth: protected by an ORDS **OAuth2 client‑credentials** role (`grandback_api`) for the API demo;
  the endpoints accept an `email`/persona header so persona‑based validation works over REST.
- The standalone **`clients/grandback-chat.html`** calls `POST /grandback/v1/chat` so the bot is
  demoable with **zero APEX import** — the single fastest thing to show on a trial.

---

## 7. Personas & seed data

Add three persona users to the seed (existing analyst/manager/admin stay), each scoped realistically:

| Persona (RFP) | role | ebs_role | property/scope |
|---|---|---|---|
| Finance Analyst | `finance_analyst` | analyst | subset of properties, **read‑only** |
| Cash Manager | `finance_manager` | cash_manager | CM scope (bank/cash), read+write in scope |
| Controller | `finance_manager` | controller | GL/close scope, read+write |
| Executive | `finance_analyst` | executive | all properties, **read‑only**, consolidated views |
| Admin | `admin` | admin | bypass scope, admin nav |

Persona drives **bias & fairness** testing (same question, different persona → role‑appropriate
filtering, no favouritism) and **compliance** testing (read‑only personas cannot write).

---

## 8. Step‑by‑step execution (the actual build)

### Stage A — Provision the OCI trial (manual, console)
1. Create **Autonomous Database (ATP) 23ai**, Always‑Free, workload type **Transaction Processing**.
2. In **Database Actions** create app schema **`GRANDBACK_SCHEMA`** (or use ADMIN for the POC) and
   grant it APEX + ORDS + `DBMS_CLOUD`/`DBMS_CLOUD_AI` execute.
3. In **APEX**, create workspace **`GRANDBACK_DEV`** mapped to `GRANDBACK_SCHEMA`.
4. Install **SQLcl 26.1.2+** locally (Java 17/21) and save a connection to the ATP wallet.

### Stage B — Database (code I will deliver)
5. Run `backend/database/deploy_all.sql` (it `@`-includes 01→04, 06, 07 in order), or run files
   01→07 individually in Database Actions → SQL.
6. Confirm `07_test_grandback_bot.sql` prints **all assertions PASS** in DBMS_OUTPUT.
7. Run `05_ords_rest_grandback.sql` to publish the REST module; note the base URL
   `https://<atp-host>/ords/grandback_schema/grandback/v1/`.

### Stage C — Prove API‑first immediately
8. `curl POST /grandback/v1/chat` with `{"message":"Show AP aging","property_id":"..."}` → JSON reply.
9. Open `clients/grandback-chat.html` (edit the base‑URL constant) → chat works with **no app import**.

### Stage D — APEX UI (full experience)
10. Validate: `node .agents/skills/apex/apexlang/tools/apexctl.mjs apexlang validate --app-path applications/accor_ebs_bot`.
11. Import: `... runtime roundtrip --app-path <abs> --db-connection-name <conn> --import-intent validate-and-import`.
    *Fallback:* APEX Builder → App Builder → Import.
12. Log in as each persona; run the persona test script (Stage E).

### Stage E — Validate against the 6 RFP dimensions
13. Execute the persona/test matrix in **RFP_TRACEABILITY.md** §Test. Record evidence
    (audit‑log rows) for **Compliance**, **Data Security/Privacy**, **Hallucination** (injection +
    grounding), **Bias/Fairness** (cross‑persona consistency), **Data Accuracy** (vs seed),
    **Performance** (response under load via repeated ORDS calls).

### Stage F — Optional NLQ
14. Edit `06_setup_select_ai.sql` with a real LLM key, run it → unmatched questions now answered by
    grounded Select AI; without it, the static help card path is unchanged.

---

## 9. Verification checklist (definition of done)

- [ ] `deploy_all.sql` runs clean on a fresh ATP; all packages compile with no errors.
- [ ] `07_test_grandback_bot.sql`: 100% assertions PASS (includes new persona + CM/FA assertions).
- [ ] No `ACCOR_` identifier remains in `backend/database/*.sql` or `applications/**/*.apx`
      (`grep -ri 'accor_' --include=*.sql --include=*.apx` returns only the `@accor.com` data domain).
- [ ] ORDS: all 5 endpoints return expected JSON; `POST /chat` enforces persona role (analyst write → blocked).
- [ ] `grandback-chat.html` performs a full read + gated‑write handshake against ORDS.
- [ ] APEX app imports and runs; chat + admin pages function for all 5 personas.
- [ ] Every doc uses Grandback vocabulary, the 3‑phase structure, and clearly separates POC vs target.
- [ ] `RFP_TRACEABILITY.md` maps each Phase‑1 use‑case category, persona, and test dimension to an artifact.

---

## 10. Risks & mitigations

| Risk | Mitigation |
|---|---|
| apexctl/SQLcl not runnable on trial host | APEX Builder manual import fallback (Stage D.11). Bot logic is package‑side, so UI import is the only thing affected. |
| Schema rename breaks a tested POC | Rename is mechanical + verified by recompile and the 32+ assertion suite before any UI work. |
| No LLM key on trial | Select AI path degrades to static help; all 8+ formatters and ORDS analytics work without it. |
| `DBMS_CLOUD_AI` absent on the instance | Already guarded by `EXECUTE IMMEDIATE` + `WHEN OTHERS` — package compiles regardless. |
| Free‑tier ATP auto‑stops when idle | Documented in Stage A; restart before demo. |

---

## 11. Build order I will follow (deliverables)

1. **RFP_TRACEABILITY.md** — scope contract (use cases · personas · test dims → artifacts).
2. **DB rename + numbering** — 01→04, 06, 07 renamed to `GRANDBACK_*`; drop‑loop + Select AI updated.
3. **Phase‑1 extension** — `GRANDBACK_BANK_ACCOUNTS/_BANK_TXNS`, `GRANDBACK_FIXED_ASSETS` + seed;
   new formatters/intents; new test assertions; 3 persona users.
4. **05_ords_rest_grandback.sql** + **clients/grandback-chat.html**.
5. **deploy_all.sql** single entrypoint.
6. **APEX `.apx`** updated to new identifiers; `apexlang validate` clean.
7. **Docs aligned** — rewrite `new-prd.md` (remove MongoDB/OpenAI error → Oracle stack), update
   README, CLAUDE, TRD, implementation_plan, UI_UX_Design, user_stories, Appflow, memory to Grandback
   + phases + personas + test dims.
```
