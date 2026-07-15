# Clinic Settings Table Usage and Field Mapping

This document provides a detailed mapping of where the `clinic_settings` table and its columns are used within the project. This will assist you in migrating your database layout to the expected schema without any extra fields (such as `clinic_id`).

---

## 📋 Expected Database Schema (`clinic_settings`)

Based on the expected database definition:
* **Table Name:** `clinic_settings`
* **Fields:**
  * `id` (INTEGER, PRIMARY KEY, NOT NULL)
  * `doctor_name` (VARCHAR(255))
  * `doctor_email` (VARCHAR(255))
  * `doctor_contact` (VARCHAR(50))
  * `doctor_license_no` (VARCHAR(100))
  * `doctor_photo_path` (VARCHAR(500))
  * `clinic_name` (VARCHAR(255))
  * `clinic_logo_path` (VARCHAR(500))
  * `clinic_address` (TEXT)
  * `clinic_phone` (VARCHAR(50))
  * `website` (VARCHAR(255))
  * `operating_hours` (VARCHAR(255))
  * `smtp_email` (VARCHAR(255))
  * `smtp_password` (VARCHAR(255))
  * `smtp_server` (VARCHAR(255))
  * `smtp_port` (VARCHAR(10))
  * `created_at` (DATETIME)
  * `updated_at` (DATETIME)

---

## 🔍 Usage and Field Mapping by File

Below is the list of files in which this table is referenced, along with the specific field names utilized.

### 1. [schema.dart](file:///d:/MediHive-Flutter/lib/database/schema.dart)
* **Description:** Contains the SQLite table definitions, table creation statements, and SQL index strings.
* **Fields Used/Defined:** 
  * All expected schema fields are defined here:
    * `id`
    * `doctor_name`
    * `doctor_email`
    * `doctor_contact`
    * `doctor_license_no`
    * `doctor_photo_path`
    * `clinic_name`
    * `clinic_logo_path`
    * `clinic_address`
    * `clinic_phone`
    * `website`
    * `operating_hours`
    * `smtp_email`
    * `smtp_password`
    * `smtp_server`
    * `smtp_port`
    * `created_at`
    * `updated_at`

### 2. [database_helper.dart](file:///d:/MediHive-Flutter/lib/database/database_helper.dart)
* **Description:** Handles SQLite database initialization, creation, and migration commands.
* **Fields Used:**
  * `clinic_id` (TEXT) - **[EXTRA FIELD]** Added in targetVersion 4 migration:
    ```dart
    try { await db.execute("ALTER TABLE clinic_settings ADD COLUMN clinic_id TEXT"); } catch (_) {}
    ```
    *Note: Since the expected schema does not include this column, this line must be removed or modified during migration.*

### 3. [clinic_settings_repository.dart](file:///d:/MediHive-Flutter/lib/repositories/clinic_settings_repository.dart)
* **Description:** Handles standard CRUD operations (select all, query by ID, insert, update, upsert, delete) on the database.
* **Fields Used:**
  * `id` (Used for mapping unique rows in lookup, update, and delete queries, and ordering).

### 4. [settings_provider.dart](file:///d:/MediHive-Flutter/lib/providers/settings_provider.dart)
* **Description:** Manages the runtime state for clinic settings, loading rows on startup and updating them in the database.
* **Fields Used:**
  * `doctor_name`
  * `doctor_email`
  * `doctor_contact` (loaded/saved)
  * `doctor_license_no` (loaded/saved)
  * `doctor_photo_path` (loaded/saved)
  * `clinic_name` (loaded/saved)
  * `clinic_phone` (loaded/saved)
  * `clinic_address` (loaded/saved)
  * `website` (loaded/saved)
  * `clinic_logo_path` (loaded/saved)
  * `operating_hours` (loaded/saved)
  * `updated_at` (saved as current DateTime string)

### 5. [import_service.dart](file:///d:/MediHive-Flutter/lib/services/import_service.dart)
* **Description:** Handles legacy desktop SQLite database import into preferences.
* **Fields Used:**
  * `doctor_name`
  * `doctor_license_no`
  * `doctor_email`
  * `doctor_contact`
  * `clinic_name`
  * `clinic_phone`
  * `clinic_address`
  * `website`

