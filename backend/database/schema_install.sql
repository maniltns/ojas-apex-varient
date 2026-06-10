-- Native Oracle APEX & OCI EBS Conversational Bot Schema Install Script
-- Target Database: Oracle Autonomous Database (ATP 23ai or 19c)
-- Schema: ACCOR_SCHEMA

-- Drop existing tables if they exist to support clean re-runs
BEGIN
   FOR r IN (SELECT table_name FROM user_tables WHERE table_name LIKE 'ACCOR_%') LOOP
      EXECUTE IMMEDIATE 'DROP TABLE ' || r.table_name || ' CASCADE CONSTRAINTS';
   END LOOP;
END;
/

-- 1. ACCOR PROPERTIES
CREATE TABLE ACCOR_PROPERTIES (
    property_id   VARCHAR2(50) PRIMARY KEY,
    name          VARCHAR2(100) NOT NULL,
    brand         VARCHAR2(50),
    city          VARCHAR2(50),
    country       VARCHAR2(50),
    currency      VARCHAR2(10),
    status        VARCHAR2(20) DEFAULT 'active'
);

-- 2. ACCOR USERS
CREATE TABLE ACCOR_USERS (
    user_id          VARCHAR2(50) PRIMARY KEY,
    email            VARCHAR2(100) UNIQUE NOT NULL,
    name             VARCHAR2(100) NOT NULL,
    password_hash    VARCHAR2(200) NOT NULL,
    role             VARCHAR2(50) NOT NULL, -- admin, finance_manager, finance_analyst
    ebs_role         VARCHAR2(50) NOT NULL, -- Super Admin, Finance Manager, Finance Analyst
    property_access  VARCHAR2(4000) NOT NULL, -- Comma separated property_ids, e.g. 'prop_novotel_paris,prop_ibis_london'
    org_id           VARCHAR2(50) NOT NULL,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. ACCOR VENDORS
CREATE TABLE ACCOR_VENDORS (
    vendor_id      VARCHAR2(50) PRIMARY KEY,
    name           VARCHAR2(100) NOT NULL,
    category       VARCHAR2(50),
    payment_terms  VARCHAR2(20)
);

-- 4. ACCOR CUSTOMERS
CREATE TABLE ACCOR_CUSTOMERS (
    customer_id   VARCHAR2(50) PRIMARY KEY,
    name          VARCHAR2(100) NOT NULL,
    segment       VARCHAR2(50),
    credit_limit  NUMBER(15,2)
);

-- 5. ACCOUNTS PAYABLE (AP) INVOICES
CREATE TABLE ACCOR_AP_INVOICES (
    invoice_id      VARCHAR2(50) PRIMARY KEY,
    invoice_number  VARCHAR2(50) UNIQUE NOT NULL,
    vendor_id       VARCHAR2(50) REFERENCES ACCOR_VENDORS(vendor_id),
    property_id     VARCHAR2(50) REFERENCES ACCOR_PROPERTIES(property_id),
    amount          NUMBER(15,2) NOT NULL,
    currency        VARCHAR2(10) NOT NULL,
    invoice_date    DATE NOT NULL,
    due_date        DATE NOT NULL,
    status          VARCHAR2(30) DEFAULT 'unpaid', -- unpaid, paid, pending_approval
    description     VARCHAR2(500),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 6. ACCOUNTS RECEIVABLE (AR) INVOICES
CREATE TABLE ACCOR_AR_INVOICES (
    invoice_id      VARCHAR2(50) PRIMARY KEY,
    invoice_number  VARCHAR2(50) UNIQUE NOT NULL,
    customer_id     VARCHAR2(50) REFERENCES ACCOR_CUSTOMERS(customer_id),
    property_id     VARCHAR2(50) REFERENCES ACCOR_PROPERTIES(property_id),
    amount          NUMBER(15,2) NOT NULL,
    currency        VARCHAR2(10) NOT NULL,
    invoice_date    DATE NOT NULL,
    due_date        DATE NOT NULL,
    status          VARCHAR2(30) DEFAULT 'unpaid', -- unpaid, paid
    description     VARCHAR2(500),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 7. GENERAL LEDGER (GL) CHART OF ACCOUNTS
CREATE TABLE ACCOR_GL_ACCOUNTS (
    account_id  VARCHAR2(50) PRIMARY KEY,
    code        VARCHAR2(20) UNIQUE NOT NULL,
    name        VARCHAR2(100) NOT NULL,
    type        VARCHAR2(20) CHECK (type IN ('ASSET', 'LIABILITY', 'EQUITY', 'INCOME', 'EXPENSE')),
    balance     NUMBER(15,2) DEFAULT 0.00,
    currency    VARCHAR2(10) NOT NULL
);

-- 8. JOURNAL ENTRIES
CREATE TABLE ACCOR_JOURNAL_ENTRIES (
    entry_id     VARCHAR2(50) PRIMARY KEY,
    entry_date   DATE NOT NULL,
    reference    VARCHAR2(50) NOT NULL,
    description  VARCHAR2(500),
    property_id  VARCHAR2(50) REFERENCES ACCOR_PROPERTIES(property_id),
    created_by   VARCHAR2(100) NOT NULL,
    status       VARCHAR2(30) DEFAULT 'pending_approval', -- pending_approval, posted
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 9. JOURNAL LINES
CREATE TABLE ACCOR_JOURNAL_LINES (
    line_id       VARCHAR2(50) PRIMARY KEY,
    entry_id      VARCHAR2(50) REFERENCES ACCOR_JOURNAL_ENTRIES(entry_id) ON DELETE CASCADE,
    account_code  VARCHAR2(20) REFERENCES ACCOR_GL_ACCOUNTS(code),
    debit         NUMBER(15,2) DEFAULT 0.00,
    credit        NUMBER(15,2) DEFAULT 0.00
);

-- 10. SYSTEM AUDIT & SECURITY LOGS
CREATE TABLE ACCOR_AUDIT_LOG (
    log_id       VARCHAR2(50) DEFAULT SYS_GUID() PRIMARY KEY,
    user_id      VARCHAR2(50),
    email        VARCHAR2(100) NOT NULL,
    action_type  VARCHAR2(50) NOT NULL, -- QUERY, DML_EXECUTION, SYSTEM, INJECTION_ATTEMPT
    query_text   VARCHAR2(4000),
    status       VARCHAR2(20) CHECK (status IN ('allowed', 'blocked')),
    reason       VARCHAR2(1000),
    timestamp    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 11. CHAT CONVERSATION HISTORY LOGS
CREATE TABLE ACCOR_CONVERSATIONS (
    conversation_id VARCHAR2(50) PRIMARY KEY,
    user_id         VARCHAR2(50) REFERENCES ACCOR_USERS(user_id),
    thread_id       VARCHAR2(100) NOT NULL,
    role            VARCHAR2(20) NOT NULL, -- user, bot
    message_content VARCHAR2(4000) NOT NULL,
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexing for performance
CREATE INDEX IDX_ACCOR_AP_PROP ON ACCOR_AP_INVOICES(property_id);
CREATE INDEX IDX_ACCOR_AR_PROP ON ACCOR_AR_INVOICES(property_id);
CREATE INDEX IDX_ACCOR_JE_PROP ON ACCOR_JOURNAL_ENTRIES(property_id);
CREATE INDEX IDX_ACCOR_AUDIT_EMAIL ON ACCOR_AUDIT_LOG(email);

-- Seed Data insertion
-- Properties
INSERT INTO ACCOR_PROPERTIES VALUES ('prop_novotel_paris', 'Novotel Paris Centre', 'Novotel', 'Paris', 'France', 'EUR', 'active');
INSERT INTO ACCOR_PROPERTIES VALUES ('prop_ibis_london', 'Ibis London City', 'Ibis', 'London', 'United Kingdom', 'GBP', 'active');
INSERT INTO ACCOR_PROPERTIES VALUES ('prop_sofitel_nyc', 'Sofitel New York', 'Sofitel', 'New York', 'USA', 'USD', 'active');
INSERT INTO ACCOR_PROPERTIES VALUES ('prop_pullman_tokyo', 'Pullman Tokyo Tamachi', 'Pullman', 'Tokyo', 'Japan', 'JPY', 'active');

-- Users (Seed passwords pre-hashed)
INSERT INTO ACCOR_USERS VALUES ('accor_usr_analyst', 'analyst@accor.com', 'Pierre Dubois', 'analyst123', 'finance_analyst', 'Finance Analyst', 'prop_novotel_paris,prop_ibis_london', 'ORG_EUR_01', SYSTIMESTAMP);
INSERT INTO ACCOR_USERS VALUES ('accor_usr_manager', 'manager@accor.com', 'Sophie Martin', 'manager123', 'finance_manager', 'Finance Manager', 'prop_novotel_paris,prop_ibis_london,prop_sofitel_nyc,prop_pullman_tokyo', 'ORG_GLOBAL', SYSTIMESTAMP);
INSERT INTO ACCOR_USERS VALUES ('accor_usr_admin', 'admin@accor.com', 'System Administrator', 'admin123', 'admin', 'Super Admin', 'prop_novotel_paris,prop_ibis_london,prop_sofitel_nyc,prop_pullman_tokyo', 'ORG_GLOBAL', SYSTIMESTAMP);

-- Vendors
INSERT INTO ACCOR_VENDORS VALUES ('vend_linen', 'Linen Care Services Ltd', 'Operations', 'NET30');
INSERT INTO ACCOR_VENDORS VALUES ('vend_fnb', 'Premium Foods & Beverage S.A.', 'F&B Supply', 'NET15');
INSERT INTO ACCOR_VENDORS VALUES ('vend_energy', 'Global Utilities & Energy Co', 'Utilities', 'DUE_ON_REC');
INSERT INTO ACCOR_VENDORS VALUES ('vend_security', 'SafeGuard Protection Group', 'Security Services', 'NET45');
INSERT INTO ACCOR_VENDORS VALUES ('vend_tech', 'Oracle EBS Consulting Partners', 'IT Support', 'NET30');

-- Customers
INSERT INTO ACCOR_CUSTOMERS VALUES ('cust_booking', 'Booking Holdings Inc.', 'OTA', 50000.00);
INSERT INTO ACCOR_CUSTOMERS VALUES ('cust_amex', 'American Express Global Business Travel', 'Corporate', 100000.00);
INSERT INTO ACCOR_CUSTOMERS VALUES ('cust_tui', 'TUI Group AG', 'Leisure Tour', 75000.00);
INSERT INTO ACCOR_CUSTOMERS VALUES ('cust_jtb', 'JTB Corp Japan', 'Regional Corporate', 40000.00);

-- AP Invoices
INSERT INTO ACCOR_AP_INVOICES VALUES ('ap_inv_1001', 'INV-LCS-091', 'vend_linen', 'prop_novotel_paris', 2500.00, 'EUR', SYSDATE-45, SYSDATE-15, 'unpaid', 'Laundry and bed linen rental service - April 2026', SYSTIMESTAMP);
INSERT INTO ACCOR_AP_INVOICES VALUES ('ap_inv_1002', 'INV-PFB-182', 'vend_fnb', 'prop_novotel_paris', 4800.00, 'EUR', SYSDATE-10, SYSDATE+5, 'unpaid', 'F&B kitchen dry supplies and beverages bulk load', SYSTIMESTAMP);
INSERT INTO ACCOR_AP_INVOICES VALUES ('ap_inv_1003', 'INV-GUE-901', 'vend_energy', 'prop_ibis_london', 1200.00, 'GBP', SYSDATE-95, SYSDATE-95, 'unpaid', 'Electricity usage invoice for Q1 2026', SYSTIMESTAMP);
INSERT INTO ACCOR_AP_INVOICES VALUES ('ap_inv_1004', 'INV-SGP-339', 'vend_security', 'prop_sofitel_nyc', 6200.00, 'USD', SYSDATE-12, SYSDATE+33, 'pending_approval', 'Security officer deployment - High season May 2026', SYSTIMESTAMP);
INSERT INTO ACCOR_AP_INVOICES VALUES ('ap_inv_1005', 'INV-OEC-772', 'vend_tech', 'prop_pullman_tokyo', 350000.00, 'JPY', SYSDATE-5, SYSDATE+25, 'paid', 'Oracle EBS functional consultants onboarding fee', SYSTIMESTAMP);

-- AR Invoices
INSERT INTO ACCOR_AR_INVOICES VALUES ('ar_inv_2001', 'AR-BHI-401', 'cust_booking', 'prop_novotel_paris', 12500.00, 'EUR', SYSDATE-20, SYSDATE+10, 'unpaid', 'OTA room sales commissions and reconciliation', SYSTIMESTAMP);
INSERT INTO ACCOR_AR_INVOICES VALUES ('ar_inv_2002', 'AR-AMX-222', 'cust_amex', 'prop_sofitel_nyc', 18200.00, 'USD', SYSDATE-40, SYSDATE-10, 'unpaid', 'Corporate client stays - Q1 group booking rate', SYSTIMESTAMP);
INSERT INTO ACCOR_AR_INVOICES VALUES ('ar_inv_2003', 'AR-TUI-094', 'cust_tui', 'prop_ibis_london', 7800.00, 'GBP', SYSDATE-2, SYSDATE+28, 'unpaid', 'Tour operator allotments package sales', SYSTIMESTAMP);

-- GL Accounts
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

-- Journal Entries
INSERT INTO ACCOR_JOURNAL_ENTRIES VALUES ('accor_je_001', SYSDATE-15, 'JE-2026-004', 'Monthly depreciation of property fixtures', 'prop_novotel_paris', 'Sophie Martin', 'posted', SYSTIMESTAMP);
INSERT INTO ACCOR_JOURNAL_ENTRIES VALUES ('accor_je_002', SYSDATE-2, 'JE-2026-009', 'Intercompany transfer Novotel Paris -> Sofitel New York', 'prop_novotel_paris', 'Sophie Martin', 'pending_approval', SYSTIMESTAMP);

-- Journal Lines
INSERT INTO ACCOR_JOURNAL_LINES VALUES ('je_line_101', 'accor_je_001', '5000', 1500.00, 0.00);
INSERT INTO ACCOR_JOURNAL_LINES VALUES ('je_line_102', 'accor_je_001', '1300', 0.00, 1500.00);
INSERT INTO ACCOR_JOURNAL_LINES VALUES ('je_line_103', 'accor_je_002', '1010', 0.00, 5000.00);
INSERT INTO ACCOR_JOURNAL_LINES VALUES ('je_line_104', 'accor_je_002', '1200', 5000.00, 0.00);

-- Initial Audit Log
INSERT INTO ACCOR_AUDIT_LOG (user_id, email, action_type, query_text, status, reason, timestamp)
VALUES ('accor_usr_admin', 'admin@accor.com', 'SYSTEM', 'Initialize ACCOR EBS Finance Database Seeding', 'allowed', 'System startup initialization successfully seeded', SYSTIMESTAMP);

COMMIT;
