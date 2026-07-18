import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/opd_form_data.dart';
import '../models/patient.dart';
import '../models/patient_model.dart';
import '../repositories/patient_repository.dart';
import '../repositories/sync_queue_repository.dart';
import '../utils/sync_id_generator.dart';
import '../utils/helpers.dart';
import '../services/sync_manager.dart';
import '../services/cloud_sync_manager.dart';
import '../repositories/opd_record_repository.dart';

class PatientProvider extends ChangeNotifier {
  Timer? _debounceTimer;
  String _searchQuery = '';
  bool isSearching = false;
  List<PatientModel> _filteredPatients = [];
  String _sortFilter = 'recent_visit';

  final PatientRepository _repo = PatientRepository();
  final SyncQueueRepository _syncQueueRepo = SyncQueueRepository();
  List<Map<String, dynamic>> _allPatientRows = [];

  String get sortFilter => _sortFilter;
  void setSortFilter(String val) {
    _sortFilter = val;
    notifyListeners();
  }

  List<PatientModel> get displayedPatients =>
    _searchQuery.isEmpty 
      ? (_sortedPatients)
      : _filteredPatients;

  List<PatientModel> get _sortedPatients {
    final list = _allPatientRows.map(_rowToModel).toList();
    switch (_sortFilter) {
      case 'oldest_visit':
        list.sort((a, b) =>
          (a.lastVisitDate ?? a.createdAt)
            .compareTo(b.lastVisitDate ?? b.createdAt));
        break;
      case 'name_asc':
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 'name_desc':
        list.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case 'id_asc':
        list.sort((a, b) => a.id.compareTo(b.id));
        break;
      case 'recent_visit':
      default:
        list.sort((a, b) =>
          (b.lastVisitDate ?? b.createdAt)
            .compareTo(a.lastVisitDate ?? a.createdAt));
        break;
    }
    return list;
  }

