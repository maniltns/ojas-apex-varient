# UI/UX Design Specification — ACCOR EBS Conversational Bot

This document defines the interface standards, component specifications, and user experience patterns for the ACCOR EBS Conversational Bot application built on Oracle APEX.

---

## 1. Visual Theme & Style Guidelines

To convey enterprise-grade reliability and match ACCOR's corporate profile, the application follows a **clean, light, professional corporate theme** utilizing the **Oracle APEX Universal Theme** layout tokens.

### 1.1 Color Palette
* **Canvas Background:** Light Neutral Gray (`#fcfcfd`)
* **Card & Container Background:** Pure White (`#ffffff`)
* **Primary Brand/Accent Color:** ACCOR Deep Navy (`#0b162c`)
* **Secondary Color / Highlights:** Brushed Gold / Champagne (`#d4af37` or `#c5a059`)
* **Sidebar & Navigation Background:** Slate Gray (`#f2f4f7`)
* **Text Colors:**
  * Primary Body Text: Deep Charcoal (`#1d2939`)
  * Secondary / Muted Text: Slate Slate (`#475467`)
* **Alerts & Status States:**
  * *Allowed / Safe / Confirmed:* Green (`#03543f` on background `#def7ec`)
  * *Blocked / Threat Detected / Action Denied:* Deep Red (`#9b1c1c` on background `#fde8e8`)
  * *Pending Action / Confirmation Required:* Amber Gold (`#723b10` on background `#fef08a`)

### 1.2 Typography
The application uses standard sans-serif typographies loaded dynamically through Google Fonts (`Inter` or `Segoe UI`) to ensure high contrast, readability, and compatibility across corporate devices.

---

## 2. Page Layouts

### 2.1 Workspace Header Context (Global Page 0)
* Displays corporate branding (ACCOR Logo + "EBS Finance Orchestrator" title).
* Displays a **Property Selector** drop-down allowing users to switch property context (Novotel Paris Centre, Ibis London City, etc.) dynamically.
* Displays user email and their active EBS Role Badge (e.g. `Finance Analyst` or `Finance Manager`) as a clean pill indicator in the header bar.

### 2.2 Page 2: Chat Workspace
* **Layout:** A two-column structure:
  * **Main Column (Chat Workspace):**
    * *Chat History Feed:* A PL/SQL dynamic content region that renders the message stream. 
      * User bubbles align right, using a light gold tint border (`rgba(212, 175, 55, 0.1)`).
      * Bot bubbles align left, using a slate-bordered canvas with alternating table styling.
      * Tables printed by the bot are rendered in clean HTML tables with subtle border grid lines.
    * *Message Input Area:* A simple full-width text field (`P2_USER_MESSAGE`) and a primary "Send" button.
  * **Sidebar / Quick Actions:**
    * Buttons linking to suggested quick queries (e.g. *"Check AP Aging"*, *"Show GL Balance"*) for fast, mouse-driven testing.

### 2.3 Page 3: Admin Governance Panel
* Gated by the `Administration Rights` authorization scheme.
* Tabbed navigation region grouping:
  * **Tab 1: Users Directory:** An Interactive Report on `ACCOR_USERS`.
  * **Tab 2: Audit Logs:** An Interactive Report on the general system access logs (`ACCOR_AUDIT_LOG`).
  * **Tab 3: Security Threats Console:** A dedicated grid showing only entries in the log where `status = 'blocked'`. Payloads that triggered injection guardrails are displayed in high-visibility alert rows.
