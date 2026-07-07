import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import '../models/opd_form_data.dart';
import '../services/event_notification_service.dart';
import '../repositories/opd_record_repository.dart';
import '../repositories/patient_repository.dart';
import '../repositories/sync_queue_repository.dart';
import '../utils/sync_id_generator.dart';
import '../services/sync_manager.dart';
import '../services/cloud_sync_manager.dart';
import '../utils/helpers.dart';
import 'dashboard_provider.dart';
import 'appointment_provider.dart';

class OpdProvider extends ChangeNotifier {
  final OpdRecordRepository _opdRepo = OpdRecordRepository();
  final PatientRepository _patientRepo = PatientRepository();
  final SyncQueueRepository _syncQueueRepo = SyncQueueRepository();

  int _currentStep = 0;
  final int totalSteps = 3;
  final OpdFormData _formData = OpdFormData();
  bool hasDraft = false;

  List<Map<String, dynamic>> _matchedPatients = [];
  bool _showMobileLookup = false;

  List<Map<String, dynamic>> get matchedPatients => _matchedPatients;
  bool get showMobileLookup => _showMobileLookup;

  Future<void> searchPatientsByMobile(String mobile) async {
    final normalized = Helpers.normalizePhone(mobile);
    if (normalized.length != 10) {
      _matchedPatients = [];
      _showMobileLookup = false;
      notifyListeners();
      return;
    }
    final repo = PatientRepository();
    final results = await repo.getByMobile(normalized);
    _matchedPatients = results;
    _showMobileLookup = results.isNotEmpty;
    notifyListeners();
  }

  void autoFillFromPatient(Map<String, dynamic> patientRow) {
    updateField('patientId', patientRow['sync_id']?.toString() ?? '');
    updateField('name', patientRow['full_name']?.toString() ?? '');
    updateField('dob', patientRow['dob']?.toString() ?? '');
    updateField('age', patientRow['age']?.toString() ?? '');
    updateField('gender', patientRow['gender']?.toString() ?? 'Male');
    updateField('address', patientRow['address']?.toString() ?? '');
    updateField('bloodGroup', patientRow['blood_group']?.toString() ?? 'O+');
    _matchedPatients = [];
    _showMobileLookup = false;
    notifyListeners();
  }

  void selectNewPatientRegistration() {
    updateField('patientId', '');
    updateField('dob', '');
    updateField('age', '');
    updateField('gender', 'Male');
    updateField('address', '');
    updateField('bloodGroup', 'O+');
    _matchedPatients = [];
    _showMobileLookup = false;
    notifyListeners();
  }

  void clearMobileLookup() {
    _matchedPatients = [];
    _showMobileLookup = false;
    notifyListeners();
  }

  OpdProvider() {
    loadDraftFromHive();
  }

  int get currentStep => _currentStep;
  set currentStep(int val) {
    _currentStep = val;
    notifyListeners();
    _saveDraftToHive();
  }

  String _visitType = 'consultation';
  String get visitType => _visitType;
  set visitType(String val) {
    _visitType = val;
    _formData.opdType = val == 'follow_up' ? 'Follow-up' : 'Consultation';
    notifyListeners();
    _saveDraftToHive();
  }

  DateTime? _previousVisitDate;
  DateTime? get previousVisitDate => _previousVisitDate;
  set previousVisitDate(DateTime? val) {
    _previousVisitDate = val;
    if (val != null) {
      _formData.previousVisitDate =
          '${val.year}-${val.month.toString().padLeft(2, '0')}-${val.day.toString().padLeft(2, '0')}';
    } else {
      _formData.previousVisitDate = '';
    }
    notifyListeners();
    _saveDraftToHive();
  }

  String _followUpReason = '';
  String get followUpReason => _followUpReason;
  set followUpReason(String val) {
    _followUpReason = val;
    _formData.followUpReason = val;
    notifyListeners();
    _saveDraftToHive();
  }

  // Getters and Setters for complete Draft System
  String get patientName => _formData.name;
  set patientName(String val) {
    _formData.name = val;
    notifyListeners();
    _saveDraftToHive();
  }

