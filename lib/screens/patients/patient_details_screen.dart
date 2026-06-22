import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../../theme/app_theme.dart';
import '../../models/patient.dart';
import '../../models/patient_model.dart';
import '../../models/opd_record_model.dart';
import '../../models/prescription.dart';
import '../../providers/patient_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/standard_header.dart';
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

class PatientDetailsScreen extends StatelessWidget {
  final String patientId;
  const PatientDetailsScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsProvider>();
    final box = Hive.box<PatientModel>('patients');
    final pModel = box.values.cast<PatientModel?>().firstWhere(
      (p) => p?.id == patientId,
      orElse: () => null,
    );

    if (pModel == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            const StandardHeader(title: 'Patient Details', roundedCorners: false),
            const SliverFillRemaining(
              child: Center(child: Text('Patient not found')),
            ),
          ],
        ),
      );
    }

    final patient = PatientDetail(
      id: pModel.id,
      name: pModel.name,
      age: pModel.age,
      gender: pModel.gender.isNotEmpty ? pModel.gender : 'Unknown',
      mobile: pModel.mobile,
      dob: pModel.dob,
      bloodGroup: pModel.bloodGroup.isNotEmpty ? pModel.bloodGroup : 'Unknown',
      address: pModel.address,
    );

    final opdBox = Hive.box<OPDRecordModel>('opd_records');
    final records = opdBox.values
        .where((r) => r.patientId == patientId)
        .toList();
    records.sort((a, b) => b.visitDate.compareTo(a.visitDate));

    final visits = records.map((r) {
      final consultation = int.tryParse(r.consultationFee) ?? 0;
      final medicine = int.tryParse(r.medicineFee) ?? 0;
      final disc = int.tryParse(r.discount) ?? 0;
      final totalFee = consultation + medicine - disc;
      return VisitRecord(
        date: DateFormat('dd MMM yyyy').format(r.visitDate),
        type: r.type.isNotEmpty ? r.type : 'Consultation',
        diagnosis: r.diagnosis.isNotEmpty ? r.diagnosis : 'No diagnosis',
        notes: r.symptoms.isNotEmpty ? r.symptoms : 'No notes',
        fees: totalFee > 0 ? totalFee : 0,
      );
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const StandardHeader(
            title: 'Patient Details',
            roundedCorners: false,
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Header with patient profile
                Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(28),
                      bottomRight: Radius.circular(28),
                    ),
                    boxShadow: [...AppTheme.heavyShadow, ...AppTheme.subtleShadow],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
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
                                  _glassTile('Blood Group', patient.bloodGroup),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
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
                                onPressed: () =>
                                    context.go('/app/prescription/$patientId'),
                                icon: Icon(Icons.description, size: 20),
                                label: Text('View Prescription'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: Colors.white,
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
                                    final opdBox = Hive.box<OPDRecordModel>(
                                      'opd_records',
                                    );
                                    final records = opdBox.values
                                        .where((r) => r.patientId == patientId)
                                        .toList();
                                    records.sort(
                                      (a, b) => b.visitDate.compareTo(a.visitDate),
                                    );
                                    final latest = records.isNotEmpty
                                        ? records.first
                                        : null;
                                    final settings = context.read<SettingsProvider>();

                                    List<Medicine> medicines = [];
                                    if (latest != null && latest.medicines.isNotEmpty) {
                                      try {
                                        final decoded = _decodeMedicinesFromJson(latest.medicines);
                                        if (decoded.isNotEmpty) {
                                          medicines = decoded.map((m) => Medicine(
                                            name: m['name'] ?? '',
                                            dosage: m['dosage'] ?? '',
                                            duration: m['duration'] ?? '',
                                          )).toList();
                                        } else {
                                          medicines = latest.medicines.split(',')
                                              .where((s) => s.trim().isNotEmpty)
                                              .map((s) => Medicine(name: s.trim(), dosage: '', duration: ''))
                                              .toList();
                                        }
                                      } catch (_) {
                                        medicines = latest.medicines.split(',')
                                            .where((s) => s.trim().isNotEmpty)
                                            .map((s) => Medicine(name: s.trim(), dosage: '', duration: ''))
                                            .toList();
                                      }
                                    }

                                    final rx = Prescription(
                                      date: DateFormat('dd MMM yyyy').format(DateTime.now()),
                                      patientName: patient.name,
                                      patientId: patient.id,
                                      age: patient.age,
                                      gender: patient.gender,
                                      diagnosis: latest?.diagnosis ?? '',
                                      medicines: medicines,
                                      notes: latest?.clinicalNotes ?? '',
                                      nextVisit: latest?.nextVisit ?? '',
                                      doctorName: settings.doctorName,
                                      clinicName: settings.clinicName,
                                      clinicAddress: settings.clinicAddress,
                                      clinicPhone: settings.clinicPhone,
                                      licenseNo: settings.doctorLicense,
                                      patientMobile: patient.mobile,
                                    );

                                    final pdfData = await PrescriptionPdfService.generatePdf(rx, includePatientDetails: false);
                                    final normalizedPhone = Helpers.normalizePhone(patient.mobile);
                                    if (normalizedPhone.isEmpty) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Patient has no valid phone number'),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      return;
                                    }

                                    final tempDir = await getTemporaryDirectory();
                                    final safeName = patient.name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_');
                                    final pdfFile = File('${tempDir.path}/${safeName}_${patient.id}.pdf');
                                    await pdfFile.writeAsBytes(pdfData);

                                    if (!context.mounted) return;
                                    await WhatsAppShareHelper.shareToWhatsApp(
                                      pdfFile,
                                      phoneNumber: normalizedPhone,
                                    );

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('✓ WhatsApp opened with prescription attached'),
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
                                      content: Text('Delete ${patient.name} and all associated records?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          style: TextButton.styleFrom(
                                            foregroundColor: AppTheme.danger,
                                          ),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true && context.mounted) {
                                    await context.read<PatientProvider>().deletePatientAndRecords(patientId);
                                    if (context.mounted) {
                                      context.go('/app/patients');
                                    }
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.danger.withValues(alpha: 0.7),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  side: BorderSide(
                                    color: AppTheme.danger.withValues(alpha: 0.2),
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
