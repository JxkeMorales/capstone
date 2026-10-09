# SmartBand — Municipal Band Operations & Gig Dispatch System

[![Vue 3](https://img.shields.io/badge/Vue-3.5-4FC08D?logo=vue.js&logoColor=white)](https://vuejs.org/)
[![Vite](https://img.shields.io/badge/Vite-8.1-646CFF?logo=vite&logoColor=white)](https://vitejs.dev/)
[![Tailwind CSS](https://img.shields.io/badge/TailwindCSS-4.3-38B2AC?logo=tailwind-css&logoColor=white)](https://tailwindcss.com/)
[![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com/)
[![PWA](https://img.shields.io/badge/PWA-Workbox-5A0FC8?logo=pwa&logoColor=white)](https://web.dev/progressive-web-apps/)
[![WCAG 2.1 AA](https://img.shields.io/badge/WCAG-2.1_AA-0284C7)](https://www.w3.org/WAI/WCAG21/quickref/)

**SmartBand** is an enterprise-grade Progressive Web Application (PWA) designed for municipal marching bands, civic ensembles, and community orchestras. Developed for the historic **Banda 1870 of Peñaranda, Nueva Ecija, Philippines**, it replaces fragile manual group chats and paper attendance logbooks with an automated, real-time gig management, call-time dispatch, and member accountability platform.

---

## 🎵 Key Features

* **Real-Time Attendance Roll Call:** Conduct live roll calls during rehearsals and civic parades with instant status classification (`Present`, `Absent`, `Excused`).
* **Automated Reliability Scoring:** 100% baseline reliability score that objectively tracks member dependability and applies a -10% flake penalty for unexcused no-shows.
* **7-Day Recurring Availability Matrix:** Musician profile availability partitioned by time slots (`Morning`, `Afternoon`, `Evening`) enabling instant section lineup queries (`Woodwinds`, `Brass`, `Percussion`, `Auxiliary`).
* **VAPID Web Push Notifications:** Zero-cost browser-native call-time alarms dispatched 2 hours and 30 minutes before parade assembly.
* **Official Municipal PDF Reports:** Client-side vector report generation with official band letterhead, municipal signatory blocks, and attendance matrices for local government budget audits.
* **Outdoor Ergonomics & Accessibility:** Strict WCAG 2.1 Level AA compliance, 48px touch targets, zero GPU-straining backdrop blur, and system typography for maximum mobile battery efficiency.

---

## 🛠️ Technology Architecture

* **Frontend:** Vue 3 (Composition API, `<script setup>`)
* **State Management:** Pinia (modular user and UI stores)
* **Routing:** Vue Router (with route-level code splitting & accessible title synchronization)
* **Styling & Design System:** Tailwind CSS v4 + Material 3 Design Tokens
* **Database & Backend:** Supabase PostgreSQL with strict Row-Level Security (RLS)
* **Realtime Sync:** Supabase Realtime WebSocket broadcast channels
* **Service Worker:** Vite PWA + Workbox offline caching + VAPID Web Push
* **Reporting:** Dynamic lazy-loaded jsPDF & `@media print` print stylesheets

---

## 👥 Role Hierarchy & Permissions

| Role | Access Level & Responsibilities |
| :--- | :--- |
| **Super Admin** | IT Administration, user account approvals, executive role promotions, master database operations, and municipal PDF exports. |
| **Secretary Admin** | Gig & rehearsal creation, live attendance roll call, availability checking, and instant attendance reminders. |
| **Executive** | High-level turnout metrics, section reliability matrix, and roster performance analytics. |
| **Musician** | Gig RSVP (`Attending` / `Not Attending`), excuse justifications, 7-day recurring availability matrix, and personal schedule tracking. |

---

## 🚀 Getting Started

### Prerequisites
* Node.js 18+ or 20+
* NPM 9+
* Supabase Account & CLI (optional for local emulation)

### Installation
```bash
# Clone the repository
git clone https://github.com/JxkeMorales/capstone.git
cd smartband

# Install dependencies
npm install
```

### Environment Configuration
Create a `.env` file in the root directory:
```env
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
VITE_VAPID_PUBLIC_KEY=your-vapid-public-key
```

### Development Server
```bash
npm run dev
```

### Production Build
```bash
npm run build
npm run preview
```

---

## 🔒 Security & Database Migration

SmartBand enforces security **at the database layer** via PostgreSQL Row-Level Security (RLS) policies:
* Consolidated baseline migration: `supabase/migrations/20261009000000_baseline_schema.sql`
* Privilege-escalation guards: `BEFORE UPDATE` trigger on `profiles` preventing unauthorized role or verification changes.
* Column-allowlisted public views: `public_roster` prevents unauthenticated PII leakage.
* Storage ownership: Avatars bucket enforces `(storage.foldername(name))[1] = auth.uid()::text`.

---

## 📚 Thesis & Defense Documentation

For thesis panel presentation preparation, refer to:
* **Defense Cheatsheet:** [`docs/DEFENSE_CHEATSHEET.md`](docs/DEFENSE_CHEATSHEET.md) — Answers to the top 10 anticipated panel questions with file references.
* **Compliance Audit:** [`STANDARDS_COMPLIANCE_AUDIT.md`](STANDARDS_COMPLIANCE_AUDIT.md) — WCAG 2.1 AA and ISO/IEC 25010 verification.
* **Design System Audit:** [`DESIGN_SYSTEM_AUDIT.md`](DESIGN_SYSTEM_AUDIT.md) — Material 3 token audit and remediation trail.

---

## 📜 License
Developed for academic capstone defense and deployment with **Banda 1870 (Peñaranda, Nueva Ecija)**. All rights reserved.
