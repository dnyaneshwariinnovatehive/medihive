import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';

import '../../theme/app_theme.dart';
import '../../models/prescription.dart';
import '../../providers/settings_provider.dart';
import '../../repositories/patient_repository.dart';
import '../../repositories/opd_record_repository.dart';
import '../../repositories/sync_queue_repository.dart';
import '../../services/sync_manager.dart';
import '../../utils/helpers.dart';
import '../../utils/sync_id_generator.dart';
import '../../widgets/standard_header.dart';
import '../../services/prescription_pdf_service.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/section_card.dart';

class _MedicineFieldData {
  final TextEditingController name;
  final TextEditingController dosage;
  final TextEditingController duration;
  _MedicineFieldData({
    String name = '',
    String dosage = 'As directed',
    String duration = '-',
  }) : name = TextEditingController(text: name),
       dosage = TextEditingController(text: dosage),
       duration = TextEditingController(text: duration);

  Medicine toMedicine() => Medicine(
    name: name.text.trim(),
    dosage: dosage.text.trim(),
    duration: duration.text.trim(),
  );

  void dispose() {
    name.dispose();
    dosage.dispose();
    duration.dispose();
  }
}

class PrescriptionScreen extends StatefulWidget {
  final String patientId;
  const PrescriptionScreen({super.key, required this.patientId});

  @override
  State<PrescriptionScreen> createState() => _PrescriptionScreenState();
}

