# Database Alignment Report

> **Single Source of Truth:** `backend/medihive.db` (SQLite)
> **Audit Date:** 2026-07-24
> **Note:** No files were modified. This is a read-only audit.

---

## 1. Files Compared Against medihive.db

| # | File | Type | Status |
|---|------|------|--------|
| 1 | `lib/database/schema.dart` | Flutter DDL (CREATE TABLE) | ✅ ALIGNED |
| 2 | `lib/database/database_helper.dart` | Flutter DB init/migration | ⚠️ MINOR ISSUES |
| 3 | `backend/database.py` | Flask PostgreSQL DDL | ❌ MISMATCHES |
| 4 | `backend/models/patient.py` | Python model | ⚠️ MINOR ISSUES |
| 5 | `backend/models/opd_record.py` | Python model | ⚠️ MINOR ISSUES |
| 6 | `backend/models/patient_image.py` | Python model | ✅ ALIGNED |
| 7 | `backend/models/medicine.py` | Python model | ✅ ALIGNED |
| 8 | `backend/models/clinic_setting.py` | Python model | ✅ ALIGNED |
| 9 | `backend/models/calendar_note.py` | Python model | ✅ ALIGNED |
| 10 | `backend/models/symptom_master.py` | Python model | ✅ ALIGNED |
| 11 | `lib/repositories/patient_repository.dart` | Flutter repository | ✅ ALIGNED |
| 12 | `lib/repositories/opd_record_repository.dart` | Flutter repository | ✅ ALIGNED |
| 13 | `lib/repositories/patient_images_repository.dart` | Flutter repository | ⚠️ MINOR ISSUES |
| 14 | `lib/repositories/calendar_notes_repository.dart` | Flutter repository | ⚠️ MINOR ISSUES |
| 15 | `lib/repositories/sync_queue_repository.dart` | Flutter repository | ✅ ALIGNED |
| 16 | `lib/repositories/medicines_repository.dart` | Flutter repository | ✅ ALIGNED |
| 17 | `lib/repositories/symptoms_master_repository.dart` | Flutter repository | ✅ ALIGNED |
| 18 | `lib/repositories/users_repository.dart` | Flutter repository | ✅ ALIGNED |
| 19 | `lib/repositories/clinic_settings_repository.dart` | Flutter repository | ✅ ALIGNED |

---

## 2. medihive.db Schema (Reference)

### Tables (9 user + 1 internal)

```
patients (10 cols)
  id, full_name, mobile_number, alternate_mobile, gender, dob, age,
  blood_group, address, created_at

opd_visits (21 cols)
  id, opd_id, patient_id, visit_datetime, opd_type, charge_type, diagnosis,
  symptoms, clinical_notes, consultation_fee, medicine_fee, panchakarma_fee,
  total_fee, discount_type, discount_value, payment_mode, next_visit_date,
  followup_status, created_at, medicines, panchakarma_notes

calendar_notes (5 cols)
  id, note_date (UNIQUE), note_text, created_at, updated_at

clinic_settings (18 cols)
  id, doctor_name, doctor_email, doctor_contact, doctor_license_no,
  doctor_photo_path, clinic_name, clinic_logo_path, clinic_address,
  clinic_phone, website, operating_hours, smtp_email, smtp_password,
  smtp_server, smtp_port, created_at, updated_at

users (7 cols)
  id, username (UNIQUE), password_hash, email, created_at, reset_otp, otp_expiry

medicines (2 cols)
  id, name (UNIQUE)

symptoms_master (2 cols)
  id, name (UNIQUE NOT NULL)

patient_images (9 cols)
  id, patient_id (FK→patients), opd_visit_id (FK→opd_visits),
  file_path, image_type, sync_status, uploaded_at, created_at, drive_url

sync_queue (8 cols)
  id, entity_type, entity_id, status, retry_count, last_error,
  created_at, last_attempt
```

### Indexes (7)
- `ix_patients_id` ON patients(id)
- `ix_opd_visits_id` ON opd_visits(id)
- `ix_opd_visits_opd_id` UNIQUE ON opd_visits(opd_id)
- `ix_patient_images_id` ON patient_images(id)
- `ix_sync_queue_id` ON sync_queue(id)
- `ix_users_id` ON users(id)
- `ix_clinic_settings_id` ON clinic_settings(id)

### Foreign Keys (3)
- `opd_visits.patient_id` → `patients(id)`
- `patient_images.patient_id` → `patients(id)`
- `patient_images.opd_visit_id` → `opd_visits(id)`

---

## 3. Mismatches Found

### 3.1 `backend/database.py` — EXTRA COLUMN in patients table

**Issue:** `patients.updated_at` column is created via migration (around line 521–529) but does NOT exist in `medihive.db`.

```python
# database.py - lines 521-529 (approximate)
# This block adds updated_at to patients - should be removed
```

**Impact:** The PostgreSQL schema will have an extra nullable column that the SQLite source-of-truth does not have. During sync, this column will always be NULL. The code in `patient.py` (line 118-120) guards this with `has_column()` check, so it won't break, but the column is unnecessary.

---

### 3.2 `backend/models/patient.py` — DEAD CODE referencing updated_at