  PatientProvider() {
    loadPatients();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void onSearchChanged(String query) {
    _searchQuery = query;
    _debounceTimer?.cancel();
    if (query.isEmpty) {
      isSearching = false;
      notifyListeners();
      return;
    }
    isSearching = true;
    notifyListeners();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  void _performSearch(String query) {
    final q = query.toLowerCase();
    final qNum = query.replaceAll(RegExp(r'[^0-9]'), '');
    _filteredPatients = _allPatientRows
      .map(_rowToModel)
      .where((p) {
        final pNum = p.id.toString().replaceAll(RegExp(r'[^0-9]'), '');
        return p.name.toLowerCase().contains(q) ||
          p.id.toString().toLowerCase().contains(q) ||
          (qNum.isNotEmpty && pNum.contains(qNum)) ||
          p.mobile.contains(q) ||
          (p.lastDiagnosis ?? '').toLowerCase().contains(q);
      }).toList();
    isSearching = false;
    notifyListeners();
  }

  // Backward compatibility fields and methods
  String get searchQuery => _searchQuery;
  List<Patient> _patients = [];

  Future<void> loadPatients() async {
    try {
      _allPatientRows = await _repo.getAll();
      await _populateVisitCache();
      _patients = _allPatientRows.map((row) {
        final model = _rowToModel(row);
        return Patient(
          id: model.id,
          name: model.name,
          age: model.age,
          gender: model.gender.isNotEmpty && model.gender != 'Not Specified' ? model.gender : 'Unknown',
          mobile: model.mobile,
          lastVisit: (model.lastVisitDate ?? model.createdAt).toString().split(' ')[0],
          dob: model.dob,
          diagnosis: model.lastDiagnosis ?? '',
        );
      }).toList();
      _patients.sort((a, b) => b.lastVisit.compareTo(a.lastVisit));
    } catch (_) {
      _allPatientRows = [];
      _patients = [];
    }
    notifyListeners();
  }

  List<Patient> get patients => _patients;

  List<Patient> get filteredPatients {
    List<Patient> result;
    if (_searchQuery.isEmpty) {
      result = List<Patient>.from(_patients);
    } else {
      final query = _searchQuery.toLowerCase();
      final queryNum = _searchQuery.replaceAll(RegExp(r'[^0-9]'), '');
      result = _patients.where((p) {
        final pNum = p.id.replaceAll(RegExp(r'[^0-9]'), '');
        return p.name.toLowerCase().contains(query) ||
            p.id.toLowerCase().contains(query) ||
            (queryNum.isNotEmpty && pNum.contains(queryNum)) ||
            p.mobile.contains(query) ||
            p.diagnosis.toLowerCase().contains(query);
      }).toList();
    }

    switch (_sortFilter) {
      case 'oldest_visit':
        result.sort((a, b) => a.lastVisit.compareTo(b.lastVisit));
        break;
      case 'name_asc':
        result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 'name_desc':
        result.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case 'id_asc':
        result.sort((a, b) => a.id.compareTo(b.id));
        break;
      case 'recent_visit':
      default:
        result.sort((a, b) => b.lastVisit.compareTo(a.lastVisit));
        break;
    }
    
    return result;
  }

  Future<void> deletePatientAndRecords(String patientId) async {
    try {
      final patient = await _repo.getBySyncId(patientId);
      if (patient != null) {
        final sqliteId = Helpers.toInt(patient['id']);
        final opdRepo = OpdRecordRepository();
        final records = await opdRepo.getByPatientId(sqliteId);
        for (final record in records) {
          await opdRepo.delete(Helpers.toInt(record['id']));
        }
        await _repo.delete(sqliteId);
      }
      await _addSyncQueueEntry('patient', patientId, operation: 'delete');
      CloudSyncManager().notifyChange(
        tableName: 'patients',
        operation: 'delete',
        recordId: patientId,
      );
      Future.microtask(() {
        print('FORCING IMMEDIATE SYNC');
        SyncManager().forceSyncNow();
      });
      await loadPatients();
    } catch (_) {}
  }

  void setSearchQuery(String query) {
    onSearchChanged(query);
  }

  String _generateTempId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(99999).toString().padLeft(5, '0');
    return 'TEMP_$timestamp$random';
  }

  Future<String> generateNextPatientId() async {
    return _generateTempId();
  }

  int _calculateAgeFromDob(String dobStr) {
    final dob = DateTime.tryParse(dobStr);
    if (dob == null) return 0;
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  Future<void> addPatientFromOpd(OpdFormData formData) async {
    final ageFromDob = _calculateAgeFromDob(formData.dob);

    if (formData.patientId.isNotEmpty) {
      final existing = await _repo.getBySyncId(formData.patientId);
      if (existing != null) {
        final updateData = <String, dynamic>{
          'full_name': formData.name.isNotEmpty ? formData.name : existing['full_name'],
          'mobile_number': formData.mobile.isNotEmpty ? formData.mobile : existing['mobile_number'],
          'gender': formData.gender.isNotEmpty ? formData.gender : existing['gender'],
          'dob': formData.dob.isNotEmpty ? formData.dob : existing['dob'],
          'age': ageFromDob > 0 ? ageFromDob : existing['age'],
          'blood_group': formData.bloodGroup.isNotEmpty ? formData.bloodGroup : existing['blood_group'],
          'address': formData.address.isNotEmpty ? formData.address : existing['address'],
        };
        print('PATIENT ADD: updating patient id=${existing['id']} syncId=${formData.patientId}');
        print('PATIENT ADD: name="${updateData['full_name']}" gender="${updateData['gender']}" mobile="${updateData['mobile_number']}"');
        final affected = await _repo.update(Helpers.toInt(existing['id']), updateData);
        print('PATIENT ADD: update affectedRows=$affected');
        if (affected == 0) {
          print('PATIENT ADD CRITICAL: UPDATE affected 0 rows!');
        }
        await _addSyncQueueEntry('patient', formData.patientId);
        CloudSyncManager().notifyChange(
          tableName: 'patients',
          operation: 'update',
          recordId: formData.patientId,
        );
        await loadPatients();
        print('PATIENT ADD: loadPatients() completed');
        return;
      } else {
        print('PATIENT ADD: existing patient NOT FOUND for syncId=${formData.patientId}');
      }
    } else {
      print('PATIENT ADD: formData.patientId is empty — will create new patient');
    }

    final nextId = await generateNextPatientId();
    formData.patientId = nextId;
    final maxId = await _repo.getMaxId();
    final sqliteId = maxId + 1;

    await _repo.insert({
      'id': sqliteId,
      'sync_id': nextId,
      'full_name': formData.name.isEmpty ? 'Unknown' : formData.name,
      'mobile_number': formData.mobile,
      'alternate_mobile': null,
      'gender': formData.gender.isNotEmpty ? formData.gender : 'Not Specified',
      'dob': formData.dob.isEmpty ? DateTime.now().toIso8601String().split('T')[0] : formData.dob,
      'age': ageFromDob > 0 ? ageFromDob : 0,
      'blood_group': formData.bloodGroup.isNotEmpty ? formData.bloodGroup : 'Not Specified',
      'address': formData.address.isEmpty ? 'Not specified' : formData.address,
      'created_at': DateTime.now().toIso8601String(),
    });

    await _addSyncQueueEntry('patient', nextId);
    CloudSyncManager().notifyChange(
      tableName: 'patients',
      operation: 'insert',
      recordId: nextId,
    );
    await loadPatients();
  }

  Future<void> _addSyncQueueEntry(String entityType, String entityId, {String? operation}) async {
    try {
      await _syncQueueRepo.insert({
        'id': SyncIdGenerator.nextId(),
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': operation ?? 'upsert',
        'status': 'pending',
        'retry_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e, st) {
      debugPrint('SYNC QUEUE INSERT FAILED: $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  Future<void> _populateVisitCache() async {
    try {
      final opdRepo = OpdRecordRepository();
      final allOpd = await opdRepo.getAll();
      final latestByPatient = <int, Map<String, dynamic>>{};
      for (final row in allOpd) {
        final pid = Helpers.toInt(row['patient_id']);
        final existing = latestByPatient[pid];
        final visitDt = row['visit_datetime'] as String? ?? '';
        if (existing == null || visitDt.compareTo(existing['visit_datetime'] as String? ?? '') > 0) {
          latestByPatient[pid] = row;
        }
      }
      _lastVisitCache.clear();
      _lastDiagCache.clear();
      for (final entry in latestByPatient.entries) {
        final patientRow = _allPatientRows.cast<Map<String, dynamic>?>().firstWhere(
          (r) => r?['id'] == entry.key,
          orElse: () => null,
        );
        if (patientRow != null) {
          final hiveId = patientRow['sync_id'] as String? ?? _toStringId(entry.key);
          _lastVisitCache[hiveId] = DateTime.tryParse(entry.value['visit_datetime'] as String? ?? '');
          _lastDiagCache[hiveId] = entry.value['diagnosis'] as String?;
        }
      }
    } catch (_) {}
  }

  int _toSqliteId(String hiveId) {
    final match = RegExp(r'(\d+)').firstMatch(hiveId);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  String _toStringId(int sqliteId) {
    return 'P${sqliteId.toString().padLeft(3, '0')}';
  }

  PatientModel _rowToModel(Map<String, dynamic> row) {
    return PatientModel(
      id: row['sync_id'] as String? ?? _toStringId(Helpers.toInt(row['id'])),
      name: row['full_name'] as String? ?? '',
      dob: row['dob'] as String? ?? '',
      age: row['age'] as int? ?? 0,
      mobile: row['mobile_number'] as String? ?? '',
      address: row['address'] as String? ?? '',
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.now(),
      isSynced: false,
      gender: row['gender'] as String? ?? 'Not Specified',
      bloodGroup: row['blood_group'] as String? ?? 'Not Specified',
    );
  }
}

final Map<String, DateTime?> _lastVisitCache = {};
final Map<String, String?> _lastDiagCache = {};

extension PatientModelExtension on PatientModel {
  DateTime? get lastVisitDate => _lastVisitCache[id];
  String? get lastDiagnosis => _lastDiagCache[id];
}
