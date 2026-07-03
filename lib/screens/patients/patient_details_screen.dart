import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../theme/app_theme.dart';
import '../../models/patient.dart';
import '../../models/prescription.dart';
import '../../models/appointment_model.dart';
import '../../providers/patient_provider.dart';
import '../../providers/settings_provider.dart';
import '../../repositories/patient_repository.dart';
import '../../repositories/opd_record_repository.dart';
import '../../repositories/patient_images_repository.dart';
import '../../widgets/standard_header.dart';
import '../../services/cloud_sync_manager.dart';
import '../../services/prescription_pdf_service.dart';
import '../../services/whatsapp_share_helper.dart';
import '../../utils/helpers.dart';
import '../../widgets/section_card.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/visit_timeline_item.dart';

List<Map<String, String?>> _decodeMedicinesFromJson(String json) {
  final decoded = jsonDecode(json);
  if (decoded is List) {
    return decoded
        .map(
          (e) => {
            'name': e['name']?.toString(),
            'dosage': e['dosage']?.toString(),
            'duration': e['duration']?.toString(),
          },
        )
        .toList();
  }
  return [];
}

class PatientDetailsScreen extends StatefulWidget {
  final String patientId;
  const PatientDetailsScreen({super.key, required this.patientId});

  @override
  State<PatientDetailsScreen> createState() => _PatientDetailsScreenState();
}

class _PatientDetailsScreenState extends State<PatientDetailsScreen> {
  PatientDetail? _patient;
  List<VisitRecord> _visits = [];
  List<Map<String, dynamic>> _opdRows = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final patientRepo = PatientRepository();
    var patientRow = await patientRepo.getBySyncId(widget.patientId);
    patientRow ??= await _getPatientByLocalId(patientRepo);

    if (patientRow == null) {
      if (mounted) setState(() => _loaded = true);
      return;
    }

    final sqliteId = patientRow['id'] as int;
    final displayId = (patientRow['sync_id'] as String?)?.isNotEmpty == true
        ? patientRow['sync_id'] as String
        : 'P${sqliteId.toString().padLeft(3, '0')}';