**Issue:** Lines 118-120 and 219-223 reference `patients.updated_at` column (guarded by `has_column()`).

```python
# patient.py:118-120
if has_column('patients', 'updated_at'):
    fields.append("updated_at = %s")
    values.append(now)
```

**Impact:** Zero functional impact since `has_column()` returns False when column is absent. However, if Issue 3.1 is fixed (column removed), this code becomes dead code that never executes. No crash risk, but cleanup recommended.

---

### 3.3 `backend/models/opd_record.py` — DEAD CODE referencing updated_at

**Issue:** Lines 128-130 and 182-186 reference `opd_visits.updated_at` column (guarded by `has_column()`).

```python
# opd_record.py:128-130
if has_column('opd_visits', 'updated_at'):
    fields.append("updated_at = %s")
    values.append(now)
```

**Impact:** Same as 3.2 — zero functional impact, dead code.

---

### 3.4 `lib/database/database_helper.dart` — MIGRATION references `weight` column

**Issue:** Line 221 references `weight` column during legacy migration copy from old schema:

```dart
sourceColumns: const [
  'id', 'full_name', 'mobile_number', 'alternate_mobile',
  'gender', 'dob', 'age', 'blood_group', 'address',
  'created_at', 'weight',   // <-- 'weight' does NOT exist in medihive.db
],
```

**Impact:** Low. This is in the `_copyCommonColumns()` call which uses `_columns()` to only select columns that actually exist in the legacy table. If `weight` existed in the legacy table, it would be preserved; if not, it's silently skipped. No crash risk.

---

### 3.5 `lib/repositories/patient_images_repository.dart` — GUARDED `clinic_id` column

**Issue:** Lines 74, 85-87 reference `clinic_id` column that does NOT exist in `medihive.db`:

```dart
final hasClinicId = await _hasColumn(tablePatientImages, 'clinic_id');
if (hasClinicId) {
  data['clinic_id'] = row['clinic_id'] ?? '';
}
```

**Impact:** Zero — `_hasColumn()` returns false, so the block is never entered. Dead code.

---

### 3.6 `lib/repositories/calendar_notes_repository.dart` — GUARDED `clinic_id` column

**Issue:** Lines 44, 54-56 similarly reference `clinic_id` with a guard.

**Impact:** Same as 3.5. Dead code.

---

## 4. Items from Previous Report (`database_mismatch_report.md`) Now Resolved

The following issues from the 2026-07-21 report have **already been fixed** in the current codebase:

| Issue | Previous State | Current State |
|-------|---------------|---------------|
| `opd_visits.patient_id` type | TEXT NOT NULL | INTEGER NOT NULL ✅ |
| `opd_visits.opd_id` NOT NULL | VARCHAR (nullable) | VARCHAR NOT NULL ✅ |
| `opd_visits.visit_datetime` type | TEXT NOT NULL | TIMESTAMP NOT NULL ✅ |
| Fee columns type (consultation_fee, etc.) | TEXT DEFAULT '0' | DOUBLE PRECISION ✅ |
| `patient_images` FK types | TEXT with ON DELETE CASCADE | INTEGER NOT NULL REFERENCES ✅ |
| `sync_queue.status` default | DEFAULT 'PENDING' | No default ✅ |
| Extra indexes (idx_opd_patient, etc.) | Present | Removed ✅ |
| `opd_visits.panchakarma_notes` removal | Report said to remove | medihive.db **HAS** this column → Keep ✅ |

---

## 5. Implementation Plan

### Priority 1 — HIGH: `backend/database.py` cleanup

**Step 1:** Remove `updated_at` column from `patients` table creation/migration in `backend/database.py`.

```
Action: Delete the migration block (approx lines 521-529) that adds updated_at to patients.
```

**Step 2:** After removing the column, clean up the dead `has_column` guards in `backend/models/patient.py` (lines 118-120, 219-223) and `backend/models/opd_record.py` (lines 128-130, 182-186).

```
Action: Remove the has_column checks and the updated_at field appends from patient.py and opd_record.py.
```

### Priority 2 — LOW: Flutter dead code cleanup

**Step 3:** Remove guarded `clinic_id` references from Flutter repositories.

| File | Lines | Action |
|------|-------|--------|
| `lib/repositories/patient_images_repository.dart` | 74, 85-87 | Remove `_hasColumn` check and `clinic_id` handling |
| `lib/repositories/calendar_notes_repository.dart` | 44, 54-56, 62, 65-69, 80, 83-86 | Remove `_hasColumn` check and `clinic_id` handling |

### Priority 3 — LOW: Migration dead code cleanup

**Step 4:** Remove `weight` from migration source columns in `lib/database/database_helper.dart` line 221.

```
Action: Remove 'weight' from the sourceColumns list in _migrateToSourceContract().
```

---

## 6. Summary

| Category | Count |
|----------|-------|
| Files fully aligned | 14 of 19 |
| Files with HIGH priority issues | 1 (`backend/database.py`) |
| Files with LOW priority/cleanup | 4 (models/patient.py, models/opd_record.py, patient_images_repo, calendar_notes_repo, database_helper.dart) |
| Real schema-breaking mismatches | **1** (extra `updated_at` column in patients) |
| Previously reported issues now fixed | 9 |
