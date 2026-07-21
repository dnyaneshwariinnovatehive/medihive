# Database Mismatch Audit & `database.py` Alignment Plan

> **Single Source of Truth Database:** `d:\MediHive-Flutter\backend\medihive.db` (and `C:\Users\dnyan\Downloads\clinic (1).db`)  
> **Target File for Alignment:** [database.py](file:///d:/MediHive-Flutter/backend/database.py)  
> **Audit Date:** 2026-07-21  

---

## 1. Why `database.py` is Used in the Project

The project operates in a **Hybrid Architecture** (Flutter Local Client + Cloud/Local Python Flask API):

1. **Role of `medihive.db` (Local SQLite Database):**
   - `medihive.db` is the **offline local database** embedded directly into the desktop/mobile application.
   - It stores patient records, OPD visits, settings, and queue items directly on the client machine.
   - You have confirmed that `medihive.db` is **100% identical** to the Single Source of Truth (`clinic.db`).

2. **Role of `database.py` (Backend Database Connector & Auto-Migration Service):**
   - `database.py` is the core database abstraction layer for the **Python Flask REST API backend server** (configured to connect to PostgreSQL / Neon DB in production or local environments).
   - Whenever an API endpoint calls `get_db()`, `database.py` triggers `_init_db()` to automatically initialize table schemas, run migrations, and seed default admin credentials on the server side.

3. **Why Schema Alignment is Critical:**
   - If `database.py` contains extra columns (like `panchakarma_notes` or `updated_at`), missing columns, or mismatched data types (such as `TEXT` instead of `INTEGER` for IDs, or `TEXT` instead of `FLOAT` for fee amounts), API requests (e.g. Patient creation, OPD logging, Data Sync) will **fail with database syntax/type mismatch errors** or create corrupt records when syncing with `medihive.db`.

---

## 2. Master Comparison Table: What Needs to be Changed in `database.py`

Below is the complete inventory of all mismatches in [database.py](file:///d:/MediHive-Flutter/backend/database.py) and the exact actions required to bring it into **100% strict match** with `medihive.db`:

| Table Name | Column / Object | Current State in `database.py` | Source of Truth (`medihive.db`) | Required Action in `database.py` | Line Numbers in `database.py` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`patients`** | `id` | `TEXT PRIMARY KEY` | `INTEGER PRIMARY KEY AUTOINCREMENT` | Change type to `INTEGER PRIMARY KEY` (or `SERIAL PRIMARY KEY`) | L162 |
| **`patients`** | `updated_at` | `TIMESTAMP` (added via migration) | **DOES NOT EXIST** | Remove `updated_at` column creation and migration block | L521–L529 |
| **`opd_visits`** | `id` | `TEXT PRIMARY KEY` | `INTEGER PRIMARY KEY AUTOINCREMENT` | Change type to `INTEGER PRIMARY KEY` (or `SERIAL PRIMARY KEY`) | L205 |
| **`opd_visits`** | `patient_id` | `TEXT NOT NULL` | `INTEGER NOT NULL` | Change type from `TEXT` to `INTEGER` | L206 |
| **`opd_visits`** | `opd_id` | `TEXT` | `VARCHAR NOT NULL` | Add `NOT NULL` constraint | L207 |
| **`opd_visits`** | `visit_datetime` | `TEXT NOT NULL` | `DATETIME NOT NULL` | Change type to `DATETIME` / `TIMESTAMP NOT NULL` | L212 |
| **`opd_visits`** | `consultation_fee` | `TEXT DEFAULT '0'` | `FLOAT` | Change data type from `TEXT` to `FLOAT` / `DOUBLE PRECISION` | L214 |
| **`opd_visits`** | `medicine_fee` | `TEXT DEFAULT '0'` | `FLOAT` | Change data type from `TEXT` to `FLOAT` / `DOUBLE PRECISION` | L215 |
| **`opd_visits`** | `panchakarma_fee` | `TEXT DEFAULT '0'` | `FLOAT` | Change data type from `TEXT` to `FLOAT` / `DOUBLE PRECISION` | L216, L296–L302 |
| **`opd_visits`** | `total_fee` | `TEXT DEFAULT '0'` | `FLOAT` | Change data type from `TEXT` to `FLOAT` / `DOUBLE PRECISION` | L217, L304–L310 |
| **`opd_visits`** | `discount_value` | `TEXT DEFAULT '0'` | `FLOAT` | Change data type from `TEXT` to `FLOAT` / `DOUBLE PRECISION` | L218, L271–L277 |
| **`opd_visits`** | `panchakarma_notes`| `TEXT DEFAULT ''` | **DOES NOT EXIST** | **Remove `panchakarma_notes` column** from CREATE statement & migration block | L224, L288–L294 |
| **`opd_visits`** | `updated_at` | `TIMESTAMP` (added via migration) | **DOES NOT EXIST** | **Remove `updated_at` column** migration block | L531–L539 |
| **`patient_images`**| `patient_id` | `TEXT NOT NULL REFERENCES patients(id) ON DELETE CASCADE` | `INTEGER NOT NULL REFERENCES patients(id)` | Change type to `INTEGER`, remove `ON DELETE CASCADE` | L496 |
| **`patient_images`**| `opd_visit_id` | `TEXT REFERENCES opd_visits(id) ON DELETE SET NULL` | `INTEGER NOT NULL REFERENCES opd_visits(id)` | Change type to `INTEGER NOT NULL`, remove `ON DELETE SET NULL` | L497 |
| **`sync_queue`** | `status` | `VARCHAR(20) DEFAULT 'PENDING'` | `VARCHAR(20)` (Default `NULL`) | Remove `DEFAULT 'PENDING'` clause | L447 |
| **`Indexes`** | Primary Key Indexes | Not explicitly named in `database.py` | `ix_patients_id`, `ix_opd_visits_id`, `ix_opd_visits_opd_id` (UNIQUE), `ix_patient_images_id`, `ix_sync_queue_id`, `ix_users_id`, `ix_clinic_settings_id` | Add explicit index creation statements to match `medihive.db` index naming conventions | L321–L327 |
| **`Indexes`** | Custom Indexes | `idx_opd_patient`, `idx_opd_visit`, `idx_patient_images_patient`, `idx_patient_images_opd` | **DO NOT EXIST** in source DB | Remove extra index statements or adjust to match `medihive.db` | L476–L488, L507–L519 |

---

## 3. Step-by-Step Code Modification Plan for `database.py`

### Step 1: Fix `patients` Table Creation (`_init_db`)
- **Location:** Lines 161–173
- **Action:** Change `id` from `TEXT PRIMARY KEY` to `INTEGER PRIMARY KEY` (or `SERIAL PRIMARY KEY`).
- **Action:** Remove migration block for `updated_at` (Lines 521–529).

### Step 2: Fix `opd_visits` Table Creation & Migrations (`_init_db`)
- **Location:** Lines 204–226 & Lines 288–319
- **Action:**
  1. Change `id` to `INTEGER PRIMARY KEY`.
  2. Change `patient_id` to `INTEGER NOT NULL`.
  3. Change `opd_id` to `VARCHAR NOT NULL`.
  4. Change fee columns (`consultation_fee`, `medicine_fee`, `panchakarma_fee`, `total_fee`, `discount_value`) from `TEXT` to `FLOAT`.
  5. **Remove `panchakarma_notes`** from CREATE statement (L224) and migration block (L288–L294).
  6. **Remove `updated_at`** migration block (L531–L539).

### Step 3: Fix `patient_images` Foreign Keys (`_init_db`)
- **Location:** Lines 494–505
- **Action:** Change `patient_id` and `opd_visit_id` to `INTEGER NOT NULL`, and remove `ON DELETE CASCADE` / `ON DELETE SET NULL`.

### Step 4: Fix `sync_queue` Default Status (`_init_db`)
- **Location:** Lines 443–453
- **Action:** Remove `DEFAULT 'PENDING'` from `status VARCHAR(20)`.

### Step 5: Align Index Definitions (`_init_db`)
- **Location:** Lines 476–519
- **Action:** Create `ix_patients_id`, `ix_opd_visits_id`, `ix_opd_visits_opd_id`, `ix_patient_images_id`, `ix_sync_queue_id`, `ix_users_id`, `ix_clinic_settings_id` to mirror `medihive.db`.
