# OCI Beginner Runbook — Deploy the Grandback Bot from Zero

> **Audience:** someone who has **never used OCI**. This walks every click, in order, from creating a
> free account to a working chat demo. No prior Oracle Cloud, ATP, ORDS, or APEX knowledge assumed.
> Allow ~60–90 minutes the first time. Where a screen name might differ slightly by region/UI version,
> the **menu path** is given so you can still find it.
>
> **What you'll end up with:** an Autonomous Database with the bot installed, a working REST API, a
> browser chat client, and (optionally) the full APEX UI.
>
> Conventions: **Console ▸ A ▸ B** means click the hamburger menu (☰, top-left) then A then B.
> `code font` = type/paste exactly. Replace anything in `<angle brackets>`.

---

## Part 0 — Vocabulary (read once, 2 minutes)

| Term | Plain meaning |
|---|---|
| **OCI** | Oracle Cloud Infrastructure — Oracle's cloud, like AWS/Azure. |
| **Tenancy** | Your whole cloud account/org. |
| **Compartment** | A folder to group cloud resources. A default `root` one exists. |
| **ATP (Autonomous Transaction Processing)** | A fully-managed Oracle database. Our data + all the bot logic live here. **Always Free** tier is enough. |
| **Database Actions** | A web SQL tool built into ATP (no install). Where we run `.sql` files. |
| **Wallet** | A small zip of certificates that lets desktop tools connect securely to ATP. |
| **APEX** | Oracle's low-code web-app platform, bundled with ATP. Hosts the chat UI. |
| **ORDS** | Turns database procedures into REST APIs. Bundled with ATP. Powers our `/grandback/v1/` endpoints. |
| **Schema** | A database user that owns tables/code. Ours is `GRANDBACK_SCHEMA` (for the trial you may just use `ADMIN`). |

---

## Part 1 — Create a free OCI account (~15 min)