  DateTime? get dob => DateTime.tryParse(_formData.dob);
  set dob(DateTime? val) {
    if (val != null) {
      _formData.dob =
          '${val.year}-${val.month.toString().padLeft(2, '0')}-${val.day.toString().padLeft(2, '0')}';
    } else {
      _formData.dob = '';
    }
    notifyListeners();
    _saveDraftToHive();
  }

  String get age => _formData.age;
  set age(String val) {
    _formData.age = val;
    notifyListeners();
    _saveDraftToHive();
  }

  String get mobile => _formData.mobile;
  set mobile(String val) {
    _formData.mobile = val;
    notifyListeners();
    _saveDraftToHive();
  }

  String get address => _formData.address;
  set address(String val) {
    _formData.address = val;
    notifyListeners();
    _saveDraftToHive();
  }

  List<String> get selectedSymptoms =>
      _formData.symptoms.isEmpty ? [] : _formData.symptoms.split(', ');
  set selectedSymptoms(List<String> val) {
    _formData.symptoms = val.join(', ');
    notifyListeners();
    _saveDraftToHive();
  }

  List<String> get selectedDiagnoses =>
      _formData.diagnosis.isEmpty ? [] : _formData.diagnosis.split(', ');
  set selectedDiagnoses(List<String> val) {
    _formData.diagnosis = val.join(', ');
    notifyListeners();
    _saveDraftToHive();
  }

  List<Map<String, dynamic>> get prescribedMedicines {
    if (_formData.medicines.isEmpty) return [];
    try {
      final decoded = jsonDecode(_formData.medicines);
      if (decoded is List) {
        return List<Map<String, dynamic>>.from(
          decoded.map((e) => Map<String, dynamic>.from(e)),
        );
      }
    } catch (_) {
      // Fallback for old comma-separated strings
      return _formData.medicines.split(', ').map((e) {
        return {
          'name': e,
          'type': '',
          'dosage': '',
          'frequency': '',
          'duration': '',
        };
      }).toList();
    }
    return [];
  }

  set prescribedMedicines(List<Map<String, dynamic>> val) {
    _formData.medicines = jsonEncode(val);
    notifyListeners();
    _saveDraftToHive();
  }

  // Explicit setters calling _saveDraftToHive()
  void setPatientName(String name) {
    patientName = name;
  }

  void setDob(String dobStr) {
    updateField('dob', dobStr);
    _saveDraftToHive();
  }

  void setAge(String ageStr) {
    _formData.age = ageStr;
    notifyListeners();
    _saveDraftToHive();
  }

  void setMobile(String mob) {
    mobile = mob;
  }

  void setAddress(String addr) {
    address = addr;
  }

  void setVisitType(String type) {
    visitType = type;
  }

  void setSelectedSymptoms(List<String> symptoms) {
    selectedSymptoms = symptoms;
  }

  void setSelectedDiagnoses(List<String> diagnoses) {
    selectedDiagnoses = diagnoses;
  }

  void setPrescribedMedicines(List<Map<String, dynamic>> medicines) {
    prescribedMedicines = medicines;
  }

