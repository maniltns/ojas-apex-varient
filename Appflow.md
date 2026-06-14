# App Flow & User Journeys — ACCOR EBS Conversational Bot

> **RFP alignment note.** This document refers to **ACCOR Grandback** (the client's Oracle EBS 12.2.12
> landscape). Code identifiers use the `GRANDBACK_*` prefix. The solution is delivered in three RFP
> phases — Phase 1 (API-first / dynamic analytics, 80 use cases), Phase 2 (Knowledge & Context /
> Vector Search, 30), Phase 3 (Agentic AI, 12). This POC builds a representative **Phase 1** subset.
> Canonical references: [POC_IMPLEMENTATION_PLAN.md](POC_IMPLEMENTATION_PLAN.md) ·
> [RFP_TRACEABILITY.md](RFP_TRACEABILITY.md).

This document outlines the user interaction paths and sequence diagrams for the APEX application.

---

## 1. Authentication & Role Context Loading

```mermaid
sequenceDiagram
    autonumber
    actor User as Corporate User
    participant Login as APEX Login Page (Page 9999)
    participant Auth as APEX Authentication Engine
    participant DB as Autonomous Database (GRANDBACK_USERS)
    participant Chat as Chat Workspace (Page 2)

    User->>Login: Enter credentials (email, password)
    Login->>Auth: Invoke APEX_AUTHENTICATION.LOGIN
    Auth->>DB: Query user records & verify password
    DB-->>Auth: Matching account profile
    Auth-->>Login: Create session cookie
    Login->>Chat: Redirect to Page 2 (CHAT)
    Chat->>DB: Resolve email and load properties in selector
    DB-->>Chat: Return list of properties
    Chat-->>User: Display Chat Workspace (scoped to active property)
```

---

## 2. Interactive Conversational Chat Loop

```mermaid
sequenceDiagram
    autonumber
    actor User as Finance User
    participant Page as APEX Page 2 Interface
    participant DB as Autonomous Database (PL/SQL Layer)
    participant Bot as GRANDBACK_BOT_PKG

    User->>Page: Select Property Scope (e.g. Novotel Paris)
    User->>Page: Type message & click "Send"
    Page->>DB: Execute afterSubmit process (process-user-chat)
    DB->>Bot: Call process_chat_message(email, role, message, property_id, thread_id)
    Note over Bot: Run guardrail checks & evaluate security boundaries
    Bot->>DB: Insert message in GRANDBACK_CONVERSATIONS
    Bot-->>Page: Return JSON payload (reply, requires_approval, intent)
    Page->>Page: Reload Dynamic Content area
    Page-->>User: Render markdown table & message feed
```

---

## 3. Gated Transaction Write Workflow (Managers Only)

For write-based actions (such as paying or approving invoices), the bot enforces a confirmation gate before altering table states:

```mermaid
sequenceDiagram
    autonumber
    actor Mgr as Finance Manager
    participant Page as APEX Page 2 Interface
    participant Bot as GRANDBACK_BOT_PKG
    participant DB as Autonomous Database

    Mgr->>Page: Type "Approve payment for ap_inv_1001"
    Page->>Bot: Call process_chat_message
    Note over Bot: Validate that role is Manager & property is in scope
    Bot-->>Page: Return JSON (requires_approval = true, payload = invoice details)
    Page->>Page: Show modal confirmation dialog
    Mgr->>Page: Click "Confirm Payment" (Sends CONFIRM message)
    Page->>Bot: Call process_chat_message with prompt "CONFIRM"
    Bot->>DB: UPDATE GRANDBACK_AP_INVOICES SET status = 'paid' WHERE id = 'ap_inv_1001'
    DB-->>Bot: Row modified successfully
    Bot-->>Page: Return JSON (Success message)
    Page-->>Mgr: Display "Payment Approved Successfully" alert card
```

---

## 4. Admin Threat & Governance Auditing

```mermaid
sequenceDiagram
    autonumber
    actor Admin as System Admin
    participant App as APEX Navigation Bar
    participant AdminPage as Governance Panel (Page 3)
    participant DB as Autonomous Database

    Admin->>App: Click "Admin Governance" link
    Note over App: Check serverSideCondition (administration-rights authorization)
    App->>AdminPage: Open Page 3
    AdminPage->>DB: Run SELECT queries on GRANDBACK_USERS & GRANDBACK_AUDIT_LOG
    DB-->>AdminPage: Return result sets
    AdminPage-->>Admin: Display Users Grid, Audit Logs, and Blocked Threat Alerts
```
