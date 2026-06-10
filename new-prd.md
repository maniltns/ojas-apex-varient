

# ACCOR EBS Finance Conversational Bot — POC

## 1. Overview
A secure, context-aware conversational chatbot for ACCOR's Corporate Finance team that interfaces with Oracle EBS Finance modules (AP, AR, GL, inter-company transactions) via a mock OCI environment. The bot enforces role-based access inherited from Oracle SSO, maintains multi-turn conversation context, and performs guided CRUD operations on financial data — all while adhering to enterprise-grade security guardrails against prompt injection, SQL injection, and unauthorized access. The POC is hosted on Oracle APEX with OCI Autonomous Database simulating EBS schemas.

## 2. User Stories
- As a **finance analyst**, I want to query AP/AR balances and invoice statuses conversationally so I can get answers without navigating complex EBS screens.
- As a **finance manager**, I want to approve or reject journal entries and vendor payments through guided chat workflows so I can act on tasks quickly.
- As a **corporate controller**, I want to view multi-property consolidated financial summaries so I can monitor ACCOR's portfolio health (Ibis, Novotel, Sofitel properties).
- As an **administrator**, I want to manage user roles, view conversation audit logs, and monitor security events so I can ensure compliance and governance.
- As any **authenticated user**, I want my permissions enforced automatically so I only see and modify data my EBS role permits.

## 3.a. Agent Architecture

**Pattern:** Manager-Subagent + Independent Agent (Hybrid)

**Reasoning:** A single user query may require security validation, intent classification, SQL generation against EBS schemas, and response formatting — all in one shot. The security validation agent must intercept every request before any data operation. An independent Audit & Context Agent handles persistent session/context management separately since it operates across the lifecycle, not per-query.

**Agent Flow:**
User sends a message via the APEX chat UI → the **EBS Finance Orchestrator (Manager)** receives the query. It first routes to the **Security & Guardrail Agent** which validates input for prompt injection, SQL injection, and checks the user's EBS role/permissions context. If cleared, the Manager routes to the **Finance Query Agent** for read operations (GL lookups, AP/AR balance queries, invoice status) or to the **Finance Action Agent** for write operations (create journal entries, approve payments, update vendor records). The Manager aggregates sub-agent outputs into a formatted, permission-filtered response. Separately, the **Conversation Context Agent** (Independent) is triggered on each session to persist conversation history, user preferences, and maintain multi-turn context. For CRUD write operations, the Finance Action Agent enforces a confirmation step before execution.

**Data Sources Detected:** 2 — OCI Autonomous Database (mock EBS Finance schemas), User/Session MongoDB store

**Agents Table:**

| Agent Type | Agent Name | Description | Tools/Data Sources | Trigger | Provider | Model | Temperature | Top_p |
|------------|------------|-------------|-------------------|---------|----------|-------|-------------|-------|
| Manager | EBS Finance Orchestrator | Coordinates all sub-agents — classifies user intent (read vs. write), routes to security validation first, then to appropriate finance agent, aggregates and formats final response with permission filtering | N/A | \"Send\" button on Chat Interface | OpenAI | gpt-5.1 | 0.2 | 1 |
| Sub-Agent | Security & Guardrail Agent | Validates every input for prompt injection patterns, SQL injection attempts, and verifies user's EBS role permissions against requested operation. Blocks unauthorized queries with clear denial messages. Enforces least-privilege principle | Custom Tool (OCI IAM Role Validator API) | Auto (via Manager) | Anthropic | claude-sonnet-4-6 | 0.1 | 1 |
| Sub-Agent | Finance Query Agent | Generates parameterized read-only SQL queries against EBS Finance schemas (GL, AP, AR, inter-company) — retrieves balances, invoice statuses, journal entries, multi-property consolidations. Returns structured data filtered by user's property/org access | Custom Tool (APEX REST API — EBS Mock DB) | Auto (via Manager) | Anthropic | claude-sonnet-4-6 | 0.2 | 1 |
| Sub-Agent | Finance Action Agent | Handles CRUD write operations — creates journal entries, updates vendor payment statuses, modifies invoice records. Enforces mandatory confirmation workflow before execution. Generates parameterized DML statements only | Custom Tool (APEX REST API — EBS Mock DB) | Auto (via Manager) | Anthropic | claude-sonnet-4-6 | 0.1 | 1 |
| Independent | Conversation Context Agent | Manages multi-turn conversation state, stores user preferences, tracks conversation thread context for coherent follow-ups. Retrieves prior context at session start for continuity | N/A | Auto on session init and per-message context refresh | Anthropic | claude-sonnet-4-6 | 0.3 | 1 |

