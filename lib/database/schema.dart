const int databaseVersion = 1;

const String tablePatients = 'patients';
const String tableOpdVisits = 'opd_visits';
const String tableCalendarNotes = 'calendar_notes';
const String tableClinicSettings = 'clinic_settings';
const String tableUsers = 'users';
const String tableMedicines = 'medicines';
const String tableSymptomsMaster = 'symptoms_master';
const String tablePatientImages = 'patient_images';
const String tableSyncQueue = 'sync_queue';

String get createPatientsTable => '''
  CREATE TABLE $tablePatients (
    id INTEGER NOT NULL,
    full_name VARCHAR NOT NULL,
    mobile_number VARCHAR NOT NULL,
    alternate_mobile VARCHAR,
    gender VARCHAR NOT NULL,
    dob DATE,
    age INTEGER,
    blood_group VARCHAR,
    address VARCHAR,
    created_at DATETIME,
    PRIMARY KEY (id)
  )
''';

String get createOpdVisitsTable => '''
  CREATE TABLE $tableOpdVisits (
    id INTEGER NOT NULL,
    opd_id VARCHAR NOT NULL,
    patient_id INTEGER NOT NULL,
    visit_datetime DATETIME NOT NULL,
    opd_type VARCHAR,
    charge_type VARCHAR,
    diagnosis VARCHAR,
    symptoms VARCHAR,
    clinical_notes VARCHAR,
    consultation_fee FLOAT,
    medicine_fee FLOAT,
    panchakarma_fee FLOAT,
    total_fee FLOAT,
    discount_type VARCHAR,
    discount_value FLOAT,
    payment_mode VARCHAR,
    next_visit_date DATE,
    followup_status VARCHAR,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    medicines TEXT,
    panchakarma_notes TEXT,
    PRIMARY KEY (id),
    FOREIGN KEY (patient_id) REFERENCES $tablePatients (id)
  )
''';

String get createCalendarNotesTable => '''
  CREATE TABLE $tableCalendarNotes (
    id INTEGER NOT NULL,
    note_date DATE NOT NULL,
    note_text TEXT,
    created_at DATETIME,
    updated_at DATETIME,
    PRIMARY KEY (id),
    UNIQUE (note_date)
  )
''';

String get createClinicSettingsTable => '''
  CREATE TABLE $tableClinicSettings (
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
''';

String get createUsersTable => '''
  CREATE TABLE $tableUsers (
    id INTEGER NOT NULL,
    username VARCHAR(50) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    created_at DATETIME,
    reset_otp VARCHAR(10),
    otp_expiry DATETIME,
    PRIMARY KEY (id),
    UNIQUE (username)
  )
''';

String get createMedicinesTable => '''
  CREATE TABLE $tableMedicines (
    id INTEGER NOT NULL,
    name VARCHAR NOT NULL,
    PRIMARY KEY (id),
    UNIQUE (name)
  )
''';

String get createSymptomsMasterTable => '''
  CREATE TABLE $tableSymptomsMaster (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE
  )
''';

String get createPatientImagesTable => '''
  CREATE TABLE $tablePatientImages (
    id INTEGER NOT NULL,
    patient_id INTEGER NOT NULL,
    opd_visit_id INTEGER NOT NULL,
    file_path VARCHAR NOT NULL,
    image_type VARCHAR,
    sync_status VARCHAR,
    uploaded_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    drive_url TEXT,
    PRIMARY KEY (id),
    FOREIGN KEY (patient_id) REFERENCES $tablePatients (id),
    FOREIGN KEY (opd_visit_id) REFERENCES $tableOpdVisits (id)
  )
''';

String get createSyncQueueTable => '''
  CREATE TABLE $tableSyncQueue (
    id INTEGER NOT NULL,
    entity_type VARCHAR(20) NOT NULL,
    entity_id VARCHAR(100) NOT NULL,
    status VARCHAR(20),
    retry_count INTEGER,
    last_error TEXT,
    created_at DATETIME,
    last_attempt DATETIME,
    PRIMARY KEY (id)
  )
''';

String get createixPatientsId => '''
  CREATE INDEX ix_patients_id ON $tablePatients (id)
''';

String get createixOpdVisitsId => '''
  CREATE INDEX ix_opd_visits_id ON $tableOpdVisits (id)
''';

String get createixOpdVisitsOpdId => '''
  CREATE UNIQUE INDEX ix_opd_visits_opd_id ON $tableOpdVisits (opd_id)
''';

String get createixPatientImagesId => '''
  CREATE INDEX ix_patient_images_id ON $tablePatientImages (id)
''';

String get createixSyncQueueId => '''
  CREATE INDEX ix_sync_queue_id ON $tableSyncQueue (id)
''';

String get createixUsersId => '''
  CREATE INDEX ix_users_id ON $tableUsers (id)
''';

String get createixClinicSettingsId => '''
  CREATE INDEX ix_clinic_settings_id ON $tableClinicSettings (id)
''';

List<String> get createStatements => [
  createPatientsTable,
  createOpdVisitsTable,
  createCalendarNotesTable,
  createClinicSettingsTable,
  createUsersTable,
  createMedicinesTable,
  createSymptomsMasterTable,
  createPatientImagesTable,
  createSyncQueueTable,
  createixPatientsId,
  createixOpdVisitsId,
  createixOpdVisitsOpdId,
  createixPatientImagesId,
  createixSyncQueueId,
  createixUsersId,
  createixClinicSettingsId,
];
