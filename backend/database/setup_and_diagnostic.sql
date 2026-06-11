-- ============================================================
-- ACCOR EBS Bot — Diagnostic & Seeding Script
-- Run this block in APEX SQL Workshop > SQL Commands
-- ============================================================
DECLARE
    v_cnt NUMBER;
    v_user_email VARCHAR2(100) := 'MANILTNS@GMAIL.COM';
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ACCOR DIAGNOSTIC & SEEDING SCRIPT ===');

    -- 1. Check and Seed Properties
    SELECT COUNT(*) INTO v_cnt FROM ACCOR_PROPERTIES;
    DBMS_OUTPUT.PUT_LINE('ACCOR_PROPERTIES row count: ' || v_cnt);
    IF v_cnt = 0 THEN
        INSERT INTO ACCOR_PROPERTIES VALUES ('prop_novotel_paris', 'Novotel Paris Centre', 'Novotel', 'Paris', 'France', 'EUR', 'active');
        INSERT INTO ACCOR_PROPERTIES VALUES ('prop_ibis_london', 'Ibis London City', 'Ibis', 'London', 'United Kingdom', 'GBP', 'active');
        INSERT INTO ACCOR_PROPERTIES VALUES ('prop_sofitel_nyc', 'Sofitel New York', 'Sofitel', 'New York', 'USA', 'USD', 'active');
        INSERT INTO ACCOR_PROPERTIES VALUES ('prop_pullman_tokyo', 'Pullman Tokyo Tamachi', 'Pullman', 'Tokyo', 'Japan', 'JPY', 'active');
        DBMS_OUTPUT.PUT_LINE('-> Seeded properties.');
    END IF;

    -- 2. Check and Seed Users
    SELECT COUNT(*) INTO v_cnt FROM ACCOR_USERS;
    DBMS_OUTPUT.PUT_LINE('ACCOR_USERS row count: ' || v_cnt);
    IF v_cnt = 0 THEN
        INSERT INTO ACCOR_USERS VALUES ('accor_usr_analyst', 'analyst@accor.com', 'Pierre Dubois', 'analyst123', 'finance_analyst', 'Finance Analyst', 'prop_novotel_paris,prop_ibis_london', 'ORG_EUR_01', SYSTIMESTAMP);
        INSERT INTO ACCOR_USERS VALUES ('accor_usr_manager', 'manager@accor.com', 'Sophie Martin', 'manager123', 'finance_manager', 'Finance Manager', 'prop_novotel_paris,prop_ibis_london,prop_sofitel_nyc,prop_pullman_tokyo', 'ORG_GLOBAL', SYSTIMESTAMP);
        INSERT INTO ACCOR_USERS VALUES ('accor_usr_admin', 'admin@accor.com', 'System Administrator', 'admin123', 'admin', 'Super Admin', 'prop_novotel_paris,prop_ibis_london,prop_sofitel_nyc,prop_pullman_tokyo', 'ORG_GLOBAL', SYSTIMESTAMP);
        DBMS_OUTPUT.PUT_LINE('-> Seeded default users.');
    END IF;

    -- Check if Developer User exists (case-insensitively)
    SELECT COUNT(*) INTO v_cnt FROM ACCOR_USERS WHERE UPPER(email) = UPPER(v_user_email);
    IF v_cnt = 0 THEN
        INSERT INTO ACCOR_USERS (user_id, email, name, password_hash, role, ebs_role, property_access, org_id)
        VALUES (
            'accor_usr_manil',
            v_user_email,
            'Manil',
            'manil123',
            'finance_manager',
            'Finance Manager',
            'prop_novotel_paris,prop_ibis_london,prop_sofitel_nyc,prop_pullman_tokyo',
            'ORG_GLOBAL'
        );
        DBMS_OUTPUT.PUT_LINE('-> Inserted developer user: ' || v_user_email);
    ELSE
        DBMS_OUTPUT.PUT_LINE('-> Developer user: ' || v_user_email || ' already exists.');
    END IF;

    -- 3. Check and Seed Vendors
    SELECT COUNT(*) INTO v_cnt FROM ACCOR_VENDORS;
    DBMS_OUTPUT.PUT_LINE('ACCOR_VENDORS row count: ' || v_cnt);
    IF v_cnt = 0 THEN
        INSERT INTO ACCOR_VENDORS VALUES ('vend_linen', 'Linen Care Services Ltd', 'Operations', 'NET30');
        INSERT INTO ACCOR_VENDORS VALUES ('vend_fnb', 'Premium Foods & Beverage S.A.', 'F&B Supply', 'NET15');
        INSERT INTO ACCOR_VENDORS VALUES ('vend_energy', 'Global Utilities & Energy Co', 'Utilities', 'DUE_ON_REC');
        INSERT INTO ACCOR_VENDORS VALUES ('vend_security', 'SafeGuard Protection Group', 'Security Services', 'NET45');
        INSERT INTO ACCOR_VENDORS VALUES ('vend_tech', 'Oracle EBS Consulting Partners', 'IT Support', 'NET30');
        DBMS_OUTPUT.PUT_LINE('-> Seeded vendors.');
    END IF;

    -- 4. Check and Seed Customers
    SELECT COUNT(*) INTO v_cnt FROM ACCOR_CUSTOMERS;
    DBMS_OUTPUT.PUT_LINE('ACCOR_CUSTOMERS row count: ' || v_cnt);
    IF v_cnt = 0 THEN
        INSERT INTO ACCOR_CUSTOMERS VALUES ('cust_booking', 'Booking Holdings Inc.', 'OTA', 50000.00);
        INSERT INTO ACCOR_CUSTOMERS VALUES ('cust_amex', 'American Express Global Business Travel', 'Corporate', 100000.00);
        INSERT INTO ACCOR_CUSTOMERS VALUES ('cust_tui', 'TUI Group AG', 'Leisure Tour', 75000.00);
        INSERT INTO ACCOR_CUSTOMERS VALUES ('cust_jtb', 'JTB Corp Japan', 'Regional Corporate', 40000.00);
        DBMS_OUTPUT.PUT_LINE('-> Seeded customers.');
    END IF;

    -- 5. Check and Seed AP Invoices
    SELECT COUNT(*) INTO v_cnt FROM ACCOR_AP_INVOICES;
    DBMS_OUTPUT.PUT_LINE('ACCOR_AP_INVOICES row count: ' || v_cnt);
    IF v_cnt = 0 THEN
        INSERT INTO ACCOR_AP_INVOICES VALUES ('ap_inv_1001', 'INV-LCS-091', 'vend_linen', 'prop_novotel_paris', 2500.00, 'EUR', SYSDATE-45, SYSDATE-15, 'unpaid', 'Laundry and bed linen rental service - April 2026', SYSTIMESTAMP);
        INSERT INTO ACCOR_AP_INVOICES VALUES ('ap_inv_1002', 'INV-PFB-182', 'vend_fnb', 'prop_novotel_paris', 4800.00, 'EUR', SYSDATE-10, SYSDATE+5, 'unpaid', 'F&B kitchen dry supplies and beverages bulk load', SYSTIMESTAMP);
        INSERT INTO ACCOR_AP_INVOICES VALUES ('ap_inv_1003', 'INV-GUE-901', 'vend_energy', 'prop_ibis_london', 1200.00, 'GBP', SYSDATE-95, SYSDATE-95, 'unpaid', 'Electricity usage invoice for Q1 2026', SYSTIMESTAMP);
        INSERT INTO ACCOR_AP_INVOICES VALUES ('ap_inv_1004', 'INV-SGP-339', 'vend_security', 'prop_sofitel_nyc', 6200.00, 'USD', SYSDATE-12, SYSDATE+33, 'pending_approval', 'Security officer deployment - High season May 2026', SYSTIMESTAMP);
        INSERT INTO ACCOR_AP_INVOICES VALUES ('ap_inv_1005', 'INV-OEC-772', 'vend_tech', 'prop_pullman_tokyo', 350000.00, 'JPY', SYSDATE-5, SYSDATE+25, 'paid', 'Oracle EBS functional consultants onboarding fee', SYSTIMESTAMP);
        DBMS_OUTPUT.PUT_LINE('-> Seeded AP invoices.');
    END IF;

    -- 6. Check and Seed AR Invoices
    SELECT COUNT(*) INTO v_cnt FROM ACCOR_AR_INVOICES;
    DBMS_OUTPUT.PUT_LINE('ACCOR_AR_INVOICES row count: ' || v_cnt);
    IF v_cnt = 0 THEN
        INSERT INTO ACCOR_AR_INVOICES VALUES ('ar_inv_2001', 'AR-BHI-401', 'cust_booking', 'prop_novotel_paris', 12500.00, 'EUR', SYSDATE-20, SYSDATE+10, 'unpaid', 'OTA room sales commissions and reconciliation', SYSTIMESTAMP);
        INSERT INTO ACCOR_AR_INVOICES VALUES ('ar_inv_2002', 'AR-AMX-222', 'cust_amex', 'prop_sofitel_nyc', 18200.00, 'USD', SYSDATE-40, SYSDATE-10, 'unpaid', 'Corporate client stays - Q1 group booking rate', SYSTIMESTAMP);
        INSERT INTO ACCOR_AR_INVOICES VALUES ('ar_inv_2003', 'AR-TUI-094', 'cust_tui', 'prop_ibis_london', 7800.00, 'GBP', SYSDATE-2, SYSDATE+28, 'unpaid', 'Tour operator allotments package sales', SYSTIMESTAMP);
        DBMS_OUTPUT.PUT_LINE('-> Seeded AR invoices.');
    END IF;

    -- 7. Check and Seed GL Accounts
    SELECT COUNT(*) INTO v_cnt FROM ACCOR_GL_ACCOUNTS;
    DBMS_OUTPUT.PUT_LINE('ACCOR_GL_ACCOUNTS row count: ' || v_cnt);
    IF v_cnt = 0 THEN
        INSERT INTO ACCOR_GL_ACCOUNTS VALUES ('gl_1010', '1010', 'Cash & Cash Equivalents', 'ASSET', 450000.00, 'EUR');
        INSERT INTO ACCOR_GL_ACCOUNTS VALUES ('gl_1200', '1200', 'Accounts Receivable (Trade)', 'ASSET', 38500.00, 'EUR');
        INSERT INTO ACCOR_GL_ACCOUNTS VALUES ('gl_1300', '1300', 'Prepaid Vendor Expenses', 'ASSET', 12000.00, 'EUR');
        INSERT INTO ACCOR_GL_ACCOUNTS VALUES ('gl_2000', '2000', 'Accounts Payable (Trade)', 'LIABILITY', 8500.00, 'EUR');
        INSERT INTO ACCOR_GL_ACCOUNTS VALUES ('gl_2200', '2200', 'Accrued Taxes Payable', 'LIABILITY', 14200.00, 'EUR');
        INSERT INTO ACCOR_GL_ACCOUNTS VALUES ('gl_3000', '3000', 'Share Capital', 'EQUITY', 200000.00, 'EUR');
        INSERT INTO ACCOR_GL_ACCOUNTS VALUES ('gl_4000', '4000', 'Room Sales Revenue', 'INCOME', 182000.00, 'EUR');
        INSERT INTO ACCOR_GL_ACCOUNTS VALUES ('gl_4100', '4100', 'F&B Sales Revenue', 'INCOME', 43500.00, 'EUR');
        INSERT INTO ACCOR_GL_ACCOUNTS VALUES ('gl_5000', '5000', 'Property Utilities Expenses', 'EXPENSE', 18900.00, 'EUR');
        INSERT INTO ACCOR_GL_ACCOUNTS VALUES ('gl_5100', '5100', 'Linen Operations Expenses', 'EXPENSE', 9200.00, 'EUR');
        INSERT INTO ACCOR_GL_ACCOUNTS VALUES ('gl_5200', '5200', 'IT Infrastructure & Licensing', 'EXPENSE', 24000.00, 'EUR');
        DBMS_OUTPUT.PUT_LINE('-> Seeded GL accounts.');
    END IF;

    -- 8. Check and Seed Journal Entries & Lines
    SELECT COUNT(*) INTO v_cnt FROM ACCOR_JOURNAL_ENTRIES;
    DBMS_OUTPUT.PUT_LINE('ACCOR_JOURNAL_ENTRIES row count: ' || v_cnt);
    IF v_cnt = 0 THEN
        INSERT INTO ACCOR_JOURNAL_ENTRIES VALUES ('accor_je_001', SYSDATE-15, 'JE-2026-004', 'Monthly depreciation of property fixtures', 'prop_novotel_paris', 'Sophie Martin', 'posted', SYSTIMESTAMP);
        INSERT INTO ACCOR_JOURNAL_ENTRIES VALUES ('accor_je_002', SYSDATE-2, 'JE-2026-009', 'Intercompany transfer Novotel Paris -> Sofitel New York', 'prop_novotel_paris', 'Sophie Martin', 'pending_approval', SYSTIMESTAMP);
        
        INSERT INTO ACCOR_JOURNAL_LINES VALUES ('je_line_101', 'accor_je_001', '5000', 1500.00, 0.00);
        INSERT INTO ACCOR_JOURNAL_LINES VALUES ('je_line_102', 'accor_je_001', '1300', 0.00, 1500.00);
        INSERT INTO ACCOR_JOURNAL_LINES VALUES ('je_line_103', 'accor_je_002', '1010', 0.00, 5000.00);
        INSERT INTO ACCOR_JOURNAL_LINES VALUES ('je_line_104', 'accor_je_002', '1200', 5000.00, 0.00);
        DBMS_OUTPUT.PUT_LINE('-> Seeded journal entries & lines.');
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('=== DIAGNOSTIC & SEEDING COMPLETE ===');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error in execution: ' || SQLERRM);
END;
/