**Workflow Visualization:**

The Input Node is positioned at the far left. The EBS Finance Orchestrator (Manager) connects to the right of the Input Node. Directly below the Manager, three sub-agents (Security & Guardrail Agent, Finance Query Agent, Finance Action Agent) are positioned in a horizontal row at the same vertical level, evenly spaced. The Manager connects downward to all three sub-agents. To the right of the Input Node at a separate horizontal position, the Conversation Context Agent sits as an independent node with its own right-connection from the Input Node.

**Connection Summary:**
- Input → EBS Finance Orchestrator: Right
- Input → Conversation Context Agent: Right (parallel independent path)
- EBS Finance Orchestrator → Security & Guardrail Agent: Bottom
- EBS Finance Orchestrator → Finance Query Agent: Bottom
- EBS Finance Orchestrator → Finance Action Agent: Bottom

## 3.g. Database Configuration

**Database:** MongoDB / Autonomous DB
**User Management:** Required — Oracle SSO simulated via email/password with EBS role mapping.

| Collection / Entity | Purpose | Key Fields |
|---------------------|---------|------------|
| users | User accounts with EBS role mappings and property access | id, email, password_hash, role, ebs_role, property_access[], org_id, created_at |
| conversations | Multi-turn conversation threads with full history | id, user_id, messages[], started_at, last_activity, status |
| user_preferences | Saved query preferences and default views per user | id, user_id, default_property, preferred_reports[], language |
| audit_log | Security audit trail — all queries, actions, blocked attempts | id, user_id, action_type, query_text, status (allowed/blocked), reason, timestamp |

**Roles:**

| Role | Access Level |
|------|-------------|
| admin | Full access — manage users, view all audit logs, configure guardrails, access all properties |
| finance_manager | Approve/reject transactions, view multi-property data within assigned org, execute write operations |
| finance_analyst | Read-only queries on assigned property financial data, no write operations |

**Authentication Flow:**
Sign Up → user provides name, email, password, assigned EBS role and property access → stored in MongoDB users collection. Log In → email + password authenticated → session loads user's EBS role context, property permissions, and prior conversation thread. All screens are gated behind authentication.

## 4. User Flow