### 6. [data_migration_service.dart](file:///d:/MediHive-Flutter/lib/services/data_migration_service.dart)
* **Description:** Migrates data from the old Hive box store to the new SQLite storage format on startup.
* **Fields Used:**
  * `id`
  * `doctor_name`
  * `doctor_email`
  * `doctor_contact`
  * `doctor_license_no`
  * `clinic_name`
  * `clinic_phone`
  * `clinic_address`
  * `website`
  * `created_at`
  * `updated_at`

### 7. [sync_manager.dart](file:///d:/MediHive-Flutter/lib/services/sync_manager.dart)
* **Description:** Includes a database cleanup utility that resets database states.
* **Fields Used:**
  * *No specific fields used* (only references table name `clinic_settings` during bulk deletion):
    ```dart
    await db.delete('clinic_settings');
    ```

### 8. [auth_service.py](file:///d:/MediHive-Flutter/backend/desktop_google/auth_service.py)
* **Description:** Python backend script responsible for authenticating users and managing OTP deliveries.
* **Fields Used:**
  * `smtp_email`
  * `smtp_password`
  * `smtp_server`
  * `smtp_port`

---

## 💡 Migration Checkpoints

To align your local codebase precisely to the expected database in the screenshot (with **no extra fields**):
1. **Remove `clinic_id` addition**: In [database_helper.dart](file:///d:/MediHive-Flutter/lib/database/database_helper.dart), locate and remove the migration line adding `clinic_id` to the `clinic_settings` table (line 80).
2. **Review DB creation**: Ensure [schema.dart](file:///d:/MediHive-Flutter/lib/database/schema.dart) remains strictly matched to the fields listed in the expected schema above (which it currently does).

---

## 📝 Implementation Plan: Standardizing `clinic_settings` Schema

This plan outlines the step-by-step changes required to migrate and use the standard schema across the entire application:

### 🛠️ Step 1: Remove the `clinic_id` Migration
Locate the version 4 migration block (`case 4`) in `database_helper.dart` and delete the line that alters the `clinic_settings` table:
* **File:** [database_helper.dart](file:///d:/MediHive-Flutter/lib/database/database_helper.dart#L80)
* **Action:** Delete the following line:
  ```dart
  try { await db.execute("ALTER TABLE clinic_settings ADD COLUMN clinic_id TEXT"); } catch (_) {}
  ```
  *(Note: Keep the other tables' clinic_id migrations intact, as they are required for their respective tables.)*

### 🛠️ Step 2: Confirm Clean Schema Definition
Verify that the `createClinicSettingsTable` query string in `schema.dart` has no references to `clinic_id` or other undocumented fields:
* **File:** [schema.dart](file:///d:/MediHive-Flutter/lib/database/schema.dart#L76-L98)
* **Verification:** The SQL creation statement matches the screenshot's fields exactly:
  ```sql
  CREATE TABLE clinic_settings (
    id INTEGER NOT NULL,
    doctor_name VARCHAR(255),
    doctor_email VARCHAR(255),
    doctor_contact VARCHAR(50),
    doctor_license_no VARCHAR(100),
    doctor_photo_path VARCHAR(500),
    clinic_name VARCHAR(255),
    clinic_logo_path VARCHAR(500),
    clinic_address TEXT,
    clinic_phone VARCHAR(50),
    website VARCHAR(255),
    operating_hours VARCHAR(255),
    smtp_email VARCHAR(255),
    smtp_password VARCHAR(255),
    smtp_server VARCHAR(255),
    smtp_port VARCHAR(10),
    created_at DATETIME,
    updated_at DATETIME,
    PRIMARY KEY (id)
  )
  ```
* **Status:** Verified. No modifications required in this file.

### 🛠️ Step 3: Perform a Local Database Reset
Because development devices may already have a version 4 database created with the extra `clinic_id` column, the SQLite database needs to be re-initialized:
1. **Uninstall/Clear Cache:** Uninstall the app from your mobile device/emulator or clear the app storage settings.
2. **First Run:** Relaunch the application. The `DatabaseHelper` will run `_onCreate` using the clean definition from `schema.dart` resulting in the exact schema layout.

### 🛠️ Step 4: Verification & Smoke Testing
Confirm settings stability:
1. Navigate to the App Settings Screen. Save Doctor Profile details and Clinic Info to trigger [settings_provider.dart](file:///d:/MediHive-Flutter/lib/providers/settings_provider.dart#L231-L246) update methods.
2. Verify that there are no SQL query exceptions or database read/write errors.

