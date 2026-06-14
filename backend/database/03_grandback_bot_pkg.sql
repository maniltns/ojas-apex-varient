CREATE OR REPLACE PACKAGE GRANDBACK_BOT_PKG AS
    -- Main entrypoint. Returns a JSON string containing reply (HTML),
    -- requires_approval, approval_payload, and intent.
    FUNCTION process_chat_message (
        p_email       IN VARCHAR2,
        p_ebs_role    IN VARCHAR2,
        p_message     IN VARCHAR2,
        p_property_id IN VARCHAR2,
        p_thread_id   IN VARCHAR2,
        p_session_id  IN VARCHAR2 DEFAULT NULL
    ) RETURN VARCHAR2;

    -- Post-authentication hook: populates application items from GRANDBACK_USERS.
    PROCEDURE bootstrap_user_session (
        p_email IN VARCHAR2
    );

    -- Marks an outstanding pending approval as cancelled (called when the
    -- user closes the approval modal without confirming).
    PROCEDURE cancel_pending_approval (
        p_email     IN VARCHAR2,
        p_thread_id IN VARCHAR2
    );
END GRANDBACK_BOT_PKG;
/

CREATE OR REPLACE PACKAGE BODY GRANDBACK_BOT_PKG AS

    C_PENDING_TTL_MIN CONSTANT PLS_INTEGER := 15;

    -- ────────────────────────────────────────────────────────────────────
    -- HTML helpers
    -- ────────────────────────────────────────────────────────────────────
    FUNCTION safe_html (p_text IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN APEX_ESCAPE.HTML(p_text);
    END safe_html;

    FUNCTION fmt_amount (p_amount IN NUMBER, p_currency IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN '<span class="ebs-num">' ||
               TO_CHAR(p_amount, 'FM999,999,999,990.00') ||
               '</span> <span class="ebs-ccy">' || p_currency || '</span>';
    END fmt_amount;

    FUNCTION status_pill (p_status IN VARCHAR2) RETURN VARCHAR2 IS
        v_class VARCHAR2(40) := 'ebs-pill';
    BEGIN
        IF p_status = 'paid' OR p_status = 'posted' THEN
            v_class := v_class || ' ebs-pill--success';
        ELSIF p_status IN ('pending_approval','pending') THEN
            v_class := v_class || ' ebs-pill--warn';
        ELSIF p_status = 'overdue' THEN
            v_class := v_class || ' ebs-pill--danger';
        ELSE
            v_class := v_class || ' ebs-pill--neutral';
        END IF;
        RETURN '<span class="' || v_class || '">' || safe_html(p_status) || '</span>';
    END status_pill;

    FUNCTION render_empty (p_msg IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN '<div class="ebs-empty">' || safe_html(p_msg) || '</div>';
    END render_empty;

    -- ────────────────────────────────────────────────────────────────────
    -- Intent formatters
    -- ────────────────────────────────────────────────────────────────────
    FUNCTION format_ap_aging (p_property_id IN VARCHAR2) RETURN VARCHAR2 IS
        v_html  VARCHAR2(32767);
        v_count INTEGER := 0;
    BEGIN
        v_html := '<h3 class="ebs-h">Accounts Payable — Aging</h3>' ||
                  '<table class="ebs-table"><thead><tr>' ||
                  '<th scope="col">Invoice</th>' ||
                  '<th scope="col">Vendor</th>' ||
                  '<th scope="col" class="num">Amount</th>' ||
                  '<th scope="col">Due</th>' ||
                  '<th scope="col">Days</th>' ||
                  '<th scope="col">Status</th>' ||
                  '</tr></thead><tbody>';

        FOR r IN (
            SELECT i.invoice_id, i.invoice_number, v.name AS vendor_name,
                   i.amount, i.currency, i.due_date, i.status,
                   TRUNC(SYSDATE) - TRUNC(i.due_date) AS days_due
              FROM GRANDBACK_AP_INVOICES i
              JOIN GRANDBACK_VENDORS v ON i.vendor_id = v.vendor_id
             WHERE i.property_id = p_property_id
             ORDER BY i.due_date ASC
        ) LOOP
            v_count := v_count + 1;
            v_html := v_html || '<tr>' ||
                      '<td><code>' || safe_html(r.invoice_number) || '</code></td>' ||
                      '<td>' || safe_html(r.vendor_name) || '</td>' ||
                      '<td class="num">' || fmt_amount(r.amount, r.currency) || '</td>' ||
                      '<td>' || TO_CHAR(r.due_date, 'YYYY-MM-DD') || '</td>' ||
                      '<td class="num">' ||
                      CASE
                          WHEN r.status = 'paid' THEN '—'
                          WHEN r.days_due > 0 THEN '<span class="ebs-num ebs-num--danger">+' || r.days_due || '</span>'
                          WHEN r.days_due = 0 THEN '<span class="ebs-num">today</span>'
                          ELSE '<span class="ebs-num">' || r.days_due || '</span>'
                      END ||
                      '</td>' ||
                      '<td>' || status_pill(r.status) || '</td>' ||
                      '</tr>';
        END LOOP;

        v_html := v_html || '</tbody></table>';

        IF v_count = 0 THEN
            RETURN render_empty('No accounts payable invoices found for this property.');
        END IF;

        RETURN v_html;
    END format_ap_aging;

    FUNCTION format_ar_aging (p_property_id IN VARCHAR2) RETURN VARCHAR2 IS
        v_html  VARCHAR2(32767);
        v_count INTEGER := 0;
    BEGIN
        v_html := '<h3 class="ebs-h">Accounts Receivable — Aging</h3>' ||
                  '<table class="ebs-table"><thead><tr>' ||
                  '<th scope="col">Invoice</th>' ||
                  '<th scope="col">Customer</th>' ||
                  '<th scope="col" class="num">Amount</th>' ||
                  '<th scope="col">Due</th>' ||
                  '<th scope="col">Days</th>' ||
                  '<th scope="col">Status</th>' ||
                  '</tr></thead><tbody>';

        FOR r IN (
            SELECT i.invoice_id, i.invoice_number, c.name AS customer_name,
                   i.amount, i.currency, i.due_date, i.status,
                   TRUNC(SYSDATE) - TRUNC(i.due_date) AS days_due
              FROM GRANDBACK_AR_INVOICES i
              JOIN GRANDBACK_CUSTOMERS c ON i.customer_id = c.customer_id
             WHERE i.property_id = p_property_id
             ORDER BY i.due_date ASC
        ) LOOP
            v_count := v_count + 1;
            v_html := v_html || '<tr>' ||
                      '<td><code>' || safe_html(r.invoice_number) || '</code></td>' ||
                      '<td>' || safe_html(r.customer_name) || '</td>' ||
                      '<td class="num">' || fmt_amount(r.amount, r.currency) || '</td>' ||
                      '<td>' || TO_CHAR(r.due_date, 'YYYY-MM-DD') || '</td>' ||
                      '<td class="num">' ||
                      CASE
                          WHEN r.status = 'paid' THEN '—'
                          WHEN r.days_due > 0 THEN '<span class="ebs-num ebs-num--danger">+' || r.days_due || '</span>'
                          WHEN r.days_due = 0 THEN '<span class="ebs-num">today</span>'
                          ELSE '<span class="ebs-num">' || r.days_due || '</span>'
                      END ||
                      '</td>' ||
                      '<td>' || status_pill(r.status) || '</td>' ||
                      '</tr>';
        END LOOP;

        v_html := v_html || '</tbody></table>';

        IF v_count = 0 THEN
            RETURN render_empty('No accounts receivable invoices found for this property.');
        END IF;

        RETURN v_html;
    END format_ar_aging;

    FUNCTION format_overdue (p_property_id IN VARCHAR2) RETURN VARCHAR2 IS
        v_html  VARCHAR2(32767);
        v_count INTEGER := 0;
    BEGIN
        v_html := '<h3 class="ebs-h">Overdue Invoices</h3>' ||
                  '<table class="ebs-table"><thead><tr>' ||
                  '<th scope="col">Type</th>' ||
                  '<th scope="col">Invoice</th>' ||
                  '<th scope="col">Counterparty</th>' ||
                  '<th scope="col" class="num">Amount</th>' ||
                  '<th scope="col">Due</th>' ||
                  '<th scope="col">Days late</th>' ||
                  '</tr></thead><tbody>';

        FOR r IN (
            SELECT 'AP' AS kind, i.invoice_number, v.name AS counterparty,
                   i.amount, i.currency, i.due_date,
                   TRUNC(SYSDATE) - TRUNC(i.due_date) AS days_late
              FROM GRANDBACK_AP_INVOICES i
              JOIN GRANDBACK_VENDORS v ON i.vendor_id = v.vendor_id
             WHERE i.property_id = p_property_id
               AND i.status != 'paid'
               AND i.due_date < TRUNC(SYSDATE)
            UNION ALL
            SELECT 'AR' AS kind, i.invoice_number, c.name AS counterparty,
                   i.amount, i.currency, i.due_date,
                   TRUNC(SYSDATE) - TRUNC(i.due_date) AS days_late
              FROM GRANDBACK_AR_INVOICES i
              JOIN GRANDBACK_CUSTOMERS c ON i.customer_id = c.customer_id
             WHERE i.property_id = p_property_id
               AND i.status != 'paid'
               AND i.due_date < TRUNC(SYSDATE)
             ORDER BY 7 DESC
        ) LOOP
            v_count := v_count + 1;
            v_html := v_html || '<tr>' ||
                      '<td><span class="ebs-tag ebs-tag--' || LOWER(r.kind) || '">' || r.kind || '</span></td>' ||
                      '<td><code>' || safe_html(r.invoice_number) || '</code></td>' ||
                      '<td>' || safe_html(r.counterparty) || '</td>' ||
                      '<td class="num">' || fmt_amount(r.amount, r.currency) || '</td>' ||
                      '<td>' || TO_CHAR(r.due_date, 'YYYY-MM-DD') || '</td>' ||
                      '<td class="num"><span class="ebs-num ebs-num--danger">+' || r.days_late || '</span></td>' ||
                      '</tr>';
        END LOOP;

        v_html := v_html || '</tbody></table>';

        IF v_count = 0 THEN
            RETURN render_empty('No overdue invoices for this property. ✓');
        END IF;

        RETURN v_html;
    END format_overdue;

    FUNCTION format_gl_balances RETURN VARCHAR2 IS
        v_html  VARCHAR2(32767);
        v_count INTEGER := 0;
    BEGIN
        v_html := '<h3 class="ebs-h">General Ledger — Balances</h3>' ||
                  '<table class="ebs-table"><thead><tr>' ||
                  '<th scope="col">Code</th>' ||
                  '<th scope="col">Account</th>' ||
                  '<th scope="col">Type</th>' ||
                  '<th scope="col" class="num">Balance</th>' ||
                  '</tr></thead><tbody>';

        FOR r IN (
            SELECT code, name, type, balance, currency
              FROM GRANDBACK_GL_ACCOUNTS
             ORDER BY code ASC
        ) LOOP
            v_count := v_count + 1;
            v_html := v_html || '<tr>' ||
                      '<td><code>' || safe_html(r.code) || '</code></td>' ||
                      '<td>' || safe_html(r.name) || '</td>' ||
                      '<td><span class="ebs-tag">' || safe_html(r.type) || '</span></td>' ||
                      '<td class="num">' || fmt_amount(r.balance, r.currency) || '</td>' ||
                      '</tr>';
        END LOOP;

        v_html := v_html || '</tbody></table>';

        IF v_count = 0 THEN
            RETURN render_empty('No Chart of Accounts found.');
        END IF;

        RETURN v_html;
    END format_gl_balances;

    FUNCTION format_consolidated_summary RETURN VARCHAR2 IS
        v_html VARCHAR2(32767);
    BEGIN
        v_html := '<h3 class="ebs-h">Consolidated Portfolio</h3>' ||
                  '<table class="ebs-table"><thead><tr>' ||
                  '<th scope="col">Property</th>' ||
                  '<th scope="col">Currency</th>' ||
                  '<th scope="col" class="num">Open AP</th>' ||
                  '<th scope="col" class="num">Open AR</th>' ||
                  '<th scope="col" class="num">Net</th>' ||
                  '</tr></thead><tbody>';

        FOR r IN (
            SELECT p.name AS property_name, p.currency,
                   NVL((SELECT SUM(amount) FROM GRANDBACK_AP_INVOICES WHERE property_id = p.property_id AND status != 'paid'), 0) AS total_ap,
                   NVL((SELECT SUM(amount) FROM GRANDBACK_AR_INVOICES WHERE property_id = p.property_id AND status != 'paid'), 0) AS total_ar
              FROM GRANDBACK_PROPERTIES p
             ORDER BY p.name ASC
        ) LOOP
            v_html := v_html || '<tr>' ||
                      '<td>' || safe_html(r.property_name) || '</td>' ||
                      '<td>' || safe_html(r.currency) || '</td>' ||
                      '<td class="num">' || fmt_amount(r.total_ap, r.currency) || '</td>' ||
                      '<td class="num">' || fmt_amount(r.total_ar, r.currency) || '</td>' ||
                      '<td class="num">' || fmt_amount(r.total_ar - r.total_ap, r.currency) || '</td>' ||
                      '</tr>';
        END LOOP;

        v_html := v_html || '</tbody></table>';
        RETURN v_html;
    END format_consolidated_summary;

    FUNCTION format_journal_status (p_property_id IN VARCHAR2) RETURN VARCHAR2 IS
        v_html  VARCHAR2(32767);
        v_count INTEGER := 0;
    BEGIN
        v_html := '<h3 class="ebs-h">Journal Entries — ' || safe_html(p_property_id) || '</h3>' ||
                  '<table class="ebs-table"><thead><tr>' ||
                  '<th scope="col">Reference</th>' ||
                  '<th scope="col">Date</th>' ||
                  '<th scope="col">Description</th>' ||
                  '<th scope="col">Author</th>' ||
                  '<th scope="col">Status</th>' ||
                  '</tr></thead><tbody>';

        FOR r IN (
            SELECT reference, entry_date, description, created_by, status
              FROM GRANDBACK_JOURNAL_ENTRIES
             WHERE property_id = p_property_id
             ORDER BY entry_date DESC
        ) LOOP
            v_count := v_count + 1;
            v_html := v_html || '<tr>' ||
                      '<td><code>' || safe_html(r.reference) || '</code></td>' ||
                      '<td>' || TO_CHAR(r.entry_date, 'YYYY-MM-DD') || '</td>' ||
                      '<td>' || safe_html(r.description) || '</td>' ||
                      '<td>' || safe_html(r.created_by) || '</td>' ||
                      '<td>' || status_pill(r.status) || '</td>' ||
                      '</tr>';
        END LOOP;

        v_html := v_html || '</tbody></table>';

        IF v_count = 0 THEN
            RETURN render_empty('No journal entries logged for this property.');
        END IF;

        RETURN v_html;
    END format_journal_status;

    FUNCTION format_property_summary (p_property_id IN VARCHAR2) RETURN VARCHAR2 IS
        v_html      VARCHAR2(32767);
        v_name      VARCHAR2(100);
        v_currency  VARCHAR2(10);
        v_open_ap   NUMBER := 0;
        v_open_ar   NUMBER := 0;
        v_overdue_n NUMBER := 0;
        v_pending_je NUMBER := 0;
        v_top_vendor VARCHAR2(100);
    BEGIN
        BEGIN
            SELECT name, currency INTO v_name, v_currency
              FROM GRANDBACK_PROPERTIES WHERE property_id = p_property_id;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RETURN render_empty('Property ' || safe_html(p_property_id) || ' not found.');
        END;

        SELECT NVL(SUM(amount),0) INTO v_open_ap
          FROM GRANDBACK_AP_INVOICES WHERE property_id = p_property_id AND status != 'paid';

        SELECT NVL(SUM(amount),0) INTO v_open_ar
          FROM GRANDBACK_AR_INVOICES WHERE property_id = p_property_id AND status != 'paid';

        SELECT COUNT(*) INTO v_overdue_n
          FROM (
              SELECT due_date FROM GRANDBACK_AP_INVOICES WHERE property_id = p_property_id AND status != 'paid' AND due_date < TRUNC(SYSDATE)
              UNION ALL
              SELECT due_date FROM GRANDBACK_AR_INVOICES WHERE property_id = p_property_id AND status != 'paid' AND due_date < TRUNC(SYSDATE)
          );

        SELECT COUNT(*) INTO v_pending_je
          FROM GRANDBACK_JOURNAL_ENTRIES WHERE property_id = p_property_id AND status = 'pending_approval';

        BEGIN
            SELECT vendor_name INTO v_top_vendor FROM (
                SELECT v.name AS vendor_name, SUM(i.amount) AS total
                  FROM GRANDBACK_AP_INVOICES i
                  JOIN GRANDBACK_VENDORS v ON i.vendor_id = v.vendor_id
                 WHERE i.property_id = p_property_id AND i.status != 'paid'
                 GROUP BY v.name
                 ORDER BY total DESC
            ) WHERE ROWNUM = 1;
        EXCEPTION WHEN NO_DATA_FOUND THEN v_top_vendor := '—'; END;

        v_html := '<h3 class="ebs-h">' || safe_html(v_name) || '</h3>' ||
                  '<div class="ebs-kpis">' ||
                  '<div class="ebs-kpi"><span class="ebs-kpi__label">Open AP</span><span class="ebs-kpi__value">' || fmt_amount(v_open_ap, v_currency) || '</span></div>' ||
                  '<div class="ebs-kpi"><span class="ebs-kpi__label">Open AR</span><span class="ebs-kpi__value">' || fmt_amount(v_open_ar, v_currency) || '</span></div>' ||
                  '<div class="ebs-kpi"><span class="ebs-kpi__label">Overdue invoices</span><span class="ebs-kpi__value">' || v_overdue_n || '</span></div>' ||
                  '<div class="ebs-kpi"><span class="ebs-kpi__label">Pending journals</span><span class="ebs-kpi__value">' || v_pending_je || '</span></div>' ||
                  '<div class="ebs-kpi ebs-kpi--wide"><span class="ebs-kpi__label">Top vendor exposure</span><span class="ebs-kpi__value">' || safe_html(v_top_vendor) || '</span></div>' ||
                  '</div>';
        RETURN v_html;
    END format_property_summary;

    FUNCTION format_vendor_lookup (p_query IN VARCHAR2) RETURN VARCHAR2 IS
        v_html       VARCHAR2(32767);
        v_match      VARCHAR2(100);
        v_count      INTEGER := 0;
        v_total_ap   NUMBER := 0;
    BEGIN
        v_match := '%' || UPPER(REGEXP_REPLACE(p_query, '(?i).*vendor\s+', '')) || '%';

        v_html := '<h3 class="ebs-h">Vendor lookup</h3>';

        FOR v IN (
            SELECT vendor_id, name, category, payment_terms
              FROM GRANDBACK_VENDORS
             WHERE UPPER(name) LIKE v_match
             ORDER BY name
             FETCH FIRST 5 ROWS ONLY
        ) LOOP
            v_count := v_count + 1;
            v_total_ap := 0;
            SELECT NVL(SUM(amount),0) INTO v_total_ap
              FROM GRANDBACK_AP_INVOICES WHERE vendor_id = v.vendor_id AND status != 'paid';

            v_html := v_html ||
                      '<div class="ebs-card">' ||
                      '<div class="ebs-card__title">' || safe_html(v.name) || '</div>' ||
                      '<div class="ebs-card__meta">' ||
                      '<span><strong>Category:</strong> ' || safe_html(v.category) || '</span>' ||
                      '<span><strong>Terms:</strong> ' || safe_html(v.payment_terms) || '</span>' ||
                      '<span><strong>Open AP:</strong> ' || fmt_amount(v_total_ap, 'EUR') || '</span>' ||
                      '</div>' ||
                      '</div>';
        END LOOP;

        IF v_count = 0 THEN
            RETURN render_empty('No vendor matches found. Try `Show vendor Linen`.');
        END IF;

        RETURN v_html;
    END format_vendor_lookup;

    -- ────────────────────────────────────────────────────────────────────
    -- Phase-1 extension formatters (CM · FA · GL trial balance · supplier risk
    -- · customer balance · expense trend) — added for full module coverage.
    -- ────────────────────────────────────────────────────────────────────

    -- CM: cash position / bank balances (book vs bank, with unreconciled delta)
    FUNCTION format_cash_position (p_property_id IN VARCHAR2) RETURN VARCHAR2 IS
        v_html  VARCHAR2(32767);
        v_count INTEGER := 0;
    BEGIN
        v_html := '<h3 class="ebs-h">Cash Position — Bank Balances</h3>' ||
                  '<table class="ebs-table"><thead><tr>' ||
                  '<th scope="col">Bank</th>' ||
                  '<th scope="col">Account</th>' ||
                  '<th scope="col" class="num">Book</th>' ||
                  '<th scope="col" class="num">Bank</th>' ||
                  '<th scope="col" class="num">Unreconciled</th>' ||
                  '</tr></thead><tbody>';
        FOR r IN (
            SELECT bank_name, account_label, currency, book_balance, bank_balance,
                   (bank_balance - book_balance) AS diff
              FROM GRANDBACK_BANK_ACCOUNTS
             WHERE property_id = p_property_id AND status = 'active'
             ORDER BY bank_name
        ) LOOP
            v_count := v_count + 1;
            v_html := v_html || '<tr>' ||
                      '<td>' || safe_html(r.bank_name) || '</td>' ||
                      '<td>' || safe_html(r.account_label) || '</td>' ||
                      '<td class="num">' || fmt_amount(r.book_balance, r.currency) || '</td>' ||
                      '<td class="num">' || fmt_amount(r.bank_balance, r.currency) || '</td>' ||
                      '<td class="num">' ||
                      CASE WHEN r.diff = 0 THEN '<span class="ebs-num">0.00</span>'
                           ELSE '<span class="ebs-num ebs-num--danger">' || TO_CHAR(r.diff, 'FM999,999,990.00') || '</span>' END ||
                      '</td></tr>';
        END LOOP;
        v_html := v_html || '</tbody></table>';
        IF v_count = 0 THEN
            RETURN render_empty('No bank accounts found for this property.');
        END IF;
        RETURN v_html;
    END format_cash_position;

    -- CM: unreconciled bank transactions
    FUNCTION format_unreconciled (p_property_id IN VARCHAR2) RETURN VARCHAR2 IS
        v_html  VARCHAR2(32767);
        v_count INTEGER := 0;
    BEGIN
        v_html := '<h3 class="ebs-h">Unreconciled Bank Transactions</h3>' ||
                  '<table class="ebs-table"><thead><tr>' ||
                  '<th scope="col">Date</th>' ||
                  '<th scope="col">Account</th>' ||
                  '<th scope="col">Description</th>' ||
                  '<th scope="col" class="num">Amount</th>' ||
                  '</tr></thead><tbody>';
        FOR r IN (
            SELECT t.txn_date, a.account_label, t.description, t.amount, t.currency
              FROM GRANDBACK_BANK_TXNS t
              JOIN GRANDBACK_BANK_ACCOUNTS a ON t.bank_account_id = a.bank_account_id
             WHERE a.property_id = p_property_id AND t.reconciled = 'N'
             ORDER BY t.txn_date DESC
        ) LOOP
            v_count := v_count + 1;
            v_html := v_html || '<tr>' ||
                      '<td>' || TO_CHAR(r.txn_date, 'YYYY-MM-DD') || '</td>' ||
                      '<td>' || safe_html(r.account_label) || '</td>' ||
                      '<td>' || safe_html(r.description) || '</td>' ||
                      '<td class="num">' || fmt_amount(r.amount, r.currency) || '</td>' ||
                      '</tr>';
        END LOOP;
        v_html := v_html || '</tbody></table>';
        IF v_count = 0 THEN
            RETURN render_empty('All bank transactions are reconciled for this property. ✓');
        END IF;
        RETURN v_html;
    END format_unreconciled;

    -- FA: asset register + depreciation status
    FUNCTION format_assets (p_property_id IN VARCHAR2) RETURN VARCHAR2 IS
        v_html  VARCHAR2(32767);
        v_count INTEGER := 0;
    BEGIN
        v_html := '<h3 class="ebs-h">Fixed Asset Register</h3>' ||
                  '<table class="ebs-table"><thead><tr>' ||
                  '<th scope="col">Asset</th>' ||
                  '<th scope="col">Category</th>' ||
                  '<th scope="col" class="num">Cost</th>' ||
                  '<th scope="col" class="num">Net Book Value</th>' ||
                  '<th scope="col">Status</th>' ||
                  '</tr></thead><tbody>';
        FOR r IN (
            SELECT asset_name, category, acquisition_cost, accumulated_depr, currency,
                   (acquisition_cost - accumulated_depr) AS nbv, status
              FROM GRANDBACK_FIXED_ASSETS
             WHERE property_id = p_property_id
             ORDER BY acquisition_cost DESC
        ) LOOP
            v_count := v_count + 1;
            v_html := v_html || '<tr>' ||
                      '<td>' || safe_html(r.asset_name) || '</td>' ||
                      '<td><span class="ebs-tag">' || safe_html(r.category) || '</span></td>' ||
                      '<td class="num">' || fmt_amount(r.acquisition_cost, r.currency) || '</td>' ||
                      '<td class="num">' || fmt_amount(r.nbv, r.currency) || '</td>' ||
                      '<td>' || status_pill(CASE WHEN r.status = 'fully_depreciated' THEN 'posted' ELSE r.status END) || '</td>' ||
                      '</tr>';
        END LOOP;
        v_html := v_html || '</tbody></table>';
        IF v_count = 0 THEN
            RETURN render_empty('No fixed assets registered for this property.');
        END IF;
        RETURN v_html;
    END format_assets;

    -- GL: trial balance summary (totals by account type; Dr/Cr balance check)
    FUNCTION format_trial_balance RETURN VARCHAR2 IS
        v_html   VARCHAR2(32767);
        v_debit  NUMBER := 0;
        v_credit NUMBER := 0;
    BEGIN
        v_html := '<h3 class="ebs-h">Trial Balance — Summary by Type</h3>' ||
                  '<table class="ebs-table"><thead><tr>' ||
                  '<th scope="col">Account Type</th>' ||
                  '<th scope="col" class="num">Total Balance</th>' ||
                  '</tr></thead><tbody>';
        FOR r IN (
            SELECT type, SUM(balance) AS total, MAX(currency) AS currency
              FROM GRANDBACK_GL_ACCOUNTS
             GROUP BY type
             ORDER BY type
        ) LOOP
            v_html := v_html || '<tr>' ||
                      '<td><span class="ebs-tag">' || safe_html(r.type) || '</span></td>' ||
                      '<td class="num">' || fmt_amount(r.total, r.currency) || '</td>' ||
                      '</tr>';
            IF r.type IN ('ASSET','EXPENSE') THEN v_debit := v_debit + r.total;
            ELSE v_credit := v_credit + r.total; END IF;
        END LOOP;
        v_html := v_html ||
                  '<tr class="ebs-row--total"><td><strong>Debit side (Asset+Expense)</strong></td>' ||
                  '<td class="num"><strong>' || fmt_amount(v_debit, 'EUR') || '</strong></td></tr>' ||
                  '<tr class="ebs-row--total"><td><strong>Credit side (Liab+Equity+Income)</strong></td>' ||
                  '<td class="num"><strong>' || fmt_amount(v_credit, 'EUR') || '</strong></td></tr>' ||
                  '</tbody></table>';
        RETURN v_html;
    END format_trial_balance;

    -- AP: supplier risk — vendors with open AP past due > 60 days
    FUNCTION format_supplier_risk (p_property_id IN VARCHAR2) RETURN VARCHAR2 IS
        v_html  VARCHAR2(32767);
        v_count INTEGER := 0;
    BEGIN
        v_html := '<h3 class="ebs-h">Supplier Risk — Payment Delays &gt; 60 days</h3>' ||
                  '<table class="ebs-table"><thead><tr>' ||
                  '<th scope="col">Vendor</th>' ||
                  '<th scope="col">Invoice</th>' ||
                  '<th scope="col" class="num">Amount</th>' ||
                  '<th scope="col" class="num">Days late</th>' ||
                  '</tr></thead><tbody>';
        FOR r IN (
            SELECT v.name AS vendor_name, i.invoice_number, i.amount, i.currency,
                   TRUNC(SYSDATE) - TRUNC(i.due_date) AS days_late
              FROM GRANDBACK_AP_INVOICES i
              JOIN GRANDBACK_VENDORS v ON i.vendor_id = v.vendor_id
             WHERE i.property_id = p_property_id
               AND i.status != 'paid'
               AND (TRUNC(SYSDATE) - TRUNC(i.due_date)) > 60
             ORDER BY days_late DESC
        ) LOOP
            v_count := v_count + 1;
            v_html := v_html || '<tr>' ||
                      '<td>' || safe_html(r.vendor_name) || '</td>' ||
                      '<td><code>' || safe_html(r.invoice_number) || '</code></td>' ||
                      '<td class="num">' || fmt_amount(r.amount, r.currency) || '</td>' ||
                      '<td class="num"><span class="ebs-num ebs-num--danger">+' || r.days_late || '</span></td>' ||
                      '</tr>';
        END LOOP;
        v_html := v_html || '</tbody></table>';
        IF v_count = 0 THEN
            RETURN render_empty('No suppliers with payment delays over 60 days for this property. ✓');
        END IF;
        RETURN v_html;
    END format_supplier_risk;

    -- AR: customer balance — open receivables grouped by customer
    FUNCTION format_customer_balance (p_property_id IN VARCHAR2) RETURN VARCHAR2 IS
        v_html  VARCHAR2(32767);
        v_count INTEGER := 0;
    BEGIN
        v_html := '<h3 class="ebs-h">Customer Balances — Open Receivables</h3>' ||
                  '<table class="ebs-table"><thead><tr>' ||
                  '<th scope="col">Customer</th>' ||
                  '<th scope="col">Segment</th>' ||
                  '<th scope="col" class="num">Open AR</th>' ||
                  '<th scope="col" class="num">Invoices</th>' ||
                  '</tr></thead><tbody>';
        FOR r IN (
            SELECT c.name AS customer_name, c.segment,
                   SUM(i.amount) AS open_ar, COUNT(*) AS inv_count, MAX(i.currency) AS currency
              FROM GRANDBACK_AR_INVOICES i
              JOIN GRANDBACK_CUSTOMERS c ON i.customer_id = c.customer_id
             WHERE i.property_id = p_property_id AND i.status != 'paid'
             GROUP BY c.name, c.segment
             ORDER BY open_ar DESC
        ) LOOP
            v_count := v_count + 1;
            v_html := v_html || '<tr>' ||
                      '<td>' || safe_html(r.customer_name) || '</td>' ||
                      '<td><span class="ebs-tag">' || safe_html(r.segment) || '</span></td>' ||
                      '<td class="num">' || fmt_amount(r.open_ar, r.currency) || '</td>' ||
                      '<td class="num">' || r.inv_count || '</td>' ||
                      '</tr>';
        END LOOP;
        v_html := v_html || '</tbody></table>';
        IF v_count = 0 THEN
            RETURN render_empty('No open customer balances for this property.');
        END IF;
        RETURN v_html;
    END format_customer_balance;

    -- Cross: expense growth trend — expense GL accounts ranked by balance
    FUNCTION format_expense_trend RETURN VARCHAR2 IS
        v_html  VARCHAR2(32767);
        v_total NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(balance),0) INTO v_total FROM GRANDBACK_GL_ACCOUNTS WHERE type = 'EXPENSE';
        v_html := '<h3 class="ebs-h">Expense Trend — by Account</h3>' ||
                  '<table class="ebs-table"><thead><tr>' ||
                  '<th scope="col">Account</th>' ||
                  '<th scope="col" class="num">Balance</th>' ||
                  '<th scope="col" class="num">% of Expense</th>' ||
                  '</tr></thead><tbody>';
        FOR r IN (
            SELECT name, balance, currency
              FROM GRANDBACK_GL_ACCOUNTS
             WHERE type = 'EXPENSE'
             ORDER BY balance DESC
        ) LOOP
            v_html := v_html || '<tr>' ||
                      '<td>' || safe_html(r.name) || '</td>' ||
                      '<td class="num">' || fmt_amount(r.balance, r.currency) || '</td>' ||
                      '<td class="num">' ||
                      CASE WHEN v_total > 0 THEN TO_CHAR(ROUND(r.balance / v_total * 100, 1), 'FM990.0') || '%'
                           ELSE '—' END ||
                      '</td></tr>';
        END LOOP;
        v_html := v_html || '</tbody></table>';
        RETURN v_html;
    END format_expense_trend;

    -- ────────────────────────────────────────────────────────────────────
    -- Pending-approval helpers (replace conversation-scan trick)
    -- ────────────────────────────────────────────────────────────────────
    FUNCTION create_pending_approval (
        p_user_id    IN VARCHAR2,
        p_thread_id  IN VARCHAR2,
        p_target_id  IN VARCHAR2,
        p_payload    IN VARCHAR2
    ) RETURN VARCHAR2 IS
        v_id VARCHAR2(50);
    BEGIN
        v_id := 'pap_' || SYS_GUID();

        -- Auto-cancel any other pending approvals on this thread.
        UPDATE GRANDBACK_PENDING_APPROVALS
           SET status = 'cancelled'
         WHERE thread_id = p_thread_id AND status = 'pending';

        INSERT INTO GRANDBACK_PENDING_APPROVALS (
            approval_id, thread_id, user_id, action_type, target_id, payload_json,
            status, created_at, expires_at
        ) VALUES (
            v_id, p_thread_id, p_user_id, 'pay_invoice', p_target_id, p_payload,
            'pending', SYSTIMESTAMP, SYSTIMESTAMP + NUMTODSINTERVAL(C_PENDING_TTL_MIN * 60, 'SECOND')
        );

        RETURN v_id;
    END create_pending_approval;

    PROCEDURE expire_stale_pending IS
    BEGIN
        UPDATE GRANDBACK_PENDING_APPROVALS
           SET status = 'expired'
         WHERE status = 'pending'
           AND expires_at < SYSTIMESTAMP;
    END expire_stale_pending;

    PROCEDURE cancel_pending_approval (
        p_email     IN VARCHAR2,
        p_thread_id IN VARCHAR2
    ) IS
        v_ctx GRANDBACK_IAM_PKG.user_context_t;
    BEGIN
        v_ctx := GRANDBACK_IAM_PKG.get_user_context(p_email);
        IF NOT v_ctx.is_resolved THEN RETURN; END IF;

        UPDATE GRANDBACK_PENDING_APPROVALS
           SET status = 'cancelled'
         WHERE thread_id = p_thread_id
           AND user_id   = v_ctx.user_id
           AND status    = 'pending';
        COMMIT;
    END cancel_pending_approval;

    -- ────────────────────────────────────────────────────────────────────
    -- bootstrap_user_session — populates application items at login
    -- ────────────────────────────────────────────────────────────────────
    PROCEDURE bootstrap_user_session (p_email IN VARCHAR2) IS
        v_ctx GRANDBACK_IAM_PKG.user_context_t;
    BEGIN
        v_ctx := GRANDBACK_IAM_PKG.get_user_context(p_email);

        IF v_ctx.is_resolved THEN
            APEX_UTIL.SET_SESSION_STATE('G_USER_ID',         v_ctx.user_id);
            APEX_UTIL.SET_SESSION_STATE('G_USER_NAME',       v_ctx.name);
            APEX_UTIL.SET_SESSION_STATE('G_USER_ROLE',       v_ctx.role);
            APEX_UTIL.SET_SESSION_STATE('G_EBS_ROLE',        v_ctx.ebs_role);
            APEX_UTIL.SET_SESSION_STATE('G_PROPERTY_ACCESS', v_ctx.property_access);
        ELSE
            APEX_UTIL.SET_SESSION_STATE('G_USER_ROLE',       'guest');
            APEX_UTIL.SET_SESSION_STATE('G_PROPERTY_ACCESS', '');
        END IF;
    END bootstrap_user_session;

    -- ────────────────────────────────────────────────────────────────────
    -- Core processor
    -- ────────────────────────────────────────────────────────────────────
    FUNCTION process_chat_message (
        p_email       IN VARCHAR2,
        p_ebs_role    IN VARCHAR2,
        p_message     IN VARCHAR2,
        p_property_id IN VARCHAR2,
        p_thread_id   IN VARCHAR2,
        p_session_id  IN VARCHAR2 DEFAULT NULL
    ) RETURN VARCHAR2 IS
        v_ctx               GRANDBACK_IAM_PKG.user_context_t;
        v_action            VARCHAR2(10) := 'read';
        v_validation_res    VARCHAR2(1000);
        v_intent            VARCHAR2(50) := 'general';
        v_reply             VARCHAR2(32767);
        v_requires_approval BOOLEAN := FALSE;
        v_approval_payload  VARCHAR2(4000) := NULL;
        v_pending_id        VARCHAR2(50);
        v_invoice_id        VARCHAR2(50);
        v_invoice_num       VARCHAR2(50);
        v_invoice_amount    NUMBER(15,2);
        v_invoice_status    VARCHAR2(30);
        v_invoice_currency  VARCHAR2(10);
        v_msg_upper         VARCHAR2(4000);
    BEGIN
        v_ctx := GRANDBACK_IAM_PKG.get_user_context(p_email);

        IF NOT v_ctx.is_resolved THEN
            v_reply := '<div class="ebs-alert ebs-alert--danger"><strong>User not recognized.</strong> ' ||
                       'Your APEX login does not map to an GRANDBACK_USERS record. Contact an administrator.</div>';
            RETURN JSON_OBJECT(
                'reply' VALUE v_reply,
                'requires_approval' VALUE FALSE,
                'approval_payload' VALUE NULL,
                'intent' VALUE 'unknown_user'
            );
        END IF;

        -- 0. Length guard
        IF GRANDBACK_IAM_PKG.is_message_too_long(p_message) THEN
            GRANDBACK_IAM_PKG.log_audit(
                p_email, 'INPUT_REJECTED', SUBSTR(p_message,1,200), 'blocked',
                'Message exceeds maximum length',
                v_ctx.role, p_property_id, 'length_guard', p_session_id);
            v_reply := '<div class="ebs-alert ebs-alert--warn"><strong>Message too long.</strong> ' ||
                       'Please keep prompts under 4,000 characters.</div>';
            RETURN JSON_OBJECT(
                'reply' VALUE v_reply,
                'requires_approval' VALUE FALSE,
                'approval_payload' VALUE NULL,
                'intent' VALUE 'length_guard'
            );
        END IF;

        -- Persist user message (escape on the way in so any HTML in raw text stays inert).
        INSERT INTO GRANDBACK_CONVERSATIONS (conversation_id, user_id, thread_id, role, message_content, timestamp)
        VALUES ('chat_msg_' || SYS_GUID(), v_ctx.user_id, p_thread_id, 'user',
                APEX_ESCAPE.HTML(SUBSTR(p_message,1,4000)), SYSTIMESTAMP);

        -- 1. Threat detection
        IF GRANDBACK_IAM_PKG.detect_injection(p_message) THEN
            GRANDBACK_IAM_PKG.log_audit(
                p_email, 'INJECTION_ATTEMPT', p_message, 'blocked',
                'SQL or prompt-injection signatures detected',
                v_ctx.role, p_property_id, 'security_violation', p_session_id);

            v_reply := '<div class="ebs-alert ebs-alert--danger">' ||
                       '<strong>Security threat blocked.</strong> ' ||
                       'Your message matched an SQL or prompt-injection pattern and has been logged. ' ||
                       'If this was a legitimate question, please rephrase it.' ||
                       '</div>';

            INSERT INTO GRANDBACK_CONVERSATIONS (conversation_id, user_id, thread_id, role, message_content, timestamp)
            VALUES ('chat_msg_' || SYS_GUID(), v_ctx.user_id, p_thread_id, 'bot', v_reply, SYSTIMESTAMP);
            COMMIT;

            RETURN JSON_OBJECT(
                'reply' VALUE v_reply,
                'requires_approval' VALUE FALSE,
                'approval_payload' VALUE NULL,
                'intent' VALUE 'security_violation'
            );
        END IF;

        v_msg_upper := UPPER(p_message);

        -- 2. Action classification (write vs read)
        IF v_msg_upper LIKE '%APPROVE%'
           OR v_msg_upper = 'CONFIRM'
           OR v_msg_upper LIKE '%PAY %'
           OR v_msg_upper LIKE '%PAY ' THEN
            v_action := 'write';
        END IF;

        -- 3. IAM gate
        v_validation_res := GRANDBACK_IAM_PKG.validate_action(p_email, p_ebs_role, v_action, p_property_id);

        IF v_validation_res != 'ALLOWED' THEN
            GRANDBACK_IAM_PKG.log_audit(
                p_email,
                CASE WHEN v_action = 'write' THEN 'PAYMENT_APPROVAL' ELSE 'READ_QUERY' END,
                p_message, 'blocked', v_validation_res,
                v_ctx.role, p_property_id, 'access_denied', p_session_id);

            v_reply := '<div class="ebs-alert ebs-alert--danger">' ||
                       '<strong>Access denied.</strong> ' ||
                       safe_html(SUBSTR(v_validation_res, 9)) ||
                       '</div>';

            INSERT INTO GRANDBACK_CONVERSATIONS (conversation_id, user_id, thread_id, role, message_content, timestamp)
            VALUES ('chat_msg_' || SYS_GUID(), v_ctx.user_id, p_thread_id, 'bot', v_reply, SYSTIMESTAMP);
            COMMIT;

            RETURN JSON_OBJECT(
                'reply' VALUE v_reply,
                'requires_approval' VALUE FALSE,
                'approval_payload' VALUE NULL,
                'intent' VALUE 'access_denied'
            );
        END IF;

        -- 4. Intent dispatch
        IF v_msg_upper LIKE '%AP AGING%' OR v_msg_upper LIKE '%PAYABLE%' THEN
            v_intent := 'ap_aging';
            v_reply  := format_ap_aging(p_property_id);

        ELSIF v_msg_upper LIKE '%AR AGING%' OR v_msg_upper LIKE '%RECEIVABLE%' THEN
            v_intent := 'ar_aging';
            v_reply  := format_ar_aging(p_property_id);

        ELSIF v_msg_upper LIKE '%OVERDUE%' THEN
            v_intent := 'overdue';
            v_reply  := format_overdue(p_property_id);

        ELSIF v_msg_upper LIKE '%GL BALANCE%' OR v_msg_upper LIKE '%CASH BALANCE%' OR v_msg_upper LIKE '%CHART OF ACCOUNTS%' THEN
            v_intent := 'gl_balances';
            v_reply  := format_gl_balances;

        ELSIF v_msg_upper LIKE '%CONSOLIDATED%' OR v_msg_upper LIKE '%PORTFOLIO%' THEN
            v_intent := 'consolidated_summary';
            v_reply  := format_consolidated_summary;

        ELSIF v_msg_upper LIKE '%JOURNAL%' THEN
            v_intent := 'journal_status';
            v_reply  := format_journal_status(p_property_id);

        ELSIF v_msg_upper LIKE '%PROPERTY SUMMARY%' OR v_msg_upper LIKE '%SUMMARY FOR%' THEN
            v_intent := 'property_summary';
            v_reply  := format_property_summary(p_property_id);

        ELSIF v_msg_upper LIKE '%SUPPLIER RISK%' OR v_msg_upper LIKE '%PAYMENT DELAY%' THEN
            v_intent := 'supplier_risk';
            v_reply  := format_supplier_risk(p_property_id);

        ELSIF v_msg_upper LIKE '%CUSTOMER BALANCE%' OR v_msg_upper LIKE '%RECEIPTS%' THEN
            v_intent := 'customer_balance';
            v_reply  := format_customer_balance(p_property_id);

        ELSIF v_msg_upper LIKE '%TRIAL BALANCE%' THEN
            v_intent := 'trial_balance';
            v_reply  := format_trial_balance;

        ELSIF v_msg_upper LIKE '%CASH POSITION%' OR v_msg_upper LIKE '%BANK BALANCE%' THEN
            v_intent := 'cash_position';
            v_reply  := format_cash_position(p_property_id);

        ELSIF v_msg_upper LIKE '%UNRECONCILED%' OR v_msg_upper LIKE '%RECONCILIATION%' THEN
            v_intent := 'unreconciled';
            v_reply  := format_unreconciled(p_property_id);

        ELSIF v_msg_upper LIKE '%ASSET%' OR v_msg_upper LIKE '%DEPRECIATION%' THEN
            v_intent := 'asset_register';
            v_reply  := format_assets(p_property_id);

        ELSIF v_msg_upper LIKE '%EXPENSE TREND%' OR v_msg_upper LIKE '%EXPENSE GROWTH%' THEN
            v_intent := 'expense_trend';
            v_reply  := format_expense_trend;

        ELSIF v_msg_upper LIKE 'SHOW VENDOR %' OR v_msg_upper LIKE 'FIND VENDOR %' OR v_msg_upper LIKE 'VENDOR %' THEN
            v_intent := 'vendor_lookup';
            v_reply  := format_vendor_lookup(p_message);

        ELSIF v_msg_upper LIKE '%APPROVE%' OR v_msg_upper LIKE '%PAY %' OR v_msg_upper LIKE '%PAY ' THEN
            v_intent := 'payment_approval';
            v_invoice_id := REGEXP_SUBSTR(LOWER(p_message), 'ap_inv_[0-9]+');

            IF v_invoice_id IS NULL THEN
                v_reply := '<div class="ebs-alert ebs-alert--warn">' ||
                           '<strong>Invoice id required.</strong> ' ||
                           'Try <code>Approve payment for ap_inv_1001</code>.' ||
                           '</div>';
            ELSE
                BEGIN
                    SELECT invoice_number, amount, status, currency
                      INTO v_invoice_num, v_invoice_amount, v_invoice_status, v_invoice_currency
                      FROM GRANDBACK_AP_INVOICES
                     WHERE invoice_id = v_invoice_id;
                EXCEPTION WHEN NO_DATA_FOUND THEN
                    v_reply := '<div class="ebs-alert ebs-alert--warn">' ||
                               '<strong>Invoice not found.</strong> No record matched <code>' ||
                               safe_html(v_invoice_id) || '</code>.</div>';
                END;

                IF v_reply IS NULL THEN
                    IF v_invoice_status = 'paid' THEN
                        v_reply := '<div class="ebs-alert ebs-alert--neutral">' ||
                                   'Invoice <code>' || safe_html(v_invoice_num) || '</code> is already <strong>paid</strong>.' ||
                                   '</div>';
                    ELSE
                        v_approval_payload := JSON_OBJECT(
                            'action'         VALUE 'pay_invoice',
                            'invoice_id'     VALUE v_invoice_id,
                            'invoice_number' VALUE v_invoice_num,
                            'amount'         VALUE v_invoice_amount,
                            'currency'       VALUE v_invoice_currency
                        );
                        v_pending_id := create_pending_approval(
                            p_user_id   => v_ctx.user_id,
                            p_thread_id => p_thread_id,
                            p_target_id => v_invoice_id,
                            p_payload   => v_approval_payload
                        );
                        -- Re-emit payload with the pending id baked in.
                        v_approval_payload := JSON_OBJECT(
                            'approval_id'    VALUE v_pending_id,
                            'action'         VALUE 'pay_invoice',
                            'invoice_id'     VALUE v_invoice_id,
                            'invoice_number' VALUE v_invoice_num,
                            'amount'         VALUE v_invoice_amount,
                            'currency'       VALUE v_invoice_currency
                        );

                        v_requires_approval := TRUE;
                        v_reply := '<div class="ebs-confirm">' ||
                                   '<div class="ebs-confirm__title">Payment approval requested</div>' ||
                                   '<div class="ebs-confirm__body">' ||
                                   'You are about to pay invoice <code>' || safe_html(v_invoice_num) ||
                                   '</code> for <strong>' || fmt_amount(v_invoice_amount, v_invoice_currency) ||
                                   '</strong>. Confirm to commit the DML, or cancel to discard.' ||
                                   '</div></div>';
                    END IF;
                END IF;
            END IF;

        ELSIF v_msg_upper = 'CONFIRM' THEN
            v_intent := 'payment_confirm';
            expire_stale_pending;

            DECLARE
                v_pap_id      VARCHAR2(50);
                v_pap_target  VARCHAR2(100);
                v_pap_payload VARCHAR2(4000);
            BEGIN
                SELECT approval_id, target_id, payload_json
                  INTO v_pap_id, v_pap_target, v_pap_payload
                  FROM (
                      SELECT approval_id, target_id, payload_json
                        FROM GRANDBACK_PENDING_APPROVALS
                       WHERE thread_id = p_thread_id
                         AND user_id   = v_ctx.user_id
                         AND status    = 'pending'
                         AND expires_at >= SYSTIMESTAMP
                       ORDER BY created_at DESC
                  )
                 WHERE ROWNUM = 1;

                UPDATE GRANDBACK_AP_INVOICES
                   SET status = 'paid'
                 WHERE invoice_id = v_pap_target;

                UPDATE GRANDBACK_PENDING_APPROVALS
                   SET status = 'confirmed', confirmed_at = SYSTIMESTAMP
                 WHERE approval_id = v_pap_id;

                SELECT invoice_number, amount, currency
                  INTO v_invoice_num, v_invoice_amount, v_invoice_currency
                  FROM GRANDBACK_AP_INVOICES WHERE invoice_id = v_pap_target;

                v_reply := '<div class="ebs-alert ebs-alert--success">' ||
                           '<strong>Payment Approved Successfully.</strong> Invoice <code>' || safe_html(v_invoice_num) ||
                           '</code> for <strong>' || fmt_amount(v_invoice_amount, v_invoice_currency) ||
                           '</strong> has been marked paid.' ||
                           '</div>';

                GRANDBACK_IAM_PKG.log_audit(
                    p_email, 'DML_EXECUTION', 'Confirmed payment for ' || v_pap_target, 'allowed',
                    'Approval ' || v_pap_id || ' confirmed',
                    v_ctx.role, p_property_id, 'payment_confirm', p_session_id);
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_reply := '<div class="ebs-alert ebs-alert--warn">' ||
                               '<strong>No pending approval found.</strong> ' ||
                               'Either there was nothing to confirm, the request expired, or it was cancelled.' ||
                               '</div>';
            END;

        ELSE
            -- Select AI fallback (kept dynamic so this package compiles on
            -- sandbox instances without DBMS_CLOUD_AI).
            BEGIN
                EXECUTE IMMEDIATE 'BEGIN :1 := DBMS_CLOUD_AI.GENERATE(prompt => :2, profile_name => :3); END;'
                USING OUT v_reply, IN p_message, IN 'GRANDBACK_BOT_PROFILE';
                v_intent := 'select_ai_response';
                GRANDBACK_IAM_PKG.log_audit(
                    p_email, 'READ_QUERY', SUBSTR(p_message,1,1000), 'allowed', 'Select AI response',
                    v_ctx.role, p_property_id, 'select_ai_response', p_session_id);
            EXCEPTION WHEN OTHERS THEN
                v_intent := 'help';
                v_reply :=
                    '<div class="ebs-help">' ||
                    '<p>I can help with these workflows. Try a quick action below or type a request:</p>' ||
                    '<ul>' ||
                    '<li><code>Show AP aging</code> &middot; vendor invoices ranked by due date</li>' ||
                    '<li><code>Show AR aging</code> &middot; customer receivables and days late</li>' ||
                    '<li><code>List overdue invoices</code> &middot; AP + AR past due, days-late ranked</li>' ||
                    '<li><code>Show GL balances</code> &middot; chart of accounts with balances</li>' ||
                    '<li><code>Consolidated portfolio</code> &middot; multi-property net AP/AR</li>' ||
                    '<li><code>Show journals</code> &middot; pending and posted entries</li>' ||
                    '<li><code>Property summary</code> &middot; KPI snapshot for the active property</li>' ||
                    '<li><code>Show vendor Linen</code> &middot; vendor card + outstanding AP</li>' ||
                    '<li><code>Supplier risk</code> &middot; suppliers with payment delays &gt; 60 days</li>' ||
                    '<li><code>Customer balances</code> &middot; open receivables by customer (AR)</li>' ||
                    '<li><code>Trial balance</code> &middot; GL totals by account type with Dr/Cr check</li>' ||
                    '<li><code>Cash position</code> &middot; bank balances, book vs statement (CM)</li>' ||
                    '<li><code>Unreconciled transactions</code> &middot; open bank items (CM)</li>' ||
                    '<li><code>Show assets</code> &middot; fixed asset register + depreciation (FA)</li>' ||
                    '<li><code>Expense trend</code> &middot; expense accounts ranked by share</li>' ||
                    '<li><code>Approve payment for ap_inv_1001</code> &middot; gated payment workflow (manager only)</li>' ||
                    '</ul>' ||
                    '<p class="ebs-muted">Select AI is not configured on this database. Static help shown.</p>' ||
                    '</div>';
            END;
        END IF;

        -- 5. Persist bot reply
        INSERT INTO GRANDBACK_CONVERSATIONS (conversation_id, user_id, thread_id, role, message_content, timestamp)
        VALUES ('chat_msg_' || SYS_GUID(), v_ctx.user_id, p_thread_id, 'bot',
                SUBSTR(v_reply, 1, 4000), SYSTIMESTAMP);

        -- 6. Allowed-path audit
        IF v_intent NOT IN ('security_violation','access_denied','length_guard','select_ai_response','payment_confirm') THEN
            GRANDBACK_IAM_PKG.log_audit(
                p_email, CASE WHEN v_action='write' THEN 'PAYMENT_APPROVAL' ELSE 'READ_QUERY' END,
                SUBSTR(p_message, 1, 1000), 'allowed', 'Intent ' || v_intent,
                v_ctx.role, p_property_id, v_intent, p_session_id);
        END IF;

        COMMIT;

        RETURN JSON_OBJECT(
            'reply'             VALUE v_reply,
            'requires_approval' VALUE v_requires_approval,
            'approval_payload'  VALUE CASE WHEN v_approval_payload IS NOT NULL
                                          THEN JSON_QUERY(v_approval_payload, '$') END,
            'intent'            VALUE v_intent
        );
    END process_chat_message;

END GRANDBACK_BOT_PKG;
/