  Future<void> loadPatientForEdit(String patientId, {String? opdId}) async {
    reset();
    hasDraft = false;

    try {
      final patient = await _patientRepo.getBySyncId(patientId);
      if (patient == null) return;
      final sqliteId = patient['id'] as int;

      updateField('patientId', patientId);
      updateField('name', patient['full_name']?.toString() ?? '');
      updateField('dob', patient['dob']?.toString() ?? '');
      updateField('age', patient['age']?.toString() ?? '');
      updateField('gender', patient['gender']?.toString() ?? 'Male');
      updateField('mobile', patient['mobile_number']?.toString() ?? '');
      updateField('address', patient['address']?.toString() ?? '');
      updateField('bloodGroup', patient['blood_group']?.toString() ?? 'O+');

      Map<String, dynamic>? record;
      if (opdId != null && opdId.isNotEmpty) {
        record = await _opdRepo.getByOpdId(opdId);
      }
      if (record == null) {
        final records = await _opdRepo.getByPatientId(sqliteId);
        if (records.isNotEmpty) {
          record = records.first;
        }
      }
      if (record != null) {
        updateField('diagnosis', record['diagnosis']?.toString() ?? '');
        updateField('symptoms', record['symptoms']?.toString() ?? '');
        updateField('medicines', record['medicines']?.toString() ?? '');
        updateField('clinicalNotes', record['clinical_notes']?.toString() ?? '');
        updateField('panchakarmaNotes', record['panchakarma_notes']?.toString() ?? '');
        updateField(
          'opdType',
          record['opd_type']?.toString() == 'follow_up' ? 'Follow-up' : 'Consultation',
        );
        updateField('consultationFee', record['consultation_fee']?.toString() ?? '');
        updateField('medicineFee', record['medicine_fee']?.toString() ?? '');
        updateField('discount', _readDiscountString(record));
        updateField('paymentMode', record['payment_mode']?.toString() ?? '');
        updateField('chargeType', record['charge_type']?.toString() ?? '');
        updateField('previousVisitDate', record['previous_visit_date']?.toString() ?? '');
        updateField('followUpReason', record['followup_status']?.toString() ?? '');
        updateField('nextVisit', record['next_visit_date']?.toString() ?? '');
        _visitType = record['opd_type']?.toString() ?? 'consultation';
        if ((record['previous_visit_date']?.toString() ?? '').isNotEmpty) {
          _previousVisitDate = DateTime.tryParse(record['previous_visit_date'].toString());
        }
      }
    } catch (_) {
      // Silently handle — form stays at default values
    }

    currentStep = 0;
    notifyListeners();
  }

  OpdFormData get formData => _formData;