class _PrescriptionScreenState extends State<PrescriptionScreen> {
  bool _isEditing = false;
  bool _dataLoaded = false;
  bool _hasError = false;
  String _errorMessage = '';
  late TextEditingController _diagnosisController;
  late TextEditingController _notesController;
  late TextEditingController _panchakarmaNotesController;
  late TextEditingController _nextVisitController;
  late List<_MedicineFieldData> _medicineFields;
  late Map<String, dynamic> _latestRecord;
  late Prescription _rx;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadData();
    });
  }

  Future<void> _loadData() async {
    try {
      final patientRepo = PatientRepository();
      var patientRow = await patientRepo.getBySyncId(widget.patientId);

      int sqliteId;
      if (patientRow != null) {
        sqliteId = Helpers.toInt(patientRow['id']);
      } else {
        sqliteId = int.tryParse(widget.patientId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (sqliteId > 0) {
          patientRow = await patientRepo.getById(sqliteId);
        }
      }

      if (patientRow == null || sqliteId == 0) {
        _hasError = true;
        _errorMessage = 'Patient not found';
        _dataLoaded = true;
        if (mounted) setState(() {});
        return;
      }

      final opdRepo = OpdRecordRepository();
      final records = await opdRepo.getByPatientId(sqliteId);

      if (records.isEmpty) {
        _hasError = true;
        _errorMessage = 'No prescription records found for this patient';
        _dataLoaded = true;
        if (mounted) setState(() {});
        return;
      }

      _latestRecord = records.first;
      if (!mounted) return;
      final settings = context.read<SettingsProvider>();

      final medRaw = _latestRecord['medicines'] as String? ?? '';
      final List<Medicine> medList = [];
      if (medRaw.isNotEmpty) {
        try {
          final decoded = _decodeMedicines(medRaw);
          if (decoded.isNotEmpty) {
            medList.addAll(decoded);
          } else {
            final parts = medRaw.split(',');
            for (var part in parts) {
              if (part.trim().isNotEmpty) {
                medList.add(
                  Medicine(
                    name: part.trim(),
                    dosage: 'As directed',
                    duration: '-',
                  ),
                );
              }
            }
          }
        } catch (_) {
          final parts = medRaw.split(',');
          for (var part in parts) {
            if (part.trim().isNotEmpty) {
              medList.add(
                Medicine(name: part.trim(), dosage: 'As directed', duration: '-'),
              );
            }
          }
        }
      }

      final visitDtStr = _latestRecord['visit_datetime'] as String? ?? '';
      final visitDate = DateTime.tryParse(visitDtStr) ?? DateTime.now();
      final diagnosis = _latestRecord['diagnosis'] as String? ?? '';
      final symptoms = _latestRecord['symptoms'] as String? ?? '';
      final panchakarmaNotes = _latestRecord['panchakarma_notes'] as String? ?? '';
      final nextVisit = _latestRecord['next_visit_date'] as String? ?? '';
      final patientName = patientRow['full_name'] as String? ?? '';
      final patientSyncId = patientRow['sync_id'] as String? ?? '';
      final patientIdStr = patientSyncId.isNotEmpty ? patientSyncId : 'P$sqliteId';
      final patientAge = patientRow['age'] as int? ?? 0;
      final patientGender = patientRow['gender'] as String? ?? '';
      final patientMobile = patientRow['mobile_number'] as String? ?? '';

      _rx = Prescription(
        date: DateFormat('dd MMM yyyy').format(visitDate),
        patientName: patientName,
        patientId: patientIdStr,
        age: patientAge,
        gender: patientGender.isNotEmpty ? patientGender : 'Unknown',
        diagnosis: diagnosis.isNotEmpty ? diagnosis : 'Consultation',
        medicines: medList,
        notes: symptoms.isNotEmpty ? symptoms : 'No specific instructions.',
        panchakarmaNotes: panchakarmaNotes,
        nextVisit: nextVisit.isNotEmpty ? nextVisit : 'As required',
        doctorName: settings.doctorName.isNotEmpty
            ? settings.doctorName
            : 'Dr. Rajas Gavas',
        doctorQualification: settings.doctorSpecialty,
        clinicName: settings.clinicName.isNotEmpty
            ? settings.clinicName
            : 'Shree Clinic',
        clinicAddress: settings.clinicAddress.isNotEmpty
            ? settings.clinicAddress
            : 'Nirman bhavan, near Milagris school, Sawantwadi',
        clinicPhone: settings.clinicPhone.isNotEmpty
            ? settings.clinicPhone
            : '9067251670',
        licenseNo: settings.doctorLicense.isNotEmpty
            ? settings.doctorLicense
            : 'I-107200-A',
        patientMobile: patientMobile.isNotEmpty ? patientMobile : '',
        clinicLogoPath: settings.clinicLogoPath,
      );

      _diagnosisController = TextEditingController(text: _rx.diagnosis);
      _notesController = TextEditingController(text: _rx.notes);
      _panchakarmaNotesController = TextEditingController(text: _rx.panchakarmaNotes);
      _nextVisitController = TextEditingController(text: _rx.nextVisit);
      _initMedicineFields();
    } catch (e) {
      _hasError = true;
      _errorMessage = 'Failed to load prescription: $e';
    }
    _dataLoaded = true;
    if (mounted) setState(() {});
  }

  void _initMedicineFields() {
    _medicineFields = _rx.medicines
        .map(
          (m) => _MedicineFieldData(
            name: m.name,
            dosage: m.dosage,
            duration: m.duration,
          ),
        )
        .toList();
    if (_medicineFields.isEmpty) {
      _medicineFields.add(_MedicineFieldData());
    }
  }

  @override
  void dispose() {
    _diagnosisController.dispose();
    _notesController.dispose();
    _panchakarmaNotesController.dispose();
    _nextVisitController.dispose();
    for (final f in _medicineFields) {
      f.dispose();
    }
    super.dispose();
  }

  List<Medicine> _decodeMedicines(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map(
              (e) => Medicine(
                name: e['name'] ?? '',
                dosage: e['dosage'] ?? 'As directed',
                duration: e['duration'] ?? '-',
              ),
            )
            .toList();
      }
    } catch (_) {}
    return [];
  }

  void _toggleEdit() {
    if (_isEditing) {
      setState(() => _isEditing = false);
    } else {
      _initMedicineFields();
      setState(() => _isEditing = true);
    }
  }

  Future<void> _saveChanges() async {
    final newDiagnosis = _diagnosisController.text.trim();
    final newNotes = _notesController.text.trim();
    final newPanchakarmaNotes = _panchakarmaNotesController.text.trim();
    final newNextVisit = _nextVisitController.text.trim();
    final newMedicinesList = _medicineFields
        .map((f) => f.toMedicine())
        .where((m) => m.name.isNotEmpty)
        .toList();
    final newMedicinesRaw = newMedicinesList.map((m) => m.name).join(', ');

    final opdRepo = OpdRecordRepository();
    final updatedRow = Map<String, dynamic>.from(_latestRecord);
    updatedRow['diagnosis'] = newDiagnosis.isNotEmpty
        ? newDiagnosis
        : (_latestRecord['diagnosis'] as String? ?? '');
    updatedRow['symptoms'] = newNotes.isNotEmpty
        ? newNotes
        : (_latestRecord['symptoms'] as String? ?? '');
    updatedRow['medicines'] = newMedicinesRaw.isNotEmpty
        ? newMedicinesRaw
        : (_latestRecord['medicines'] as String? ?? '');
    updatedRow['panchakarma_notes'] = newPanchakarmaNotes.isNotEmpty
        ? newPanchakarmaNotes
        : (_latestRecord['panchakarma_notes'] as String? ?? '');
    updatedRow['next_visit_date'] = newNextVisit.isNotEmpty
        ? newNextVisit
        : (_latestRecord['next_visit_date'] as String? ?? '');

    try {
      await opdRepo.update(Helpers.toInt(_latestRecord['id']), updatedRow);

      final syncQueueRepo = SyncQueueRepository();
      await syncQueueRepo.insert({
        'id': SyncIdGenerator.nextId(),
        'entity_type': 'opd_visit',
        'entity_id': _latestRecord['opd_id'] as String,
        'status': 'pending',
        'retry_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      });

      Future.microtask(() {
        SyncManager().forceSyncNow();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save prescription: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    _latestRecord = updatedRow;

    final updatedRx = Prescription(
      date: _rx.date,
      patientName: _rx.patientName,
      patientId: _rx.patientId,
      age: _rx.age,
      gender: _rx.gender,
      diagnosis: newDiagnosis.isNotEmpty ? newDiagnosis : _rx.diagnosis,
      medicines: newMedicinesList.isNotEmpty ? newMedicinesList : _rx.medicines,
      notes: newNotes.isNotEmpty ? newNotes : _rx.notes,
      panchakarmaNotes: newPanchakarmaNotes.isNotEmpty ? newPanchakarmaNotes : _rx.panchakarmaNotes,
      nextVisit: newNextVisit.isNotEmpty ? newNextVisit : _rx.nextVisit,
      doctorName: _rx.doctorName,
      doctorQualification: _rx.doctorQualification,
      clinicName: _rx.clinicName,
      clinicAddress: _rx.clinicAddress,
      clinicPhone: _rx.clinicPhone,
      licenseNo: _rx.licenseNo,
      clinicLogoPath: _rx.clinicLogoPath,
    );
    _rx = updatedRx;

    setState(() => _isEditing = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Prescription saved'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _addMedicine() {
    setState(() {
      _medicineFields.add(_MedicineFieldData());
    });
  }

  void _removeMedicine(int index) {
    setState(() {
      _medicineFields[index].dispose();
      _medicineFields.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_dataLoaded) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            const StandardHeader(title: 'Prescription', showBack: true),
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      );
    }

    if (_hasError) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            const StandardHeader(title: 'Prescription', showBack: true),
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 64,
                        color: AppTheme.textHint,
                      ),
                      SizedBox(height: 16),
                      Text(
                        _errorMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          StandardHeader(
            title: 'Prescription',
            showBack: true,
            onBack: () => context.go('/app/patients/${widget.patientId}'),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Text(
                _rx.date,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      AnimatedListItem(
                        index: 0,
                        child: SectionCard(
                          shadows: AppTheme.heavyShadow,
                          child: Column(
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(20),
                                decoration: const BoxDecoration(
                                  gradient: AppTheme.primaryGradient,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _rx.clinicName,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      _rx.clinicAddress,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.85,
                                        ),
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                    SizedBox(height: 14),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.phone,
                                              color: Colors.white.withValues(
                                                alpha: 0.7,
                                              ),
                                              size: 14,
                                            ),
                                            SizedBox(width: 6),
                                            Text(
                                              _rx.clinicPhone,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.badge_outlined,
                                              color: Colors.white.withValues(
                                                alpha: 0.7,
                                              ),
                                              size: 14,
                                            ),
                                            SizedBox(width: 6),
                                            Text(
                                              'Lic: ${_rx.licenseNo}',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _rx.doctorName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 18,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: _toggleEdit,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _isEditing
                                                  ? AppTheme.primary.withValues(
                                                      alpha: 0.1,
                                                    )
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: _isEditing
                                                    ? AppTheme.primary
                                                        .withValues(alpha: 0.3)
                                                    : AppTheme.border,
                                              ),
                                            ),
                                            child: Icon(
                                              Icons.edit_outlined,
                                              color: AppTheme.primary,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: AppTheme.surfaceVariant,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _infoCol(
                                                  'Patient Name',
                                                  _rx.patientName,
                                                ),
                                              ),
                                              Expanded(
                                                child: _infoCol(
                                                  'Patient ID',
                                                  _rx.patientId,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _infoCol(
                                                  'Age / Gender',
                                                  '${_rx.age} / ${_rx.gender}',
                                                ),
                                              ),
                                              Expanded(
                                                child: _isEditing
                                                    ? Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            'Diagnosis',
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              color: AppTheme
                                                                  .textSecondary,
                                                            ),
                                                          ),
                                                          SizedBox(height: 2),
                                                          TextField(
                                                            controller:
                                                                _diagnosisController,
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              color: AppTheme
                                                                  .textPrimary,
                                                              fontSize: 13,
                                                            ),
                                                            decoration: InputDecoration(
                                                              isDense: true,
                                                              contentPadding:
                                                                  EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        8,
                                                                    vertical: 6,
                                                                  ),
                                                              border: OutlineInputBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      6,
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      )
                                                    : _infoCol(
                                                        'Diagnosis',
                                                        _rx.diagnosis,
                                                      ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      AnimatedListItem(
                        index: 1,
                        child: SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle('Medicines Prescribed'),
                              SizedBox(height: 12),
                              if (_isEditing)
                                ..._medicineFields.asMap().entries.map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppTheme.surfaceVariant,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                'Medicine ${e.key + 1}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.textPrimary,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              Spacer(),
                                              GestureDetector(
                                                onTap: () =>
                                                    _removeMedicine(e.key),
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.danger
                                                        .withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Icon(
                                                    Icons.delete_outline,
                                                    color: AppTheme.danger,
                                                    size: 16,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 8),
                                          TextField(
                                            controller: e.value.name,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              color: AppTheme.textPrimary,
                                              fontSize: 13,
                                            ),
                                            decoration: InputDecoration(
                                              labelText: 'Medicine Name',
                                              isDense: true,
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                          SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller: e.value.dosage,
                                                  style: TextStyle(
                                                    color: AppTheme.textPrimary,
                                                    fontSize: 13,
                                                  ),
                                                  decoration: InputDecoration(
                                                    labelText: 'Dosage',
                                                    isDense: true,
                                                    contentPadding:
                                                        EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 8,
                                                        ),
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),

                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              else
                                ..._rx.medicines.asMap().entries.map(
                                  (e) => Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceVariant,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${e.key + 1}. ${e.value.name}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        _infoCol('Dosage', e.value.dosage),
                                      ],
                                    ),
                                  ),
                                ),
                              if (_isEditing)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: OutlinedButton.icon(
                                    onPressed: _addMedicine,
                                    icon: Icon(Icons.add, size: 16),
                                    label: Text(
                                      'Add Medicine',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.primary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      side: BorderSide(
                                        color: AppTheme.primary.withValues(
                                          alpha: 0.4,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      AnimatedListItem(
                        index: 2,
                        child: SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle('Instructions'),
                              SizedBox(height: 8),
                              if (_isEditing)
                                TextField(
                                  controller: _notesController,
                                  maxLines: 3,
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 13,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.all(12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: AppTheme.surfaceTint,
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceTint,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _rx.notes,
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                              SizedBox(height: 12),
                              _sectionTitle('Panchakarma Notes'),
                              SizedBox(height: 8),
                              if (_isEditing)
                                TextField(
                                  controller: _panchakarmaNotesController,
                                  maxLines: 3,
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 13,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.all(12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: AppTheme.surfaceTint,
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceTint,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _rx.panchakarmaNotes.isNotEmpty
                                        ? _rx.panchakarmaNotes
                                        : 'No Panchakarma notes',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                              SizedBox(height: 16),
                              if (_isEditing)
                                TextField(
                                  controller: _nextVisitController,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 18,
                                    color: AppTheme.primary,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Next Visit',
                                    isDense: true,
                                    contentPadding: EdgeInsets.all(12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: AppTheme.primary.withValues(
                                      alpha: 0.1,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        AppTheme.primary.withValues(alpha: 0.1),
                                        AppTheme.primaryLight.withValues(
                                          alpha: 0.1,
                                        ),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Next Visit',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        _rx.nextVisit,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: AppTheme.border,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    'This is a computer-generated prescription',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: OutlinedButton.icon(
                              onPressed: _isEditing
                                  ? _saveChanges
                                  : () {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Tap the edit icon to make changes',
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                    },
                              icon: Icon(Icons.save_outlined, size: 18),
                              label: Text('Save'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: AppTheme.primary,
                                  width: 1.5,
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            flex: 1,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                try {
                                  final pdfData =
                                      await PrescriptionPdfService
                                          .generatePdf(_rx);
                                  final dir =
                                      await getApplicationDocumentsDirectory();
                                  final docDir = Directory(
                                    '${dir.path}/Prescriptions',
                                  );
                                  if (!await docDir.exists()) {
                                    await docDir.create(recursive: true);
                                  }
                                  final safeName = _rx.patientName
                                      .replaceAll(RegExp(r'[^\w\s-]'), '')
                                      .replaceAll(RegExp(r'\s+'), '_')
                                      .trim()
                                      .replaceAll(RegExp(r'_+'), '_');
                                  final safeId = _rx.patientId
                                      .replaceAll(RegExp(r'[^\w]'), '');
                                  final file = File(
                                    '${docDir.path}/${safeName}_$safeId.pdf',
                                  );
                                  await file.writeAsBytes(pdfData);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Saved to ${file.path}',
                                      ),
                                      backgroundColor: AppTheme.success,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error saving prescription: $e',
                                      ),
                                    ),
                                  );
                                }
                              },
                              icon: Icon(Icons.download, size: 18),
                              label: Text('Download'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: AppTheme.primary,
                                  width: 1.5,
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            flex: 1,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                try {
                                  final pdfData =
                                      await PrescriptionPdfService
                                          .generatePdf(_rx);
                                  await Printing.layoutPdf(
                                    onLayout: (_) => pdfData,
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error printing prescription: $e',
                                      ),
                                    ),
                                  );
                                }
                              },
                              icon: Icon(Icons.print, size: 18),
                              label: Text('Print'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: AppTheme.primary,
                                  width: 1.5,
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 80),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCol(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
      ),
      SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: AppTheme.textPrimary,
        ),
      ),
    ],
  );

  Widget _sectionTitle(String title) => Row(
    children: [
      Container(
        width: 4,
        height: 20,
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      SizedBox(width: 8),
      Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
    ],
  );
}
