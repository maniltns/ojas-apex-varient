-- Grandback (EBS) Finance Bot — Schema Install Script
-- Target Database: Oracle Autonomous Database (ATP 23ai or 19c)
-- Schema: GRANDBACK_SCHEMA
--
-- Authentication note:
--   Login credentials are managed by APEX Accounts (oracleApexAccounts).
--   GRANDBACK_USERS.password_hash is therefore unused and stores a sentinel value.
--   The table acts as a profile/role registry keyed on `email`, looked up
--   post-login by GRANDBACK_BOT_PKG.bootstrap_user_session.

-- Drop existing tables if they exist to support clean re-runs
BEGIN
   FOR r IN (SELECT table_name FROM user_tables WHERE table_name LIKE 'GRANDBACK_%') LOOP
      EXECUTE IMMEDIATE 'DROP TABLE ' || r.table_name || ' CASCADE CONSTRAINTS';
   END LOOP;
END;
/

-- 1. GRANDBACK PROPERTIES
CREATE TABLE GRANDBACK_PROPERTIES (
    property_id   VARCHAR2(50) PRIMARY KEY,
    name          VARCHAR2(100) NOT NULL,
    brand         VARCHAR2(50),
    city          VARCHAR2(50),
    country       VARCHAR2(50),
    currency      VARCHAR2(10),
    status        VARCHAR2(20) DEFAULT 'active'
);