1. User lands on ACCOR EBS Finance Bot — app visible but blurred with auth modal overlay (Sign Up as default).
2. New user → clicks \"Sign Up\" → fills Name, Email, Password, selects EBS Role (analyst/manager) and Property Assignment → account created → redirected to chat.
3. Returning user → enters email + password → authenticated → Conversation Context Agent loads prior session context and preferences → enters chat interface.
4. User types a financial query (e.g., \"Show AP aging for Novotel Paris\") → Manager receives → routes to Security Agent for validation → if cleared, routes to Finance Query Agent → parameterized query generated and executed via APEX REST API → results returned to Manager → formatted response displayed.
5. User requests a write action (e.g., \"Create a journal entry for inter-company transfer\") → Manager routes to Security Agent → permission verified (must be finance_manager) → Finance Action Agent initiates guided workflow → collects required fields step-by-step → shows confirmation summary → user confirms → action executed → audit logged.
6. If Security Agent detects prompt injection, SQL injection, or unauthorized access → blocks immediately → returns clear denial message → logs incident in audit_log.
7. Admin user → accesses Admin Panel → views audit logs, manages user roles, monitors blocked security events.

## 5. Integrations Required

No out-of-the-box integrations required for this app.

> **Manual Setup Required:** This app requires connection to **OCI Autonomous Database** (mock EBS Finance schemas) and **OCI IAM** (role validation) via APEX REST APIs, which are not available as pre-built integrations on Lyzr Studio. You will need to configure these as **Custom Tools** (OpenAPI spec pointing to your APEX REST endpoints) in Lyzr Studio after deployment. Specifically:
> 1. **APEX REST API — EBS Mock DB:** Custom OpenAPI spec for parameterized SQL execution against GL, AP, AR tables (used by Finance Query Agent and Finance Action Agent)
> 2. **OCI IAM Role Validator API:** Custom OpenAPI spec for validating user EBS roles and property permissions (used by Security & Guardrail Agent)
>
> This does not block the 'Push to Agents' flow — add these custom tools post-deployment.

## 6. UI/UX Specification

[SELECTED_THEME: luxury-dark]

### App Structure
Full-width layout with a persistent left sidebar for navigation (Chat, Conversation History, Admin Panel for admin role), a top header bar showing ACCOR branding, logged-in user identity, EBS role badge, and active property context. Main content area is a professional chat interface optimized for financial data display.

### Design System
**Components:** Chat message bubbles (user/bot differentiated), financial data tables within chat, confirmation modals for CRUD actions, role badges, property selector dropdown, security alert banners, audit log table with filters.
**Visual Hierarchy:** Large chat area with clear message threading, compact data tables with alternating row shading, prominent confirmation dialogs with clear approve/cancel actions, security warnings in high-visibility styling.
**Information Density:** Chat messages are spacious for readability; embedded financial tables are compact and scannable; sidebar is minimal with icon + label navigation.

### Screens/Pages/Sections

#### Screen 0: Login
**Purpose:** Authenticates returning users.
**Layout:** Centered card form over blurred app background.
**Components:** Email input, Password input, \"Log In\" button, \"Don't have an account? Sign Up\" link, error states for invalid credentials, ACCOR logo above form.

#### Screen 0b: Sign Up
**Purpose:** Creates new accounts with EBS role assignment.
**Layout:** Centered card form.
**Components:** Name, Email, Password fields, EBS Role dropdown (Finance Analyst / Finance Manager), Property Assignment multi-select (Novotel, Ibis, Sofitel, Pullman, etc.), \"Create Account\" button, validation states.

#### Screen 1: Chat Interface (Main)
**Purpose:** Primary conversational interface for all financial queries and actions.
**Layout:** Full-height chat area with message thread, input bar pinned at bottom, property context selector in header.
**Components:**
- **Message Thread:** User/bot messages with timestamps, role-aware responses, embedded financial data tables (sortable columns for amounts, dates, statuses), step-by-step guided workflow cards for CRUD operations.
- **Confirmation Modal:** Triggered for write operations — shows operation summary, affected records, \"Confirm\" / \"Cancel\" buttons.
- **Security Alert Banner:** Appears inline when a query is blocked — shows reason and suggested alternative.
- **Input Bar:** Text input with \"Send\" CTA, suggested quick actions (e.g., \"AP Aging\", \"GL Balance\", \"Create Journal Entry\").
- **Property Context:** Dropdown in header to switch active property — filters all subsequent queries.

#### Screen 2: Conversation History
**Purpose:** Browse and resume past conversation threads.
**Layout:** Left list of conversation threads (date, preview) + right panel showing selected thread.
**Components:** Searchable thread list, date filters, thread preview cards, \"Resume Conversation\" action to continue context.

#### Screen 3: Admin Panel (Admin role only)
**Purpose:** User management, audit logs, security monitoring.
**Layout:** Tabbed layout — Users tab, Audit Log tab, Security Events tab.
**Components:**
- **Users Tab:** Table of all users (name, email, role, property access, status), edit/deactivate actions.
- **Audit Log Tab:** Filterable table (user, action type, status, timestamp), export capability.
- **Security Events Tab:** Blocked queries, injection attempts, unauthorized access attempts with details.

### Complete User Journey
User opens app → sees blurred chat interface with Sign Up modal → creates account with Finance Analyst role for Novotel properties → enters chat → types \"What's the AP aging summary for Novotel Paris?\" → Security validates, Query Agent executes → sees formatted aging table in chat → follows up \"Show invoices over 90 days\" (multi-turn context maintained) → sees filtered results → Manager user types \"Approve payment for invoice INV-2024-0891\" → Security validates manager permission → Finance Action Agent shows confirmation card with payment details → user clicks \"Confirm\" → payment processed, audit logged → user navigates to Conversation History to review prior sessions → Admin