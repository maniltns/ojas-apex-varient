# 🧠 ACCOR Grandback Finance Conversational Bot — POC

A secure, role-aware conversational assistant over **ACCOR Grandback** (the client's Oracle **EBS
12.2.12** finance landscape — AP · AR · GL · CM · FA, MOAC, 18 countries, 1000+ users). It runs
entirely inside the **native Oracle** stack: **Oracle APEX** + **OCI Autonomous Database 23ai**, with
all logic in PL/SQL and an **ORDS REST API** (the RFP "API-first" layer). For the POC, EBS data is
represented by seeded `GRANDBACK_*` tables.

**Start here:** [POC_IMPLEMENTATION_PLAN.md](POC_IMPLEMENTATION_PLAN.md) (step-by-step trial deploy) ·
[RFP_TRACEABILITY.md](RFP_TRACEABILITY.md) (use cases · personas · test dimensions → artifacts) ·
[new-prd.md](new-prd.md) (product requirements) · [docs/architecture.drawio](docs/architecture.drawio)
(5-page architecture).

---

## 🏗️ Architecture overview

The database is both the data layer and the orchestration engine; APEX and ORDS are thin surfaces over
the same PL/SQL.

```mermaid
graph TD
    User([Finance User]) -->|HTTPS / REST| Edge["Oracle APEX (Page 2 chat)  ·  ORDS /grandback/v1/*"]
    Edge -->|process_chat_message| Bot["GRANDBACK_BOT_PKG (6-step pipeline · 15 formatters)"]
    Bot -->|guard / IAM / audit| Sec["GRANDBACK_IAM_PKG"]
    Bot -->|gated DML| Pend[("GRANDBACK_PENDING_APPROVALS")]
    Bot -->|NL→SQL (optional, SELECT-only)| SelectAI["Select AI / OCI GenAI"]
    Bot -->|read/write| Data[("GRANDBACK_* tables — AP·AR·GL·CM·FA on ATP 23ai")]
    Sec -->|autonomous tx| Audit[("GRANDBACK_AUDIT_LOG")]
```

### Delivery phases (RFP)
- **Phase 1 — API-first / Dynamic analytics (80 use cases):** ORDS + Select AI/NLQ. **POC builds a
  representative subset across AP/AR/GL/CM/FA.**
- **Phase 2 — Knowledge & Context (30):** Oracle Vector Search, forecasting. *Roadmap.*
- **Phase 3 — Agentic AI (12 agents):** autonomous workflows. *Roadmap.*

### Key technical specs
* **Presentation:** Oracle APEX (APEXlang `.apx` under `applications/accor_ebs_bot/`) + standalone
  ORDS HTML client (`clients/grandback-chat.html`).
* **API:** ORDS REST module `grandback/v1` (`05_ords_rest_grandback.sql`).
* **Logic/data:** OCI ATP 23ai — `GRANDBACK_BOT_PKG`, `GRANDBACK_IAM_PKG`, `GRANDBACK_BOT_API_PKG`.
* **Guardrails:** SQL/prompt-injection + property-scope enforcement; gated DML; autonomous-tx audit.
* **NL→SQL:** `DBMS_CLOUD_AI` (Select AI), SELECT-only, grounded to `GRANDBACK_*`; static help fallback.

---

## 📦 Project structure

```text
ojas-apex-varient/
├── applications/accor_ebs_bot/        # Oracle APEX app (APEXlang)
│   ├── pages/                         # Page 2 (Chat) · Page 3 (Admin)
│   └── shared-components/             # auth, app-processes, lovs, static files
├── backend/database/                  # numbered deploy order
│   ├── 01_schema_install.sql          # 15 GRANDBACK_* tables + seed (5 personas)
│   ├── 02_grandback_iam_pkg.sql       # security / IAM validator
│   ├── 03_grandback_bot_pkg.sql       # bot engine (15 formatters, gated payment)
│   ├── 04_grandback_bot_api_pkg.sql   # APEX AJAX wrapper
│   ├── 05_ords_rest_grandback.sql     # ORDS REST API (API-first)
│   ├── 06_setup_select_ai.sql         # optional NLQ (needs LLM key)
│   ├── 07_test_grandback_bot.sql      # PL/SQL unit suite
│   ├── deploy_all.sql                 # single entrypoint (@-runs 01..04,07)
│   └── _legacy/                       # superseded scripts (do not use)
├── clients/grandback-chat.html        # standalone ORDS client (zero APEX import)
├── POC_IMPLEMENTATION_PLAN.md · RFP_TRACEABILITY.md
└── docs/architecture.drawio
```

---

## 🚀 Deploy on an OCI trial

> Full walk-through (with the apexctl/SQLcl reality and fallbacks) is in
> [POC_IMPLEMENTATION_PLAN.md](POC_IMPLEMENTATION_PLAN.md). Quick version:

**1. Database** — connect SQLcl / Database Actions as the `GRANDBACK_SCHEMA` user and run:
```sql
@deploy_all.sql            -- installs 01..04, runs the 07 test suite
@05_ords_rest_grandback.sql  -- publishes the REST API
-- optional NLQ: edit DEFINEs then  @06_setup_select_ai.sql
```
Confirm `07` prints **ALL TESTS PASSED**.

**2. Prove API-first immediately** (no APEX import needed):
```bash
curl -X POST https://<atp-host>/ords/grandback_schema/grandback/v1/chat \
  -H 'Content-Type: application/json' \
  -d '{"email":"manager@accor.com","message":"Show AP aging","property_id":"prop_novotel_paris"}'
```
…or open `clients/grandback-chat.html`, set the API base URL, and chat.

**3. APEX UI** — validate then import the app (requires Node + SQLcl 26.1.2+ on the host):
```bash
node .agents/skills/apex/apexlang/tools/apexctl.mjs apexlang validate --app-path applications/accor_ebs_bot
node .agents/skills/apex/apexlang/tools/apexctl.mjs runtime roundtrip \
  --app-path <abs-path>/applications/accor_ebs_bot --db-connection-name <conn> \
  --import-intent validate-and-import
```
*Fallback:* APEX Builder → App Builder → Import. (The bot works regardless — all logic is in the
PL/SQL packages the pages call.)

**Seed personas** (APEX Accounts login): `analyst@accor.com` (read-only), `cashmgr@accor.com`,
`controller@accor.com`, `exec@accor.com` (read-only), `manager@accor.com`, `admin@accor.com`.