-- 2. GRANDBACK USERS (profile/role registry — auth is APEX Accounts)
CREATE TABLE GRANDBACK_USERS (
    user_id          VARCHAR2(50) PRIMARY KEY,
    email            VARCHAR2(100) UNIQUE NOT NULL,
    name             VARCHAR2(100) NOT NULL,
    password_hash    VARCHAR2(200) NOT NULL,
    role             VARCHAR2(50) NOT NULL,
    ebs_role         VARCHAR2(50) NOT NULL,
    property_access  VARCHAR2(4000) NOT NULL,
    org_id           VARCHAR2(50) NOT NULL,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. GRANDBACK VENDORS
CREATE TABLE GRANDBACK_VENDORS (
    vendor_id      VARCHAR2(50) PRIMARY KEY,
    name           VARCHAR2(100) NOT NULL,
    category       VARCHAR2(50),
    payment_terms  VARCHAR2(20)
);

-- 4. GRANDBACK CUSTOMERS
CREATE TABLE GRANDBACK_CUSTOMERS (
    customer_id   VARCHAR2(50) PRIMARY KEY,
    name          VARCHAR2(100) NOT NULL,
    segment       VARCHAR2(50),
    credit_limit  NUMBER(15,2)
);

-- 5. ACCOUNTS PAYABLE (AP) INVOICES
CREATE TABLE GRANDBACK_AP_INVOICES (
    invoice_id      VARCHAR2(50) PRIMARY KEY,
    invoice_number  VARCHAR2(50) UNIQUE NOT NULL,
    vendor_id       VARCHAR2(50) REFERENCES GRANDBACK_VENDORS(vendor_id),
    property_id     VARCHAR2(50) REFERENCES GRANDBACK_PROPERTIES(property_id),
    amount          NUMBER(15,2) NOT NULL,
    currency        VARCHAR2(10) NOT NULL,
    invoice_date    DATE NOT NULL,
    due_date        DATE NOT NULL,
    status          VARCHAR2(30) DEFAULT 'unpaid',
    description     VARCHAR2(500),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 6. ACCOUNTS RECEIVABLE (AR) INVOICES
CREATE TABLE GRANDBACK_AR_INVOICES (
    invoice_id      VARCHAR2(50) PRIMARY KEY,
    invoice_number  VARCHAR2(50) UNIQUE NOT NULL,
    customer_id     VARCHAR2(50) REFERENCES GRANDBACK_CUSTOMERS(customer_id),
    property_id     VARCHAR2(50) REFERENCES GRANDBACK_PROPERTIES(property_id),
    amount          NUMBER(15,2) NOT NULL,
    currency        VARCHAR2(10) NOT NULL,
    invoice_date    DATE NOT NULL,
    due_date        DATE NOT NULL,
    status          VARCHAR2(30) DEFAULT 'unpaid',
    description     VARCHAR2(500),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 7. GENERAL LEDGER (GL) CHART OF ACCOUNTS
CREATE TABLE GRANDBACK_GL_ACCOUNTS (
    account_id  VARCHAR2(50) PRIMARY KEY,
    code        VARCHAR2(20) UNIQUE NOT NULL,
    name        VARCHAR2(100) NOT NULL,
    type        VARCHAR2(20) CHECK (type IN ('ASSET', 'LIABILITY', 'EQUITY', 'INCOME', 'EXPENSE')),
    balance     NUMBER(15,2) DEFAULT 0.00,
    currency    VARCHAR2(10) NOT NULL
);

-- 8. JOURNAL ENTRIES
CREATE TABLE GRANDBACK_JOURNAL_ENTRIES (
    entry_id     VARCHAR2(50) PRIMARY KEY,
    entry_date   DATE NOT NULL,
    reference    VARCHAR2(50) NOT NULL,
    description  VARCHAR2(500),
    property_id  VARCHAR2(50) REFERENCES GRANDBACK_PROPERTIES(property_id),
    created_by   VARCHAR2(100) NOT NULL,
    status       VARCHAR2(30) DEFAULT 'pending_approval',
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 9. JOURNAL LINES
CREATE TABLE GRANDBACK_JOURNAL_LINES (
    line_id       VARCHAR2(50) PRIMARY KEY,
    entry_id      VARCHAR2(50) REFERENCES GRANDBACK_JOURNAL_ENTRIES(entry_id) ON DELETE CASCADE,
    account_code  VARCHAR2(20) REFERENCES GRANDBACK_GL_ACCOUNTS(code),
    debit         NUMBER(15,2) DEFAULT 0.00,
    credit        NUMBER(15,2) DEFAULT 0.00
);

-- 10. SYSTEM AUDIT & SECURITY LOGS (extended with session/role/property/intent context)
CREATE TABLE GRANDBACK_AUDIT_LOG (
    log_id       VARCHAR2(50) DEFAULT SYS_GUID() PRIMARY KEY,
    user_id      VARCHAR2(50),
    email        VARCHAR2(100) NOT NULL,
    action_type  VARCHAR2(50) NOT NULL,
    query_text   VARCHAR2(4000),
    status       VARCHAR2(20) CHECK (status IN ('allowed', 'blocked')),
    reason       VARCHAR2(1000),
    role         VARCHAR2(50),
    property_id  VARCHAR2(50),
    intent       VARCHAR2(50),
    session_id   VARCHAR2(100),
    request_ip   VARCHAR2(45),
    timestamp    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 11. CHAT CONVERSATION HISTORY LOGS
CREATE TABLE GRANDBACK_CONVERSATIONS (
    conversation_id VARCHAR2(50) PRIMARY KEY,
    user_id         VARCHAR2(50) REFERENCES GRANDBACK_USERS(user_id),
    thread_id       VARCHAR2(100) NOT NULL,
    role            VARCHAR2(20) NOT NULL,
    message_content VARCHAR2(4000) NOT NULL,
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 12. PENDING APPROVALS (gated DML state — replaces conversation-scan trick)
CREATE TABLE GRANDBACK_PENDING_APPROVALS (
    approval_id    VARCHAR2(50) DEFAULT SYS_GUID() PRIMARY KEY,
    thread_id      VARCHAR2(100) NOT NULL,
    user_id        VARCHAR2(50) REFERENCES GRANDBACK_USERS(user_id),
    action_type    VARCHAR2(50) NOT NULL,        -- pay_invoice, post_journal, ...
    target_id      VARCHAR2(100) NOT NULL,       -- e.g. ap_inv_1001
    payload_json   VARCHAR2(4000),
    status         VARCHAR2(20) DEFAULT 'pending'
                   CHECK (status IN ('pending','confirmed','cancelled','expired')),
    created_at     TIMESTAMP DEFAULT SYSTIMESTAMP,
    expires_at     TIMESTAMP DEFAULT SYSTIMESTAMP + INTERVAL '15' MINUTE,
    confirmed_at   TIMESTAMP
);

-- 13. CASH MANAGEMENT (CM) — BANK ACCOUNTS
CREATE TABLE GRANDBACK_BANK_ACCOUNTS (
    bank_account_id VARCHAR2(50) PRIMARY KEY,
    property_id     VARCHAR2(50) REFERENCES GRANDBACK_PROPERTIES(property_id),
    bank_name       VARCHAR2(100) NOT NULL,
    account_label   VARCHAR2(100) NOT NULL,
    currency        VARCHAR2(10) NOT NULL,
    book_balance    NUMBER(15,2) DEFAULT 0.00,   -- GL/cash-book view
    bank_balance    NUMBER(15,2) DEFAULT 0.00,   -- statement view (diff = unreconciled)
    status          VARCHAR2(20) DEFAULT 'active'
);

-- 14. CASH MANAGEMENT (CM) — BANK TRANSACTIONS (reconciliation source)
CREATE TABLE GRANDBACK_BANK_TXNS (
    txn_id          VARCHAR2(50) PRIMARY KEY,
    bank_account_id VARCHAR2(50) REFERENCES GRANDBACK_BANK_ACCOUNTS(bank_account_id),
    txn_date        DATE NOT NULL,
    description     VARCHAR2(200),
    amount          NUMBER(15,2) NOT NULL,        -- +receipt / -payment
    currency        VARCHAR2(10) NOT NULL,
    reconciled      VARCHAR2(1) DEFAULT 'N' CHECK (reconciled IN ('Y','N'))
);

-- 15. FIXED ASSETS (FA) — ASSET REGISTER
CREATE TABLE GRANDBACK_FIXED_ASSETS (
    asset_id          VARCHAR2(50) PRIMARY KEY,
    property_id       VARCHAR2(50) REFERENCES GRANDBACK_PROPERTIES(property_id),
    asset_name        VARCHAR2(100) NOT NULL,
    category          VARCHAR2(50),
    acquisition_cost  NUMBER(15,2) NOT NULL,
    accumulated_depr  NUMBER(15,2) DEFAULT 0.00,
    currency          VARCHAR2(10) NOT NULL,
    in_service_date   DATE,
    useful_life_years NUMBER(4) DEFAULT 5,
    status            VARCHAR2(20) DEFAULT 'in_service'  -- in_service / fully_depreciated / disposed
);

-- Indexing for performance
CREATE INDEX IDX_GRANDBACK_AP_PROP ON GRANDBACK_AP_INVOICES(property_id);
CREATE INDEX IDX_GRANDBACK_AR_PROP ON GRANDBACK_AR_INVOICES(property_id);
CREATE INDEX IDX_GRANDBACK_JE_PROP ON GRANDBACK_JOURNAL_ENTRIES(property_id);
CREATE INDEX IDX_GRANDBACK_AUDIT_EMAIL ON GRANDBACK_AUDIT_LOG(email);
CREATE INDEX IDX_GRANDBACK_AUDIT_TS ON GRANDBACK_AUDIT_LOG(timestamp);
CREATE INDEX IDX_GRANDBACK_PEND_THREAD ON GRANDBACK_PENDING_APPROVALS(thread_id, status);
CREATE INDEX IDX_GRANDBACK_CONV_THREAD ON GRANDBACK_CONVERSATIONS(thread_id, timestamp);
CREATE INDEX IDX_GRANDBACK_BANK_PROP ON GRANDBACK_BANK_ACCOUNTS(property_id);
CREATE INDEX IDX_GRANDBACK_BANKTXN_ACCT ON GRANDBACK_BANK_TXNS(bank_account_id, reconciled);
CREATE INDEX IDX_GRANDBACK_FA_PROP ON GRANDBACK_FIXED_ASSETS(property_id);

-- =====================================================================
-- Seed Data
-- =====================================================================

-- Properties
INSERT INTO GRANDBACK_PROPERTIES VALUES ('prop_novotel_paris', 'Novotel Paris Centre', 'Novotel', 'Paris', 'France', 'EUR', 'active');
INSERT INTO GRANDBACK_PROPERTIES VALUES ('prop_ibis_london', 'Ibis London City', 'Ibis', 'London', 'United Kingdom', 'GBP', 'active');
INSERT INTO GRANDBACK_PROPERTIES VALUES ('prop_sofitel_nyc', 'Sofitel New York', 'Sofitel', 'New York', 'USA', 'USD', 'active');
INSERT INTO GRANDBACK_PROPERTIES VALUES ('prop_pullman_tokyo', 'Pullman Tokyo Tamachi', 'Pullman', 'Tokyo', 'Japan', 'JPY', 'active');

-- Users (password_hash = sentinel; auth handled by APEX Accounts)
INSERT INTO GRANDBACK_USERS VALUES ('gb_usr_analyst', 'analyst@accor.com', 'Pierre Dubois', 'managed_by_apex_accounts', 'finance_analyst', 'Finance Analyst', 'prop_novotel_paris,prop_ibis_london', 'ORG_EUR_01', SYSTIMESTAMP);
INSERT INTO GRANDBACK_USERS VALUES ('gb_usr_manager', 'manager@accor.com', 'Sophie Martin', 'managed_by_apex_accounts', 'finance_manager', 'Finance Manager', 'prop_novotel_paris,prop_ibis_london,prop_sofitel_nyc,prop_pullman_tokyo', 'ORG_GLOBAL', SYSTIMESTAMP);
INSERT INTO GRANDBACK_USERS VALUES ('gb_usr_admin', 'admin@accor.com', 'managed_by_apex_accounts', 'managed_by_apex_accounts', 'admin', 'Super Admin', 'prop_novotel_paris,prop_ibis_london,prop_sofitel_nyc,prop_pullman_tokyo', 'ORG_GLOBAL', SYSTIMESTAMP);
-- RFP personas: Cash Manager (CM scope, write), Controller (GL/close scope, write), Executive (all properties, read-only consolidated)
INSERT INTO GRANDBACK_USERS VALUES ('gb_usr_cashmgr', 'cashmgr@accor.com', 'Marie Laurent', 'managed_by_apex_accounts', 'finance_manager', 'Cash Manager', 'prop_novotel_paris,prop_ibis_london', 'ORG_EUR_01', SYSTIMESTAMP);
INSERT INTO GRANDBACK_USERS VALUES ('gb_usr_controller', 'controller@accor.com', 'James Whitfield', 'managed_by_apex_accounts', 'finance_manager', 'Controller', 'prop_novotel_paris,prop_ibis_london,prop_sofitel_nyc,prop_pullman_tokyo', 'ORG_GLOBAL', SYSTIMESTAMP);
INSERT INTO GRANDBACK_USERS VALUES ('gb_usr_exec', 'exec@accor.com', 'Isabelle Moreau', 'managed_by_apex_accounts', 'finance_analyst', 'Executive', 'prop_novotel_paris,prop_ibis_london,prop_sofitel_nyc,prop_pullman_tokyo', 'ORG_GLOBAL', SYSTIMESTAMP);

-- Vendors
INSERT INTO GRANDBACK_VENDORS VALUES ('vend_linen', 'Linen Care Services Ltd', 'Operations', 'NET30');
INSERT INTO GRANDBACK_VENDORS VALUES ('vend_fnb', 'Premium Foods & Beverage S.A.', 'F&B Supply', 'NET15');
INSERT INTO GRANDBACK_VENDORS VALUES ('vend_energy', 'Global Utilities & Energy Co', 'Utilities', 'DUE_ON_REC');
INSERT INTO GRANDBACK_VENDORS VALUES ('vend_security', 'SafeGuard Protection Group', 'Security Services', 'NET45');
INSERT INTO GRANDBACK_VENDORS VALUES ('vend_tech', 'Oracle EBS Consulting Partners', 'IT Support', 'NET30');
INSERT INTO GRANDBACK_VENDORS VALUES ('vend_marketing', 'Mosaic Brand Communications', 'Marketing', 'NET30');

-- Customers
INSERT INTO GRANDBACK_CUSTOMERS VALUES ('cust_booking', 'Booking Holdings Inc.', 'OTA', 50000.00);
INSERT INTO GRANDBACK_CUSTOMERS VALUES ('cust_amex', 'American Express Global Business Travel', 'Corporate', 100000.00);
INSERT INTO GRANDBACK_CUSTOMERS VALUES ('cust_tui', 'TUI Group AG', 'Leisure Tour', 75000.00);
INSERT INTO GRANDBACK_CUSTOMERS VALUES ('cust_jtb', 'JTB Corp Japan', 'Regional Corporate', 40000.00);
INSERT INTO GRANDBACK_CUSTOMERS VALUES ('cust_marriott_grp', 'Global Conference Group LLC', 'MICE', 60000.00);

-- AP Invoices (mix of unpaid / overdue / paid / pending_approval to exercise all formatters)
INSERT INTO GRANDBACK_AP_INVOICES VALUES ('ap_inv_1001', 'INV-LCS-091', 'vend_linen', 'prop_novotel_paris', 2500.00, 'EUR', SYSDATE-45, SYSDATE-15, 'unpaid', 'Laundry and bed linen rental service - April 2026', SYSTIMESTAMP);
INSERT INTO GRANDBACK_AP_INVOICES VALUES ('ap_inv_1002', 'INV-PFB-182', 'vend_fnb', 'prop_novotel_paris', 4800.00, 'EUR', SYSDATE-10, SYSDATE+5, 'unpaid', 'F&B kitchen dry supplies and beverages bulk load', SYSTIMESTAMP);
INSERT INTO GRANDBACK_AP_INVOICES VALUES ('ap_inv_1003', 'INV-GUE-901', 'vend_energy', 'prop_ibis_london', 1200.00, 'GBP', SYSDATE-95, SYSDATE-95, 'unpaid', 'Electricity usage invoice for Q1 2026', SYSTIMESTAMP);
INSERT INTO GRANDBACK_AP_INVOICES VALUES ('ap_inv_1004', 'INV-SGP-339', 'vend_security', 'prop_sofitel_nyc', 6200.00, 'USD', SYSDATE-12, SYSDATE+33, 'pending_approval', 'Security officer deployment - High season May 2026', SYSTIMESTAMP);
INSERT INTO GRANDBACK_AP_INVOICES VALUES ('ap_inv_1005', 'INV-OEC-772', 'vend_tech', 'prop_pullman_tokyo', 350000.00, 'JPY', SYSDATE-5, SYSDATE+25, 'paid', 'Oracle EBS functional consultants onboarding fee', SYSTIMESTAMP);
INSERT INTO GRANDBACK_AP_INVOICES VALUES ('ap_inv_1006', 'INV-MBC-441', 'vend_marketing', 'prop_novotel_paris', 8200.00, 'EUR', SYSDATE-22, SYSDATE-2, 'unpaid', 'Q2 brand campaign creative production', SYSTIMESTAMP);
INSERT INTO GRANDBACK_AP_INVOICES VALUES ('ap_inv_1007', 'INV-LCS-104', 'vend_linen', 'prop_ibis_london', 980.00, 'GBP', SYSDATE-3, SYSDATE+27, 'unpaid', 'Linen rental top-up — premium suite block', SYSTIMESTAMP);

-- AR Invoices
INSERT INTO GRANDBACK_AR_INVOICES VALUES ('ar_inv_2001', 'AR-BHI-401', 'cust_booking', 'prop_novotel_paris', 12500.00, 'EUR', SYSDATE-20, SYSDATE+10, 'unpaid', 'OTA room sales commissions and reconciliation', SYSTIMESTAMP);
INSERT INTO GRANDBACK_AR_INVOICES VALUES ('ar_inv_2002', 'AR-AMX-222', 'cust_amex', 'prop_sofitel_nyc', 18200.00, 'USD', SYSDATE-40, SYSDATE-10, 'unpaid', 'Corporate client stays - Q1 group booking rate', SYSTIMESTAMP);
INSERT INTO GRANDBACK_AR_INVOICES VALUES ('ar_inv_2003', 'AR-TUI-094', 'cust_tui', 'prop_ibis_london', 7800.00, 'GBP', SYSDATE-2, SYSDATE+28, 'unpaid', 'Tour operator allotments package sales', SYSTIMESTAMP);
INSERT INTO GRANDBACK_AR_INVOICES VALUES ('ar_inv_2004', 'AR-MGC-118', 'cust_marriott_grp', 'prop_sofitel_nyc', 24500.00, 'USD', SYSDATE-8, SYSDATE+22, 'unpaid', 'Conference block — Q2 leadership offsite', SYSTIMESTAMP);
INSERT INTO GRANDBACK_AR_INVOICES VALUES ('ar_inv_2005', 'AR-JTB-052', 'cust_jtb', 'prop_pullman_tokyo', 1850000.00, 'JPY', SYSDATE-65, SYSDATE-35, 'unpaid', 'Inbound tour group reconciliation — March', SYSTIMESTAMP);

-- GL Accounts
INSERT INTO GRANDBACK_GL_ACCOUNTS VALUES ('gl_1010', '1010', 'Cash & Cash Equivalents', 'ASSET', 450000.00, 'EUR');
INSERT INTO GRANDBACK_GL_ACCOUNTS VALUES ('gl_1200', '1200', 'Accounts Receivable (Trade)', 'ASSET', 38500.00, 'EUR');
INSERT INTO GRANDBACK_GL_ACCOUNTS VALUES ('gl_1300', '1300', 'Prepaid Vendor Expenses', 'ASSET', 12000.00, 'EUR');
INSERT INTO GRANDBACK_GL_ACCOUNTS VALUES ('gl_2000', '2000', 'Accounts Payable (Trade)', 'LIABILITY', 8500.00, 'EUR');
INSERT INTO GRANDBACK_GL_ACCOUNTS VALUES ('gl_2200', '2200', 'Accrued Taxes Payable', 'LIABILITY', 14200.00, 'EUR');
INSERT INTO GRANDBACK_GL_ACCOUNTS VALUES ('gl_3000', '3000', 'Share Capital', 'EQUITY', 200000.00, 'EUR');
INSERT INTO GRANDBACK_GL_ACCOUNTS VALUES ('gl_4000', '4000', 'Room Sales Revenue', 'INCOME', 182000.00, 'EUR');
INSERT INTO GRANDBACK_GL_ACCOUNTS VALUES ('gl_4100', '4100', 'F&B Sales Revenue', 'INCOME', 43500.00, 'EUR');
INSERT INTO GRANDBACK_GL_ACCOUNTS VALUES ('gl_5000', '5000', 'Property Utilities Expenses', 'EXPENSE', 18900.00, 'EUR');
INSERT INTO GRANDBACK_GL_ACCOUNTS VALUES ('gl_5100', '5100', 'Linen Operations Expenses', 'EXPENSE', 9200.00, 'EUR');
INSERT INTO GRANDBACK_GL_ACCOUNTS VALUES ('gl_5200', '5200', 'IT Infrastructure & Licensing', 'EXPENSE', 24000.00, 'EUR');

-- Journal Entries
INSERT INTO GRANDBACK_JOURNAL_ENTRIES VALUES ('gb_je_001', SYSDATE-15, 'JE-2026-004', 'Monthly depreciation of property fixtures', 'prop_novotel_paris', 'Sophie Martin', 'posted', SYSTIMESTAMP);
INSERT INTO GRANDBACK_JOURNAL_ENTRIES VALUES ('gb_je_002', SYSDATE-2,  'JE-2026-009', 'Intercompany transfer Novotel Paris -> Sofitel New York', 'prop_novotel_paris', 'Sophie Martin', 'pending_approval', SYSTIMESTAMP);
INSERT INTO GRANDBACK_JOURNAL_ENTRIES VALUES ('gb_je_003', SYSDATE-7,  'JE-2026-011', 'Q2 prepaid utilities reclassification', 'prop_ibis_london', 'Sophie Martin', 'pending_approval', SYSTIMESTAMP);
INSERT INTO GRANDBACK_JOURNAL_ENTRIES VALUES ('gb_je_004', SYSDATE-30, 'JE-2026-002', 'Year-end revenue accrual — banquet division', 'prop_sofitel_nyc',  'Sophie Martin', 'posted', SYSTIMESTAMP);

-- Journal Lines
INSERT INTO GRANDBACK_JOURNAL_LINES VALUES ('je_line_101', 'gb_je_001', '5000', 1500.00, 0.00);
INSERT INTO GRANDBACK_JOURNAL_LINES VALUES ('je_line_102', 'gb_je_001', '1300', 0.00, 1500.00);
INSERT INTO GRANDBACK_JOURNAL_LINES VALUES ('je_line_103', 'gb_je_002', '1010', 0.00, 5000.00);
INSERT INTO GRANDBACK_JOURNAL_LINES VALUES ('je_line_104', 'gb_je_002', '1200', 5000.00, 0.00);
INSERT INTO GRANDBACK_JOURNAL_LINES VALUES ('je_line_105', 'gb_je_003', '1300', 3200.00, 0.00);
INSERT INTO GRANDBACK_JOURNAL_LINES VALUES ('je_line_106', 'gb_je_003', '5000', 0.00, 3200.00);

-- Bank Accounts (CM) — book vs bank balance differs where there are unreconciled txns
INSERT INTO GRANDBACK_BANK_ACCOUNTS VALUES ('bank_np_eur', 'prop_novotel_paris', 'BNP Paribas', 'Novotel Paris — Operating EUR', 'EUR', 412300.00, 415100.00, 'active');
INSERT INTO GRANDBACK_BANK_ACCOUNTS VALUES ('bank_il_gbp', 'prop_ibis_london', 'Barclays', 'Ibis London — Operating GBP', 'GBP', 88750.00, 88750.00, 'active');
INSERT INTO GRANDBACK_BANK_ACCOUNTS VALUES ('bank_sn_usd', 'prop_sofitel_nyc', 'Citibank', 'Sofitel NYC — Operating USD', 'USD', 305000.00, 311400.00, 'active');
INSERT INTO GRANDBACK_BANK_ACCOUNTS VALUES ('bank_pt_jpy', 'prop_pullman_tokyo', 'MUFG Bank', 'Pullman Tokyo — Operating JPY', 'JPY', 9850000.00, 9850000.00, 'active');

-- Bank Transactions — some unreconciled (reconciled='N') to exercise CM reconciliation use case
INSERT INTO GRANDBACK_BANK_TXNS VALUES ('btxn_001', 'bank_np_eur', SYSDATE-3, 'Card settlement batch — front desk', 2800.00, 'EUR', 'N');
INSERT INTO GRANDBACK_BANK_TXNS VALUES ('btxn_002', 'bank_np_eur', SYSDATE-9, 'Supplier payment — Linen Care', -2500.00, 'EUR', 'Y');
INSERT INTO GRANDBACK_BANK_TXNS VALUES ('btxn_003', 'bank_sn_usd', SYSDATE-2, 'Group deposit — conference block', 6400.00, 'USD', 'N');
INSERT INTO GRANDBACK_BANK_TXNS VALUES ('btxn_004', 'bank_sn_usd', SYSDATE-6, 'Utility direct debit', -1850.00, 'USD', 'Y');
INSERT INTO GRANDBACK_BANK_TXNS VALUES ('btxn_005', 'bank_il_gbp', SYSDATE-4, 'OTA remittance — Booking', 5200.00, 'GBP', 'Y');

-- Fixed Assets (FA) — register with depreciation status
INSERT INTO GRANDBACK_FIXED_ASSETS VALUES ('fa_np_hvac', 'prop_novotel_paris', 'HVAC Plant — Main Building', 'Building Systems', 240000.00, 96000.00, 'EUR', ADD_MONTHS(SYSDATE,-48), 10, 'in_service');
INSERT INTO GRANDBACK_FIXED_ASSETS VALUES ('fa_np_kitchen', 'prop_novotel_paris', 'Commercial Kitchen Equipment', 'F&B Equipment', 85000.00, 68000.00, 'EUR', ADD_MONTHS(SYSDATE,-72), 8, 'in_service');
INSERT INTO GRANDBACK_FIXED_ASSETS VALUES ('fa_sn_elev', 'prop_sofitel_nyc', 'Elevator Modernization', 'Building Systems', 520000.00, 130000.00, 'USD', ADD_MONTHS(SYSDATE,-36), 15, 'in_service');
INSERT INTO GRANDBACK_FIXED_ASSETS VALUES ('fa_il_fitout', 'prop_ibis_london', 'Lobby Fit-out & Furniture', 'FF&E', 64000.00, 64000.00, 'GBP', ADD_MONTHS(SYSDATE,-96), 7, 'fully_depreciated');
INSERT INTO GRANDBACK_FIXED_ASSETS VALUES ('fa_pt_it', 'prop_pullman_tokyo', 'PMS & Network Infrastructure', 'IT Hardware', 12000000.00, 7200000.00, 'JPY', ADD_MONTHS(SYSDATE,-30), 5, 'in_service');

-- Initial Audit Log
INSERT INTO GRANDBACK_AUDIT_LOG (user_id, email, action_type, query_text, status, reason, role, property_id, intent, session_id, timestamp)
VALUES ('gb_usr_admin', 'admin@accor.com', 'SYSTEM', 'Initialize Grandback (EBS) Finance Database Seeding', 'allowed', 'System startup initialization successfully seeded', 'admin', NULL, 'system_init', NULL, SYSTIMESTAMP);

COMMIT;