1. Go to **https://www.oracle.com/cloud/free/** → **Start for free**.
2. Sign up: email, country, then verify the email. Provide name + a **credit card** (identity check
   only — Always Free resources don't charge) and a phone number for SMS verification.
3. Choose a **home region** near you (you cannot change it later — pick the closest). Finish.
4. You'll receive a "Your account is ready" email. Sign in at **https://cloud.oracle.com** with your
   tenancy name + the username/password you set. You're now in the **OCI Console**.

> Stuck on sign-up? Use a personal email, a real card, and a region you'll keep. Corporate
> SSO/proxy networks sometimes block the verification SMS — try a phone hotspot.

---

## Part 2 — Create the Autonomous Database (~10 min)

1. **Console ▸ Oracle Database ▸ Autonomous Database**.
2. Make sure the **Compartment** (left) is `root` (or any you like). Click **Create Autonomous Database**.
3. Fill in:
   - **Display name:** `grandback-poc`
   - **Database name:** `grandbackpoc` (letters/numbers only)
   - **Workload type:** **Transaction Processing**
   - **Deployment:** Serverless
   - **Always Free:** toggle **ON** (important — keeps it free)
   - **Database version:** 23ai (or the highest offered)
   - **Create administrator credentials:** set a strong **ADMIN** password — **write it down**.
   - **Network access:** **Secure access from everywhere** (simplest for a trial).
   - **License:** "License included".
4. Click **Create**. Wait ~2–4 min until the big square icon turns **green / AVAILABLE**.

> Free-tier ATP **auto-stops after ~7 idle days** and you restart it from this same page
> (**More actions ▸ Start**). If a demo "can't connect", check it's started here first.

---

## Part 3 — Open Database Actions and run the SQL (~15 min)

We'll run the install scripts in the browser — no tools to install.

1. On the `grandback-poc` detail page click **Database Actions ▸ View all database actions**
   (opens a new tab). If asked, sign in as **ADMIN** / your ADMIN password.
2. In Database Actions, click the **SQL** card. You now have a web SQL worksheet.
3. For the trial, the simplest path is to **install everything as ADMIN** (skip creating a separate
   schema). *(If you prefer a dedicated `GRANDBACK_SCHEMA`, see Part 8.)*
4. Open each repo file, copy its entire contents into the worksheet, and run with the **▶ Run Script**
   button (the icon with a page behind the play triangle — **not** the single ▶ which runs one
   statement). Run them **in this order**:

   | Order | File | What it does |
   |---|---|---|
   | 1 | `backend/database/01_schema_install.sql` | Creates 15 tables + seed data (5 personas) |
   | 2 | `backend/database/02_grandback_iam_pkg.sql` | Security/identity package |
   | 3 | `backend/database/03_grandback_bot_pkg.sql` | Bot engine |
   | 4 | `backend/database/04_grandback_bot_api_pkg.sql` | APEX AJAX wrapper |
   | 5 | `backend/database/07_test_grandback_bot.sql` | Test suite (read the output!) |

   > Or paste **`backend/database/deploy_all.sql`** — but Database Actions' `@@` include only works
   > if the files are on the DB server, which they aren't, so for the browser just run 1–5 manually.
   > `deploy_all.sql` is for the SQLcl desktop path (Part 7).

5. After file 5, scroll the **Script Output** pane. You want to see **`ALL TESTS PASSED`**. If you see
   `FAIL` lines, note them — something didn't install cleanly; re-run files 1–4 and check for red
   errors (a common cause is running file 3 before file 2).

6. Sanity check — run this single statement (click the single ▶):
   ```sql
   SELECT object_name, object_type, status FROM user_objects
   WHERE object_name LIKE 'GRANDBACK%' AND status <> 'VALID';
   ```
   **Expect zero rows.** Any row = an invalid package; re-run that package's file and read the errors.

---

## Part 4 — Publish the REST API (~5 min)

1. In the **same SQL worksheet**, open `backend/database/05_ords_rest_grandback.sql`, paste, **▶ Run
   Script**. You should see `✓ ORDS module grandback.v1 published.` in the output.
2. Find your API base URL. It's:
   `https://<your-ATP-host>/ords/<schema>/grandback/v1/`
   - `<your-ATP-host>` = the host part of the Database Actions URL in your browser address bar
     (everything between `https://` and `/ords`).
   - `<schema>` = `admin` if you installed as ADMIN (lowercase), else `grandback_schema`.
   - Example: `https://abcd1234.adb.uk-london-1.oraclecloudapps.com/ords/admin/grandback/v1/`

3. **Test it** — open a terminal (or use any REST tool) and run:
   ```bash
   curl -X POST "https://<host>/ords/admin/grandback/v1/chat" \
     -H "Content-Type: application/json" \
     -d '{"email":"manager@accor.com","message":"Show AP aging","property_id":"prop_novotel_paris"}'
   ```
   **Expect** a JSON blob whose `reply` contains an HTML table with invoice `INV-MBC-441`.

> 404? The schema name in the URL is wrong (try `admin` vs `grandback_schema`), or ORDS isn't enabled
> — re-run file `05`. 401? You enabled auth; for the trial keep it open (see SECURITY_TESTING.md W1).

---

## Part 5 — Open the browser chat client (~3 min)

1. Open `clients/grandback-chat.html` in a text editor. Find the line with `id="apiBase"` and set its
   `value=` to your base URL from Part 4 (no trailing slash needed). Save.
2. Double-click the file to open it in a browser.
3. Pick a **persona** (top-right), pick a **property**, click a chip like **Show AP aging**, or type a
   question. You should see formatted tables. Try **Approve payment for ap_inv_1001** as
   *Finance Manager* → a confirm modal appears → **Confirm** → success message.

> "Network error / offline"? Two usual causes: (a) the API base URL is wrong; (b) **CORS** — the
> handlers send `Access-Control-Allow-Origin: *` so this should work, but some browsers block
> `file://`. If so, serve the file: `python -m http.server` in the `clients/` folder, then open
> `http://localhost:8000/grandback-chat.html`.

**At this point you have a working, demoable bot.** Parts 6–7 are optional polish.

---

## Part 6 — (Optional) Enable natural-language questions (Select AI) (~10 min)

Without this, only the curated quick actions work. With an LLM key, free-form questions across all
modules work (the "80 use cases" story — see USE_CASE_CATALOGUE.md).

1. Get an API key from a provider (e.g. OpenAI) **or** use OCI Generative AI.
2. In the SQL worksheet, open `backend/database/06_setup_select_ai.sql`. Edit the three `DEFINE`
   lines at the top (`llm_provider`, `llm_model`, `llm_api_key`). **▶ Run Script.**
3. Grant the schema network access if prompted (ATP may need an ACL for the LLM host — the script
   comments explain; for ADMIN it usually works directly).
4. Back in the chat client, ask something not on a chip, e.g.
   *"Which vendor has the largest unpaid balance?"* — it should answer from live data.

> Never commit your real key. `06_setup_select_ai.sql` ships a placeholder only.

---

## Part 7 — (Optional) Install the full APEX UI (~20 min, needs desktop tools)

The polished chat + admin pages. This needs **SQLcl** (a small Java CLI) because the app is stored as
declarative `.apx` files, not a one-click export.

1. Install **Java 17 or 21**, then **SQLcl 26.1.2+** (download from Oracle, unzip, the binary is
   `bin/sql`). Install **Node.js 18+** (for the validator).
2. Download the DB **wallet**: ATP page ▸ **Database Connection** ▸ **Download Wallet** ▸ set a
   password ▸ save the zip.
3. Create the APEX workspace: ATP page ▸ **Database Actions ▸ APEX** ▸ sign in as ADMIN ▸ create a
   workspace named **`GRANDBACK_DEV`** mapped to your schema (ADMIN or `GRANDBACK_SCHEMA`). Set an
   APEX Accounts password for each seed user (analyst@accor.com, manager@accor.com, …) under
   **Manage Users**.
4. From the repo root, validate then import:
   ```bash
   node .agents/skills/apex/apexlang/tools/apexctl.mjs apexlang validate --app-path applications/accor_ebs_bot
   node .agents/skills/apex/apexlang/tools/apexctl.mjs runtime roundtrip \
     --app-path "$(pwd)/applications/accor_ebs_bot" \
     --db-connection-name <your-sqlcl-conn> --import-intent validate-and-import
   ```
   **Fallback if the tooling fights you:** in APEX ▸ **App Builder ▸ Import**, import the app
   manually. The bot still works because all logic is in the DB packages the pages call.
5. Open the app from App Builder ▸ **Run**, log in as a seed persona, use the chat.

---

## Part 8 — (Optional) Use a dedicated schema instead of ADMIN

Cleaner, closer to production. In Database Actions as ADMIN, before Part 3:
```sql
CREATE USER GRANDBACK_SCHEMA IDENTIFIED BY "<StrongPwd#123>";
GRANT DWROLE TO GRANDBACK_SCHEMA;                 -- ATP convenience role
GRANT EXECUTE ON DBMS_CLOUD     TO GRANDBACK_SCHEMA;
GRANT EXECUTE ON DBMS_CLOUD_AI  TO GRANDBACK_SCHEMA;
-- then REST-enable it (Database Actions ▸ Administration ▸ Database Users ▸ toggle "Web Access" / REST)
```
Then connect **as `GRANDBACK_SCHEMA`** (sign out of ADMIN, sign in as the new user in Database
Actions) and run Parts 3–4 there. The URL schema segment becomes `grandback_schema`.

---

## Part 9 — Verify against acceptance & security

- Run the business cases in **[UAT_ACCEPTANCE.md](UAT_ACCEPTANCE.md)** (login per persona, type, check).
- Run the **[SECURITY_TESTING.md](SECURITY_TESTING.md)** checklist (injection, authz, the open-API warning).
- Record what passed/failed in **[GAP_REGISTER.md](GAP_REGISTER.md)**.

## Troubleshooting quick table

| Symptom | Likely cause | Fix |
|---|---|---|
| Can't connect / "database unavailable" | ATP auto-stopped | ATP page ▸ More actions ▸ **Start** |
| `ALL TESTS PASSED` not shown | a package failed to compile | Re-run files 2→3→4 in order; check red errors |
| `ORA-00942 table or view does not exist` | ran a package before the schema | Run `01_schema_install.sql` first |
| REST `404` | wrong schema in URL | try `admin` vs `grandback_schema`, re-run `05` |
| REST `401` | API protected | keep open for trial, or use a token (SECURITY_TESTING C2) |
| Chat client "offline" | wrong API base / `file://` CORS | fix base URL; serve via `python -m http.server` |
| NLQ answers "not configured" | no LLM key | do Part 6, or just use the curated chips |
| APEX import fails | toolchain/version | use App Builder ▸ Import (Part 7 fallback) |

> **Cost note:** everything above stays within **Always Free** if you keep the ATP on the Always-Free
> shape and don't add paid services. Select AI calls bill on **your LLM provider's** side, not OCI.