    _patient = PatientDetail(
      id: displayId,
      name: (patientRow['full_name'] as String?) ?? '',
      age: (patientRow['age'] as int?) ?? 0,
      gender: (patientRow['gender'] as String?) ?? '',
      mobile: (patientRow['mobile_number'] as String?) ?? '',
      dob: (patientRow['dob'] as String?) ?? '',
      bloodGroup: (patientRow['blood_group'] as String?) ?? '',
      address: (patientRow['address'] as String?) ?? '',
    );
    final opdRepo = OpdRecordRepository();
    _opdRows = await opdRepo.getByPatientId(sqliteId);
    _visits = _opdRows.map((r) {
      final consultation =
          int.tryParse(r['consultation_fee']?.toString() ?? '') ?? 0;
      final medicine = int.tryParse(r['medicine_fee']?.toString() ?? '') ?? 0;
      final disc = int.tryParse(r['discount_value']?.toString() ?? '') ?? 0;
      final totalFee = consultation + medicine - disc;
      final visitDateStr = r['visit_datetime'] as String? ?? '';
      DateTime visitDate;
      try {
        visitDate = DateTime.parse(visitDateStr);
      } catch (_) {
        visitDate = DateTime.now();
      }
      return VisitRecord(
        date: DateFormat('dd MMM yyyy').format(visitDate),
        type: ((r['opd_type'] as String?)?.isNotEmpty == true)
            ? r['opd_type'] as String
            : 'Consultation',
        diagnosis: ((r['diagnosis'] as String?)?.isNotEmpty == true)
            ? r['diagnosis'] as String
            : 'No diagnosis',
        notes: ((r['symptoms'] as String?)?.isNotEmpty == true)
            ? r['symptoms'] as String
            : 'No notes',
        fees: totalFee > 0 ? totalFee : 0,
      );
    }).toList();
    if (mounted) setState(() => _loaded = true);
  }

  Future<Map<String, dynamic>?> _getPatientByLocalId(
    PatientRepository patientRepo,
  ) async {
    final sqliteId =
        int.tryParse(widget.patientId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (sqliteId == 0) return null;
    return patientRepo.getById(sqliteId);
  }

  Future<void> _confirmDeleteOpd(int index) async {
    if (index >= _opdRows.length) return;
    final row = _opdRows[index];
    final opdId = row['opd_id'] as String? ?? '';
    final visitDate = row['visit_datetime'] as String? ?? '';
    if (opdId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete OPD Record'),
        content: Text('Delete OPD record from $visitDate?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final opdRepo = OpdRecordRepository();
    final localRow = await opdRepo.getByOpdId(opdId);
    if (localRow == null) return;

    final localId = localRow['id'] as int;

    // Clean up images
    final imagesRepo = PatientImagesRepository();
    await imagesRepo.deleteByOpdVisitId(localId);

    // Clean up Hive appointment
    final nextVisit = localRow['next_visit_date']?.toString() ?? '';
    if (nextVisit.isNotEmpty) {
      try {
        final apptBox = Hive.box<AppointmentModel>('appointments');
        final apptId = 'followup_${opdId}_$nextVisit';
        if (apptBox.containsKey(apptId)) {
          await apptBox.delete(apptId);
        }
      } catch (_) {}
    }

    // Clean up Hive document
    try {
      final docBox = Hive.box('opd_documents');
      if (docBox.containsKey(opdId)) {
        await docBox.delete(opdId);
      }
    } catch (_) {}

    // Delete from SQLite
    await opdRepo.delete(localId);

    // Notify cloud sync
    CloudSyncManager().notifyChange(
      tableName: 'opd_visits',
      operation: 'delete',
      recordId: opdId,
    );

    // Reload data
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsProvider>();

    if (!_loaded) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final patient = _patient;
    if (patient == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            const StandardHeader(
              title: 'Patient Details',
              roundedCorners: false,
            ),
            const SliverFillRemaining(
              child: Center(child: Text('Patient not found')),
            ),
          ],
        ),
      );
    }

    final visits = _visits;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const StandardHeader(title: 'Patient Details', roundedCorners: false),
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Header with patient profile
                Transform.translate(
                  offset: const Offset(0, -1),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(28),
                        bottomRight: Radius.circular(28),
                      ),
                      boxShadow: [
                        ...AppTheme.heavyShadow,
                        ...AppTheme.subtleShadow,
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 28),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Hero(
                                      tag: 'patient_avatar_${patient.id}',
                                      child: CircleAvatar(
                                        radius: 40,
                                        backgroundColor: Colors.white,
                                        child: Text(
                                          patient.initial,
                                          style: TextStyle(
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            patient.name,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            '${patient.id} • ${patient.gender}',
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.8,
                                              ),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 16),
                                Row(
                                  children: [
                                    _glassTile('Age', '${patient.age} years'),
                                    SizedBox(width: 12),
                                    _glassTile(
                                      'Blood Group',
                                      patient.bloodGroup,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Contact Info
                      AnimatedListItem(
                        index: 0,
                        child: SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Contact Information',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              SizedBox(height: 16),
                              _contactRow(
                                Icons.phone,
                                'Mobile Number',
                                patient.mobile,
                              ),
                              SizedBox(height: 12),
                              _contactRow(
                                Icons.location_on,
                                'Address',
                                patient.address,
                              ),
                              SizedBox(height: 12),
                              _contactRow(
                                Icons.calendar_today,
                                'Date of Birth',
                                patient.dob,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      // Visit History
                      AnimatedListItem(
                        index: 1,
                        child: SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Visit History',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              SizedBox(height: 16),
                              ...visits.asMap().entries.map(
                                (e) => VisitTimelineItem(
                                  visit: e.value,
                                  isLast: e.key == visits.length - 1,
                                  onDelete: () => _confirmDeleteOpd(e.key),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      AnimatedListItem(
                        index: 2,
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: ElevatedButton.icon(
                                onPressed: () => context.go(
                                  '/app/prescription/${widget.patientId}',
                                ),
                                icon: Icon(Icons.description, size: 20),
                                label: Text('View Prescription'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: Colors.white,
                                  surfaceTintColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  try {
                                    final latest = _opdRows.isNotEmpty
                                        ? _opdRows.first
                                        : null;
                                    final settings = context
                                        .read<SettingsProvider>();

                                    List<Medicine> medicines = [];
                                    if (latest != null &&
                                        (latest['medicines'] as String? ?? '')
                                            .isNotEmpty) {
                                      try {
                                        final decoded =
                                            _decodeMedicinesFromJson(
                                              (latest['medicines'] as String? ??
                                                  ''),
                                            );
                                        if (decoded.isNotEmpty) {
                                          medicines = decoded
                                              .map(
                                                (m) => Medicine(
                                                  name: m['name'] ?? '',
                                                  dosage: m['dosage'] ?? '',
                                                  duration: m['duration'] ?? '',
                                                ),
                                              )
                                              .toList();
                                        } else {
                                          medicines =
                                              (latest['medicines'] as String? ??
                                                      '')
                                                  .split(',')
                                                  .where(
                                                    (s) => s.trim().isNotEmpty,
                                                  )
                                                  .map(
                                                    (s) => Medicine(
                                                      name: s.trim(),
                                                      dosage: '',
                                                      duration: '',
                                                    ),
                                                  )
                                                  .toList();
                                        }
                                      } catch (_) {
                                        medicines =
                                            (latest['medicines'] as String? ??
                                                    '')
                                                .split(',')
                                                .where(
                                                  (s) => s.trim().isNotEmpty,
                                                )
                                                .map(
                                                  (s) => Medicine(
                                                    name: s.trim(),
                                                    dosage: '',
                                                    duration: '',
                                                  ),
                                                )
                                                .toList();
                                      }
                                    }

                                    final rx = Prescription(
                                      date: DateFormat(
                                        'dd MMM yyyy',
                                      ).format(DateTime.now()),
                                      patientName: patient.name,
                                      patientId: patient.id,
                                      age: patient.age,
                                      gender: patient.gender,
                                      diagnosis:
                                          latest?['diagnosis'] as String? ?? '',
                                      medicines: medicines,
                                      notes:
                                          latest?['clinical_notes']
                                              as String? ??
                                          '',
                                      nextVisit:
                                          latest?['next_visit_date']
                                              as String? ??
                                          '',
                                      doctorName: settings.doctorName,
                                      clinicName: settings.clinicName,
                                      clinicAddress: settings.clinicAddress,
                                      clinicPhone: settings.clinicPhone,
                                      licenseNo: settings.doctorLicense,
                                      patientMobile: patient.mobile,
                                    );

                                    final pdfData =
                                        await PrescriptionPdfService.generatePdf(
                                          rx,
                                          includePatientDetails: false,
                                        );
                                    final normalizedPhone =
                                        Helpers.normalizePhone(patient.mobile);
                                    if (normalizedPhone.isEmpty) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Patient has no valid phone number',
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      return;
                                    }

                                    final tempDir =
                                        await getTemporaryDirectory();
                                    final safeName = patient.name
                                        .replaceAll(RegExp(r'[^\w\s-]'), '')
                                        .replaceAll(RegExp(r'\s+'), '_');
                                    final pdfFile = File(
                                      '${tempDir.path}/${safeName}_${patient.id}.pdf',
                                    );
                                    await pdfFile.writeAsBytes(pdfData);

                                    if (!context.mounted) return;
                                    await WhatsAppShareHelper.shareToWhatsApp(
                                      pdfFile,
                                      phoneNumber: normalizedPhone,
                                    );

                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '✓ WhatsApp opened with prescription attached',
                                        ),
                                        backgroundColor: AppTheme.success,
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 4),
                                      ),
                                    );
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: AppTheme.danger,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                                icon: Icon(Icons.share, size: 20),
                                label: Text('Share'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: Colors.white,
                                  surfaceTintColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              flex: 1,
                              child: OutlinedButton(
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete Patient'),
                                      content: Text(
                                        'Delete ${patient.name} and all associated records?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          style: TextButton.styleFrom(
                                            foregroundColor: AppTheme.danger,
                                          ),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true && context.mounted) {
                                    await context
                                        .read<PatientProvider>()
                                        .deletePatientAndRecords(
                                          widget.patientId,
                                        );
                                    if (context.mounted) {
                                      context.go('/app/patients');
                                    }
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.danger.withValues(
                                    alpha: 0.7,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  side: BorderSide(
                                    color: AppTheme.danger.withValues(
                                      alpha: 0.2,
                                    ),
                                    width: 1.5,
                                  ),
                                  elevation: 0,
                                ),
                                child: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
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

  Widget _glassTile(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
            SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.primary, size: 20),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
          ),
        ),
      ],
    );
  }
}