  // Hive Draft System — kept as-is (transient UI state, no SQLite table)
  void _saveDraftToHive() {
    try {
      final box = Hive.isBoxOpen('drafts') ? Hive.box('drafts') : null;
      if (box != null) {
        box.put('current_opd_draft', {
          'patientId': _formData.patientId,
          'patientName': patientName,
          'dob': dob?.toIso8601String(),
          'age': age,
          'mobile': mobile,
          'address': address,
          'visitType': visitType,
          'selectedSymptoms': selectedSymptoms,
          'selectedDiagnoses': selectedDiagnoses,
          'prescribedMedicines': prescribedMedicines,
          'currentStep': currentStep,
          'savedAt': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Error saving draft to Hive: $e');
    }
  }

  void saveDraft() {
    _saveDraftToHive();
  }

  void loadDraftFromHive() {
    try {
      final box = Hive.isBoxOpen('drafts') ? Hive.box('drafts') : null;
      if (box != null) {
        final draft = box.get('current_opd_draft');
        if (draft != null && draft is Map) {
          final map = Map<String, dynamic>.from(draft);
          _formData.patientId = map['patientId'] ?? '';
          _formData.name = map['patientName'] ?? '';
          final dobStr = map['dob'];
          if (dobStr != null) {
            final parsed = DateTime.tryParse(dobStr);
            if (parsed != null) {
              _formData.dob =
                  '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
            }
          }
          _formData.age = map['age'] ?? '';
          _formData.mobile = map['mobile'] ?? '';
          _formData.address = map['address'] ?? '';

          final savedVisitType = map['visitType'] ?? 'consultation';
          _visitType = savedVisitType;
          _formData.opdType = savedVisitType == 'follow_up'
              ? 'Follow-up'
              : 'Consultation';

          final symptoms = map['selectedSymptoms'];
          if (symptoms is List) {
            _formData.symptoms = List<String>.from(symptoms).join(', ');
          }
          final diagnoses = map['selectedDiagnoses'];
          if (diagnoses is List) {
            _formData.diagnosis = List<String>.from(diagnoses).join(', ');
          }
          final medicines = map['prescribedMedicines'];
          if (medicines is List) {
            if (medicines.isNotEmpty && medicines.first is Map) {
              prescribedMedicines = List<Map<String, dynamic>>.from(
                medicines.map((e) => Map<String, dynamic>.from(e)),
              );
            } else {
              _formData.medicines = List<String>.from(medicines).join(', ');
            }
          }
          _currentStep = map['currentStep'] ?? 0;
          hasDraft = true;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error loading draft from Hive: $e');
    }
  }

  void clearDraft() {
    reset();
  }

  bool get hasUnsavedData {
    return patientName.isNotEmpty ||
        _formData.dob.isNotEmpty ||
        age.isNotEmpty ||
        mobile.isNotEmpty ||
        address.isNotEmpty ||
        _formData.symptoms.isNotEmpty ||
        _formData.diagnosis.isNotEmpty ||
        _formData.medicines.isNotEmpty;
  }

  Future<void> autoSaveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftKey = _formData.patientId.isNotEmpty
          ? 'opd_draft_${_formData.patientId}'
          : 'opd_draft_new_patient';

      final draftData = {'step': _currentStep, 'form': _formData.toJson()};

      await prefs.setString(draftKey, jsonEncode(draftData));

      final Set<String> allDraftKeys =
          prefs.getStringList('opd_draft_keys')?.toSet() ?? {};
      allDraftKeys.add(draftKey);
      await prefs.setStringList('opd_draft_keys', allDraftKeys.toList());
      notifyListeners();
    } catch (e) {
      debugPrint('Error auto-saving draft: $e');
    }
  }

  Future<void> loadDraft(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(key);
      if (jsonString != null) {
        final data = jsonDecode(jsonString);
        _currentStep = data['step'] ?? 0;
        _formData.fromJson(data['form'] ?? {});

        // Rebuild prescriptions from medicines string
        updateField('medicines', _formData.medicines);

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading draft: $e');
    }
  }

  Future<void> discardDraft(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);

      final List<String> allDraftKeys =
          prefs.getStringList('opd_draft_keys') ?? [];
      allDraftKeys.remove(key);
      await prefs.setStringList('opd_draft_keys', allDraftKeys);
      notifyListeners();
    } catch (e) {
      debugPrint('Error discarding draft: $e');
    }
  }

  static Future<bool> hasDraftForPatient(String patientId) async {
    if (patientId.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('opd_draft_$patientId');
  }

  void updateField(String field, String value) {
    switch (field) {
      case 'patientId':
        _formData.patientId = value;
      case 'name':
        _formData.name = value;
      case 'dob':
        _formData.dob = value;
        // Auto-calculate age (years/months) from DOB
        final birthDate = DateTime.tryParse(value);
        if (birthDate != null) {
          final now = DateTime.now();
          int years = now.year - birthDate.year;
          int months = now.month - birthDate.month;
          if (months < 0 || (months == 0 && now.day < birthDate.day)) {
            years--;
            months += 12;
          }
          if (now.day < birthDate.day) {
            months--;
          }
          if (months < 0) {
            months = 11;
          }
          if (years > 0) {
            _formData.age = '$years yr, $months mo';
          } else {
            _formData.age = '$months mo';
          }
        }
      case 'age':
        _formData.age = value;
      case 'gender':
        _formData.gender = value;
      case 'mobile':
        _formData.mobile = value;
      case 'address':
        _formData.address = value;
      case 'bloodGroup':
        _formData.bloodGroup = value;
      case 'diagnosis':
        _formData.diagnosis = value;
      case 'symptoms':
        _formData.symptoms = value;
      case 'opdType':
        _formData.opdType = value;
      case 'chargeType':
        _formData.chargeType = value;
      case 'medicines':
        _formData.medicines = value;
      case 'clinicalNotes':
        _formData.clinicalNotes = value;
      case 'panchakarmaNotes':
        _formData.panchakarmaNotes = value;
      case 'nextVisit':
        _formData.nextVisit = value;
      case 'consultationFee':
        _formData.consultationFee = value;
      case 'medicineFee':
        _formData.medicineFee = value;
      case 'panchakarmaFee':
        _formData.panchakarmaFee = value;
      case 'discount':
        _formData.discount = value;
      case 'discountType':
        _formData.discountType = value;
      case 'paymentMode':
        _formData.paymentMode = value;
      case 'previousVisitDate':
        _formData.previousVisitDate = value;
      case 'followUpReason':
        _formData.followUpReason = value;
    }
    notifyListeners();
    autoSaveDraft();
    _saveDraftToHive();
  }

  String? validateCurrentStep() {
    if (_currentStep == 0) {
      if (_formData.name.trim().isEmpty) return 'Full Name is required.';
      if (_formData.dob.trim().isEmpty) return 'Date of Birth is required.';
      if (_formData.mobile.trim().isEmpty) return 'Mobile Number is required.';
      if (_formData.address.trim().isEmpty) return 'Address is required.';
    }
    return null; // Valid
  }

  void nextStep() {
    if (_currentStep < 2) {
      _currentStep++;
      notifyListeners();
      autoSaveDraft();
      _saveDraftToHive();
    }
  }

  void previousStep() {
    if (_currentStep > 0) {
      _currentStep--;
      notifyListeners();
      autoSaveDraft();
      _saveDraftToHive();
    }
  }

  void reset() {
    try {
      final box = Hive.isBoxOpen('drafts') ? Hive.box('drafts') : null;
      if (box != null) {
        box.delete('current_opd_draft');
      }
    } catch (_) {}

    final draftKey = _formData.patientId.isNotEmpty
        ? 'opd_draft_${_formData.patientId}'
        : 'opd_draft_new_patient';
    discardDraft(draftKey);

    _currentStep = 0;
    _formData.reset();
    hasDraft = false;
    notifyListeners();
  }

  Future<bool> submitRecord({
    DashboardProvider? dashboardProvider,
    AppointmentProvider? appointmentProvider,
    String? existingRecordId,
    Uint8List? documentBytes,
  }) async {
    try {
      final nextVisit = _formData.nextVisit;
      final patientId = _formData.patientId;
      final patientName = _formData.name.isEmpty ? 'Unknown' : _formData.name;

      // 1. Save OPD Record (update if editing, insert if new)
      final opdId = existingRecordId ?? 'R${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999).toString().padLeft(3, '0')}';
      print('=== OPD SUBMIT ===');
      print('OPD SUBMIT: existingRecordId=$existingRecordId');
      print('OPD SUBMIT: opdId=$opdId');
      print('OPD SUBMIT: formData.patientId=$patientId');
      print('OPD SUBMIT: formData.gender="${_formData.gender}"');
      print('OPD SUBMIT: formData.diagnosis="${_formData.diagnosis}"');
      print('OPD SUBMIT: formData.symptoms="${_formData.symptoms}"');
      print('OPD SUBMIT: formData.clinicalNotes="${_formData.clinicalNotes}"');
      print('OPD SUBMIT: formData.panchakarmaNotes="${_formData.panchakarmaNotes}"');
      print('OPD DEBUG: panchakarmaNotes="${_formData.panchakarmaNotes}"');

      int sqlitePatientId;
      try {
        final patient = await _patientRepo.getBySyncId(patientId);
        sqlitePatientId = patient?['id'] as int? ?? _toSqliteId(patientId);
      } catch (_) {
        sqlitePatientId = _toSqliteId(patientId);
      }
      print('OPD SUBMIT: sqlitePatientId=$sqlitePatientId');

      DateTime preservedCreatedAt;
      int sqliteId;

      if (existingRecordId != null) {
        print('OPD SUBMIT: EDIT PATH — finding existing record by opd_id=$existingRecordId');
        final existing = await _opdRepo.getByOpdId(existingRecordId);
        if (existing != null) {
          sqliteId = existing['id'] as int;
          preservedCreatedAt = DateTime.tryParse(existing['created_at']?.toString() ?? '') ?? DateTime.now();
          print('OPD SUBMIT: EDIT PATH — found existing record sqliteId=$sqliteId preservedCreatedAt=$preservedCreatedAt');
        } else {
          sqliteId = DateTime.now().microsecondsSinceEpoch;
          preservedCreatedAt = DateTime.now();
          print('OPD SUBMIT: EDIT PATH — getByOpdId returned NULL! Using new sqliteId=$sqliteId. THIS WILL CAUSE UPDATE TO AFFECT 0 ROWS!');
        }
      } else {
        sqliteId = DateTime.now().microsecondsSinceEpoch;
        preservedCreatedAt = DateTime.now();
        print('OPD SUBMIT: INSERT PATH — no existingRecordId, new sqliteId=$sqliteId');
      }

      final nowStr = DateTime.now().toIso8601String();

      final recordMap = <String, dynamic>{
        'id': sqliteId,
        'opd_id': opdId,
        'patient_id': sqlitePatientId,
        'visit_datetime': nowStr,
        'opd_type': _formData.opdType == 'Follow-up' ? 'follow_up' : 'consultation',
        'charge_type': _formData.chargeType.isNotEmpty ? _formData.chargeType : null,
        'diagnosis': _formData.diagnosis.isNotEmpty ? _formData.diagnosis : null,
        'symptoms': _formData.symptoms.isNotEmpty ? _formData.symptoms : null,
        'clinical_notes': _formData.clinicalNotes.isNotEmpty ? _formData.clinicalNotes : null,
        'panchakarma_notes': _formData.panchakarmaNotes.isNotEmpty ? _formData.panchakarmaNotes : null,
        'consultation_fee': _parseFee(_formData.consultationFee),
        'medicine_fee': _parseFee(_formData.medicineFee),
        'panchakarma_fee': _parseFee(_formData.panchakarmaFee),
        'total_fee': _formData.totalFee,
        'discount_type': _formData.discountType.isNotEmpty ? _formData.discountType : null,
        'discount_value': _parseFee(_formData.discount),
        'payment_mode': _formData.paymentMode.isNotEmpty ? _formData.paymentMode : null,
        'next_visit_date': _formData.nextVisit.isNotEmpty ? _formData.nextVisit : null,
        'followup_status': _formData.followUpReason.isNotEmpty ? _formData.followUpReason : null,
        'created_at': preservedCreatedAt.toIso8601String(),
        'medicines': _formData.medicines.isNotEmpty ? _formData.medicines : null,
      };

      if (existingRecordId != null) {
        // Preserve original visit_datetime for edits
        final existingBeforeUpdate = await _opdRepo.getByOpdId(existingRecordId);
        if (existingBeforeUpdate != null) {
          final originalVisitDt = existingBeforeUpdate['visit_datetime'] as String? ?? '';
          if (originalVisitDt.isNotEmpty) {
            recordMap['visit_datetime'] = originalVisitDt;
          }
          print('OPD EDIT LOADED existing: id=$existingRecordId sqliteId=$sqliteId '
              'diagnosis=${recordMap['diagnosis']} '
              'symptoms=${recordMap['symptoms']} '
              'clinical_notes=${recordMap['clinical_notes']} '
              'panchakarma_notes=${recordMap['panchakarma_notes']} '
              'consultation_fee=${recordMap['consultation_fee']} '
              'medicine_fee=${recordMap['medicine_fee']} '
              'panchakarma_fee=${recordMap['panchakarma_fee']} '
              'discount_type=${recordMap['discount_type']} '
              'discount_value=${recordMap['discount_value']} '
              'payment_mode=${recordMap['payment_mode']} '
              'followup_status=${recordMap['followup_status']} '
              'next_visit_date=${recordMap['next_visit_date']} '
              'medicines=${recordMap['medicines']}');
        } else {
          print('OPD EDIT WARNING: existing record NOT FOUND for id=$existingRecordId');
        }
        final affected = await _opdRepo.update(sqliteId, recordMap);
        print('OPD EDIT UPDATE: opdId=$existingRecordId sqliteId=$sqliteId affectedRows=$affected');
        if (affected == 0) {
          print('OPD EDIT CRITICAL: UPDATE affected 0 rows! Falling back to INSERT.');
          await _opdRepo.insert({
            ...recordMap,
            'id': DateTime.now().microsecondsSinceEpoch,
          });
        }
        print('CALLING _addSyncQueueEntry for existing opd_visit id=$existingRecordId');
        await _addSyncQueueEntry('opd_visit', existingRecordId);
        CloudSyncManager().notifyChange(
          tableName: 'opd_visits',
          operation: 'update',
          recordId: existingRecordId,
        );
        Future.microtask(() {
          print('FORCING IMMEDIATE SYNC');
          SyncManager().forceSyncNow();
        });
      } else {
        final insertedId = await _opdRepo.insert(recordMap);
        print('OPD INSERT: opdId=$opdId sqliteId=$sqliteId insertedId=$insertedId');
        print('CALLING _addSyncQueueEntry for new opd_visit id=$opdId');
        await _addSyncQueueEntry('opd_visit', opdId);
        CloudSyncManager().notifyChange(
          tableName: 'opd_visits',
          operation: 'insert',
          recordId: opdId,
          payload: recordMap,
        );
        print('OPD ADDED TO SYNC QUEUE: $opdId');
        Future.microtask(() {
          print('FORCING IMMEDIATE SYNC');
          SyncManager().forceSyncNow();
        });
      }

      if (documentBytes != null && documentBytes.isNotEmpty) {
        try {
          final docBox = Hive.box('opd_documents');
          await docBox.put(opdId, base64Encode(documentBytes));
        } catch (e, st) {
          print('WARN: Failed to save document for record $opdId: $e');
          print(st);
        }
      }

      // 2. Create calendar appointment for future follow-up (nextVisit)
      if (nextVisit.isNotEmpty && appointmentProvider != null) {
        final visitDate = DateTime.tryParse(nextVisit);
        if (visitDate != null) {
          await appointmentProvider.addAppointment(
            dateTime: visitDate,
            type: 'Follow-up',
            patient: patientName,
            time: '09:00',
            patientId: patientId,
          );
        }
      }

      // 3. Reset form
      reset();

      // 4. Notify dashboard to reload
      if (dashboardProvider != null) {
        await dashboardProvider.loadDashboardData();
      }

      // 5. Trigger notification
      await EventNotificationService.notifyOpdRegistered(
        patientName: patientName,
        type: _formData.opdType == 'Follow-up' ? 'Follow-up' : 'Consultation',
      );

      return true;
    } catch (e) {
      debugPrint('OpdProvider.submitRecord failed: $e');
      return false;
    }
  }

  Future<bool> saveRecord({
    DashboardProvider? dashboardProvider,
    AppointmentProvider? appointmentProvider,
  }) async {
    return await submitRecord(
      dashboardProvider: dashboardProvider,
      appointmentProvider: appointmentProvider,
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────

  Future<void> _addSyncQueueEntry(String entityType, String entityId, {String? operation}) async {
    try {
      debugPrint('_addSyncQueueEntry CALLED: type=$entityType id=$entityId op=$operation');
      await _syncQueueRepo.insert({
        'id': SyncIdGenerator.nextId(),
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': operation ?? 'upsert',
        'status': 'pending',
        'retry_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      debugPrint('_addSyncQueueEntry SUCCEEDED: type=$entityType id=$entityId');
    } catch (e, st) {
      debugPrint('SYNC QUEUE INSERT FAILED: $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  int _toSqliteId(String hiveId) {
    final match = RegExp(r'(\d+)').firstMatch(hiveId);
    if (match != null) return int.parse(match.group(1)!);
    return 0;
  }

  double? _parseFee(String fee) {
    if (fee.isEmpty) return null;
    return double.tryParse(fee);
  }

  String _readDiscountString(Map<String, dynamic> row) {
    final type = row['discount_type'] as String?;
    final value = row['discount_value'];
    if ((type != null && type.isNotEmpty) && value != null) {
      return '$type: ${(value as num).toStringAsFixed(0)}';
    } else if (value != null) {
      return (value as num).toStringAsFixed(0);
    }
    return '';
  }
}
