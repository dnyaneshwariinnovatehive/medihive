import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/opd_provider.dart';
import '../../providers/patient_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/appointment_provider.dart';
import '../../widgets/standard_header.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/section_card.dart';
import '../../widgets/chip_selector.dart';
import '../../widgets/scrollable_date_picker.dart';
import '../../widgets/medi_chip_input_field.dart';
import '../../widgets/chip_input_field.dart';
import '../../widgets/shake_widget.dart';
import '../../widgets/animated_button.dart';
import '../../widgets/success_overlay.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../utils/medical_data.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../repositories/opd_record_repository.dart';
import '../../repositories/patient_repository.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;

class OpdRegistrationScreen extends StatefulWidget {
  final String? editPatientId;
  final String? editOpdId;
  const OpdRegistrationScreen({super.key, this.editPatientId, this.editOpdId});

  @override
  State<OpdRegistrationScreen> createState() => _OpdRegistrationScreenState();
}

class _OpdRegistrationScreenState extends State<OpdRegistrationScreen> {
  // GlobalKeys for Step Forms
  final List<GlobalKey<FormState>> _formKeys = List.generate(
    3,
    (_) => GlobalKey<FormState>(),
  );
  final _scrollController = ScrollController();
  TextEditingController? _autocompleteController;
  String? _documentPath;
  Uint8List? _documentBytes;
  bool _showFab = true;

  // Shake animation triggers for Step 0 (Patient Information)
  bool _shakeName = false;
  bool _shakeDob = false;
  bool _shakeMobile = false;
  bool _shakeAddress = false;
  bool _isSubmitting = false;
  bool _hasTriedSubmit = false;
  Timer? _lookupDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final show =
          _scrollController.position.userScrollDirection ==
          ScrollDirection.forward;
      if (show != _showFab) {
        setState(() => _showFab = show);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<OpdProvider>();
      if (widget.editPatientId != null && widget.editPatientId!.isNotEmpty) {
        p.loadPatientForEdit(widget.editPatientId!, opdId: widget.editOpdId);
      } else {
        p.loadDraftFromHive();
      }
      if (p.hasDraft) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Resuming saved draft — ${p.patientName}'),
            action: SnackBarAction(label: 'Discard', onPressed: p.clearDraft),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  int calculateAge(DateTime dob) {
    final today = DateTime.now();
    int years = today.year - dob.year;
    if (today.month < dob.month ||
        (today.month == dob.month && today.day < dob.day)) {
      years--;
    }
    return years;
  }

  String formatAgeString(DateTime dob) {
    final today = DateTime.now();
    int years = today.year - dob.year;
    int months = today.month - dob.month;
    if (months < 0 || (months == 0 && today.day < dob.day)) {
      years--;
      months += 12;
    }
    if (today.day < dob.day) {
      months--;
    }
    if (months < 0) {
      months = 11;
    }
    return "Age: $years years $months months";
  }

  void _onMobileChanged(OpdProvider opd, String value) {
    final normalized = Helpers.normalizePhone(value);
    final fieldValue = normalized.isNotEmpty ? normalized : value;
    opd.updateField('mobile', fieldValue);
    _lookupDebounce?.cancel();
    if (normalized.length == 10) {
      _lookupDebounce = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        opd.searchPatientsByMobile(normalized);
      });
    } else {
      opd.clearMobileLookup();
    }
  }

  Widget _buildMobileLookup(OpdProvider opd) {
    final patients = opd.matchedPatients;
    final isSingle = patients.length == 1;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(76)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (patients.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                isSingle ? '' : 'Available Patients',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            ...patients.asMap().entries.map((entry) {
              final patient = entry.value;
              final name = patient['full_name']?.toString() ?? '';
              final gender = patient['gender']?.toString() ?? '';
              final ageStr = _formatLookupAge(patient);
              final dobStr = _formatLookupDob(patient);
              return InkWell(
                onTap: () => opd.autoFillFromPatient(patient),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppTheme.primary.withAlpha(30),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$gender${ageStr.isNotEmpty ? ' | $ageStr' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (dobStr.isNotEmpty)
                        Text(
                          dobStr,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
            const Divider(height: 1, thickness: 1),
          ],
          InkWell(
            onTap: () => opd.selectNewPatientRegistration(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.person_add_outlined, size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Register New Patient',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatLookupAge(Map<String, dynamic> patient) {
    final age = patient['age'];
    if (age == null) return '';
    final ageStr = age.toString();
    if (ageStr.contains('yr') || ageStr.contains('mo')) return ageStr;
    final ageNum = int.tryParse(ageStr);
    if (ageNum != null) return '$ageNum yrs';
    return ageStr;
  }

  String _formatLookupDob(Map<String, dynamic> patient) {
    final dob = patient['dob']?.toString() ?? '';
    if (dob.isEmpty) return '';
    final date = DateTime.tryParse(dob);
    if (date != null) {
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    }
    return dob;
  }

  bool _validateStep1(OpdProvider opd) {
    bool isValid = true;
    bool shouldScroll = false;
    _hasTriedSubmit = true;

    if (opd.formData.name.trim().isEmpty) {
      isValid = false;
      shouldScroll = true;
      setState(() => _shakeName = true);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _shakeName = false);
      });
    }
    if (opd.formData.dob.trim().isEmpty) {
      isValid = false;
      shouldScroll = true;
      setState(() => _shakeDob = true);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _shakeDob = false);
      });
    }
    if (opd.formData.mobile.trim().isEmpty ||
        opd.formData.mobile.trim().replaceAll(RegExp(r'[^0-9]'), '').length !=
            10) {
      isValid = false;
      shouldScroll = true;
      setState(() => _shakeMobile = true);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _shakeMobile = false);
      });
    }
    if (opd.formData.address.trim().isEmpty) {
      isValid = false;
      shouldScroll = true;
      setState(() => _shakeAddress = true);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _shakeAddress = false);
      });
    }

    if (shouldScroll) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }

    // Trigger form validation to display standard inline help errors
    _formKeys[0].currentState?.validate();

    return isValid;
  }

  Widget buildRequiredLabel(String name) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            TextSpan(
              text: ' *',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsProvider>();
    final opd = context.watch<OpdProvider>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final provider = context.read<OpdProvider>();
        if (!provider.hasUnsavedData) {
          Navigator.of(context).pop();
          return;
        }
        await showModalBottomSheet(
          context: context,
          builder: (_) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Save Draft'),
                leading: const Icon(Icons.save, color: Colors.orange),
                onTap: () {
                  provider.saveDraft();
                  Navigator.pop(context); // close sheet
                  Navigator.pop(context); // exit form
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Draft saved successfully')),
                  );
                },
              ),
              ListTile(
                title: const Text('Discard'),
                leading: const Icon(Icons.delete, color: Colors.red),
                onTap: () {
                  provider.clearDraft();
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Continue Editing'),
                leading: const Icon(Icons.edit),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  const StandardHeader(title: 'OPD Registration'),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: MediStepProgressIndicator(
                        currentStep: opd.currentStep,
                        stepLabels: const [
                          'Patient Information',
                          'Medical & Clinical Details',
                          'Billing & Payment',
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKeys[opd.currentStep],
                        child: _buildStepContent(opd, context, opd.currentStep),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(top: BorderSide(color: AppTheme.border)),
                boxShadow: AppTheme.cardShadow,
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    if (opd.currentStep > 0) ...[
                      Expanded(
                        child: AnimatedButton(
                          onTap: () {
                            opd.previousStep();
                            _scrollController.animateTo(
                              0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.primary,
                                width: 2,
                              ),
                            ),
                            child: const Text(
                              'Previous',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: AnimatedButton(
                        onTap: () async {
                          // Perform validation for current step
                          if (opd.currentStep == 0) {
                            if (!_validateStep1(opd)) return;
                          } else {
                            if (!(_formKeys[opd.currentStep].currentState
                                    ?.validate() ??
                                false)) {
                              return;
                            }
                          }

                          if (opd.currentStep < 2) {
                            opd.nextStep();
                            _scrollController.animateTo(
                              0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          } else {
                            if (_isSubmitting) return;
                            setState(() => _isSubmitting = true);
                            print('OPD SAVE START');
                            try {
                              await context
                                  .read<PatientProvider>()
                                  .addPatientFromOpd(opd.formData);
                              if (!context.mounted) return;
                              final patientNameForNotification =
                                  opd.formData.name;
                              // Find existing record ID if editing
                              String? existingId;
                              print('OPD SAVE: editPatientId="${widget.editPatientId}" editOpdId="${widget.editOpdId}"');
                              if (widget.editOpdId != null &&
                                  widget.editOpdId!.isNotEmpty) {
                                existingId = widget.editOpdId;
                                print('OPD SAVE: using direct editOpdId=$existingId');
                              } else if (widget.editPatientId != null &&
                                  widget.editPatientId!.isNotEmpty) {
                                final patientSyncId = widget.editPatientId!;
                                final patientRepo = PatientRepository();
                                final patient =
                                    await patientRepo.getBySyncId(patientSyncId);
                                if (patient != null) {
                                  final sqlitePatientId = Helpers.toInt(patient['id']);
                                  final opdRepo = OpdRecordRepository();
                                  final records = await opdRepo
                                      .getByPatientId(sqlitePatientId);
                                  print('OPD SAVE: patientRecords=${records.length}');
                                  if (records.isNotEmpty) {
                                    final firstOpdId =
                                        records.first['opd_id']?.toString();
                                    print(
                                        'OPD SAVE: firstRecord opd_id=$firstOpdId');
                                    if (firstOpdId != null &&
                                        firstOpdId.isNotEmpty) {
                                      existingId = firstOpdId;
                                    } else {
                                      print(
                                          'OPD SAVE WARNING: first record has null/empty opd_id');
                                    }
                                  } else {
                                    print(
                                        'OPD SAVE WARNING: no OPD records found for patient sqlitePatientId=$sqlitePatientId');
                                  }
                                } else {
                                  print(
                                      'OPD SAVE WARNING: patient not found by syncId=$patientSyncId');
                                }
                              } else {
                                print(
                                    'OPD SAVE: editPatientId is null/empty — will CREATE new OPD');
                              }
                              print('OPD SAVE: existingId=$existingId');
                              if (!context.mounted) return;
                              final success = await opd.submitRecord(
                                dashboardProvider: context
                                    .read<DashboardProvider>(),
                                appointmentProvider: context
                                    .read<AppointmentProvider>(),
                                existingRecordId: existingId,
                                documentBytes: _documentBytes,
                              );
                              if (!success) {
                                setState(() => _isSubmitting = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to save record. Please try again.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                                return;
                              }
                              if (context.mounted) {
                                context.read<NotificationProvider>().addNotification(
                                  'OPD Record Saved',
                                  'Patient $patientNameForNotification record saved',
                                );
                              }
                            } catch (e) {
                              setState(() => _isSubmitting = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to save OPD record: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                              rethrow;
                            }

                            if (!context.mounted) return;
                            showGeneralDialog(
                              context: context,
                              barrierColor: Colors.black.withValues(
                                alpha: 0.45,
                              ),
                              barrierDismissible: false,
                              pageBuilder: (dialogContext, __, ___) =>
                                  SuccessOverlay(
                                    title: 'Record Saved!',
                                    subtitle: 'Patient added successfully',
                                    onComplete: () {
                                      Navigator.of(
                                        dialogContext,
                                        rootNavigator: true,
                                      ).pop();
                                      Future.delayed(Duration.zero, () {
                                        _isSubmitting = false;
                                        opd.clearDraft();
                                        if (context.mounted) {
                                          context.pop();
                                        }
                                      });
                                    },
                                  ),
                            );
                          }
                        },
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (opd.currentStep == 2)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8.0),
                                  child: Icon(
                                    Icons.save,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                ),
                              Text(
                                opd.currentStep < 2
                                    ? 'Next Step'
                                    : 'Save OPD Record',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(OpdProvider opd, BuildContext context, int index) {
    switch (index) {
      case 0:
        return _buildStep1(opd, context);
      case 1:
        return _buildStep2(opd, context);
      case 2:
        return _buildStep3(opd);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep1(OpdProvider opd, BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Patient Information',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ShakeWidget(
            shake: _shakeMobile,
            child: _textField(
              'Mobile Number',
              'Enter mobile number',
              opd.formData.mobile,
              (v) => _onMobileChanged(opd, v),
              keyboardType: TextInputType.phone,
              isRequired: true,
              prefixIcon: Icons.phone_outlined,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Mobile number is required';
                }
                final numStr = value.trim().replaceAll(RegExp(r'[^0-9]'), '');
                if (numStr.length != 10) {
                  return 'Enter exactly 10 digits';
                }
                return null;
              },
            ),
          ),
          if (opd.showMobileLookup) _buildMobileLookup(opd),
          const SizedBox(height: 16),
          ShakeWidget(
            shake: _shakeName,
            child: _textField(
              'Full Name',
              'Enter patient name',
              opd.formData.name,
              (v) => opd.updateField('name', v),
              isRequired: true,
              textInputAction: TextInputAction.done,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Full name is required';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShakeWidget(
                      shake: _shakeDob,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () async {
                              final initial = DateTime.tryParse(
                                opd.formData.dob,
                              );
                              final picked = await showScrollableDatePicker(
                                context: context,
                                initialDate: initial,
                                firstDate: DateTime(1900),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                final iso =
                                    '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                final today = DateTime.now();
                                int years = today.year - picked.year;
                                int months = today.month - picked.month;
                                if (months < 0 ||
                                    (months == 0 && today.day < picked.day)) {
                                  years--;
                                  months += 12;
                                }
                                if (today.day < picked.day) {
                                  months--;
                                }
                                if (months < 0) {
                                  months = 11;
                                }
                                opd.setDob(iso);
                                opd.setAge('$years yr $months mo');
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    color: AppTheme.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Date of Birth *',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _hasTriedSubmit && opd.formData.dob.isEmpty
                                                ? AppTheme.danger
                                                : AppTheme.textSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Builder(
                                          builder: (context) {
                                            final date = DateTime.tryParse(
                                              opd.formData.dob,
                                            );
                                            final display = date != null
                                                ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'
                                                : '';
                                            return Text(
                                              opd.formData.dob.isEmpty
                                                  ? 'Tap to select date'
                                                  : display,
                                              style: AppTheme.body.copyWith(
                                                color: opd.formData.dob.isEmpty
                                                    ? AppTheme.textHint
                                                    : AppTheme.textPrimary,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.calendar_month_outlined,
                                    color: AppTheme.primary,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (opd.formData.dob.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Builder(
                              builder: (context) {
                                final dobDate = DateTime.tryParse(
                                  opd.formData.dob,
                                );
                                if (dobDate != null) {
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Text(
                                      formatAgeString(dobDate),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _textField(
                      'Age',
                      'Years/Months',
                      opd.formData.age,
                      (v) => opd.updateField('age', v),
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          final numStr = value.replaceAll(
                            RegExp(r'[^0-9]'),
                            '',
                          );
                          if (numStr.isNotEmpty &&
                              (int.tryParse(numStr) ?? -1) < 0) {
                            return 'Invalid age';
                          }
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _label('Gender'),
          ChipSelector(
            options: AppConstants.genders,
            selected: opd.formData.gender,
            onSelected: (v) => opd.updateField('gender', v),
          ),
          const SizedBox(height: 16),
          ShakeWidget(
            shake: _shakeAddress,
            child: _textField(
              'Address',
              'Enter full address',
              opd.formData.address,
              (v) => opd.updateField('address', v),
              maxLines: 3,
              isRequired: true,
              textInputAction: TextInputAction.done,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Address is required';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 16),
          _label('Blood Group'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: opd.formData.bloodGroup,
                items: AppConstants.bloodGroups
                    .map((bg) => DropdownMenuItem(value: bg, child: Text(bg)))
                    .toList(),
                onChanged: (v) => opd.updateField('bloodGroup', v ?? 'O+'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2(OpdProvider opd, BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_outlined,
                color: AppTheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Medical & Clinical Details',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          MediChipInputField(
            label: 'Diagnosis',
            hint: 'Search or add diagnosis...',
            suggestions: MedicalData.diagnoses,
            initialValue: opd.formData.diagnosis,
            onChanged: (v) => opd.updateField('diagnosis', v),
          ),
          const SizedBox(height: 16),
          ChipInputField(
            label: 'Symptoms',
            suggestions: kSymptoms,
            selectedItems: opd.selectedSymptoms,
            onChanged: opd.setSelectedSymptoms,
          ),
          const SizedBox(height: 16),
          _label('Upload Documents (Optional)'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final ImagePicker picker = ImagePicker();
                final XFile? image = await picker.pickImage(
                  source: ImageSource.gallery,
                );
                if (image != null) {
                  final bytes = await image.readAsBytes();
                  setState(() {
                    _documentPath = image.path;
                    _documentBytes = bytes;
                  });
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Document uploaded successfully!'),
                      backgroundColor: AppTheme.success,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Failed to pick document: $e'),
                    backgroundColor: AppTheme.danger,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: _documentPath == null
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      border: Border.all(color: AppTheme.border, width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          size: 32,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to upload documents',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      border: Border.all(color: AppTheme.success, width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: (kIsWeb || _documentBytes != null)
                              ? Image.memory(
                                  _documentBytes!,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                )
                              : Image.file(
                                  File(_documentPath!),
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'document_${DateTime.now().millisecondsSinceEpoch}.jpg',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textPrimary,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Ready for submission',
                                style: TextStyle(
                                  color: AppTheme.success,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: AppTheme.danger,
                          ),
                          onPressed: () {
                            setState(() {
                              _documentPath = null;
                              _documentBytes = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          _textField(
            'Clinical Notes',
            'Enter observations and notes',
            opd.formData.clinicalNotes,
            (v) => opd.updateField('clinicalNotes', v),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          _textField(
            'Panchakarma Notes',
            'Enter Panchakarma treatment notes',
            opd.formData.panchakarmaNotes,
            (v) => opd.updateField('panchakarmaNotes', v),
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          _label('OPD Type'),
          ChipSelector(
            options: const ['Consultation', 'Follow-up'],
            selected: opd.visitType == 'follow_up'
                ? 'Follow-up'
                : 'Consultation',
            onSelected: (v) {
              opd.visitType = v == 'Follow-up' ? 'follow_up' : 'consultation';
            },
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: opd.visitType == 'follow_up'
                ? Column(
                    key: const ValueKey('follow_up_fields'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () async {
                          final initial = DateTime.tryParse(
                            opd.formData.previousVisitDate,
                          );
                          final picked = await showScrollableDatePicker(
                            context: context,
                            initialDate: initial,
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            opd.previousVisitDate = picked;
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                color: AppTheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    final date = DateTime.tryParse(
                                      opd.formData.previousVisitDate,
                                    );
                                    final display = date != null
                                        ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'
                                        : '';
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Previous Visit Date',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          opd.formData.previousVisitDate.isEmpty
                                              ? 'Tap to select date'
                                              : display,
                                          style: AppTheme.body.copyWith(
                                            color:
                                                opd
                                                    .formData
                                                    .previousVisitDate
                                                    .isEmpty
                                                ? AppTheme.textHint
                                                : AppTheme.textPrimary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              Icon(
                                Icons.calendar_month_outlined,
                                color: AppTheme.primary,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _textField(
                        'Follow-up Reason',
                        'Enter reason for follow-up...',
                        opd.followUpReason,
                        (v) => opd.followUpReason = v,
                      ),
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('no_follow_up')),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Icon(
                Icons.medication_outlined,
                color: AppTheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Prescriptions',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Autocomplete<Map<String, String>>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              final query = textEditingValue.text.toLowerCase();
              if (query.isEmpty) {
                return const Iterable<Map<String, String>>.empty();
              }
              final matches = kMedicines
                  .where((med) => med['name']!.toLowerCase().contains(query))
                  .toList();

              if (query.isNotEmpty &&
                  !matches.any((m) => m['name']!.toLowerCase() == query)) {
                matches.add({'name': textEditingValue.text, 'type': 'Custom'});
              }
              return matches;
            },
            displayStringForOption: (option) => option['name']!,
            fieldViewBuilder:
                (context, textEditingController, focusNode, onFieldSubmitted) {
                  _autocompleteController = textEditingController;
                  return TextFormField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      labelText: 'Prescribe Medicine',
                      hintText: 'Type medicine name to search...',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      filled: true,
                      fillColor: AppTheme.surface,
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppTheme.primary,
                        size: 20,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                  );
                },
            optionsViewBuilder: (context, onSelected, options) {
              final grouped = <String, List<Map<String, String>>>{};
              for (final opt in options) {
                grouped.putIfAbsent(opt['type']!, () => []).add(opt);
              }

              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4.0,
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: 250,
                      maxWidth: MediaQuery.of(context).size.width - 32,
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: grouped.length,
                      itemBuilder: (context, index) {
                        final type = grouped.keys.elementAt(index);
                        final meds = grouped[type]!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              width: double.infinity,
                              child: Text(
                                type,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            ...meds.map(
                              (med) => ListTile(
                                dense: true,
                                title: Text(
                                  med['name']!,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  med['type']!,
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                onTap: () => onSelected(med),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              );
            },
            onSelected: (option) {
              final newList = List<Map<String, dynamic>>.from(
                opd.prescribedMedicines,
              );
              newList.add({
                'name': option['name'],
                'type': option['type'],
                'dosage': kDosageOptions.first,
              });
              opd.setPrescribedMedicines(newList);
              _autocompleteController?.clear();
            },
          ),
          if (opd.prescribedMedicines.isNotEmpty) ...[
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: opd.prescribedMedicines.length,
              itemBuilder: (context, index) {
                final item = opd.prescribedMedicines[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  color: AppTheme.surfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: AppTheme.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${item['name']} ${item['type'] != null && item['type'].toString().isNotEmpty ? '— ${item['type']}' : ''}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: AppTheme.danger,
                                size: 20,
                              ),
                              onPressed: () {
                                final newList = List<Map<String, dynamic>>.from(
                                  opd.prescribedMedicines,
                                );
                                newList.removeAt(index);
                                opd.setPrescribedMedicines(newList);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue:
                              kDosageOptions.contains(item['dosage'])
                              ? item['dosage']
                              : kDosageOptions.first,
                          decoration: const InputDecoration(
                            labelText: 'Dosage',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                          ),
                          items: kDosageOptions
                              .map(
                                (d) => DropdownMenuItem(
                                  value: d,
                                  child: Text(
                                    d,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              final newList =
                                  List<Map<String, dynamic>>.from(
                                    opd.prescribedMedicines,
                                  );
                              newList[index]['dosage'] = val;
                              opd.setPrescribedMedicines(newList);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final initial = DateTime.tryParse(opd.formData.nextVisit);
              final picked = await showScrollableDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime.now(),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                final iso =
                    '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                opd.updateField('nextVisit', iso);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final date = DateTime.tryParse(opd.formData.nextVisit);
                        final display = date != null
                            ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'
                            : '';
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Next Visit Date',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              opd.formData.nextVisit.isEmpty
                                  ? 'Tap to select date'
                                  : display,
                              style: AppTheme.body.copyWith(
                                color: opd.formData.nextVisit.isEmpty
                                    ? AppTheme.textHint
                                    : AppTheme.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Icon(
                    Icons.calendar_month_outlined,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3(OpdProvider opd) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attach_money, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Billing & Payment',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Consultation Fee *
          _textField(
            'Consultation Fees',
            '0',
            opd.formData.consultationFee,
            (v) => opd.updateField('consultationFee', v),
            keyboardType: TextInputType.number,
            isRequired: true,
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Required';
              if (double.tryParse(value.trim()) == null) {
                return 'Must be a valid number';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Medicine Fee
          _textField(
            'Medicine Fee',
            '0',
            opd.formData.medicineFee,
            (v) => opd.updateField('medicineFee', v),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),

          // Panchakarma Fee
          _textField(
            'Panchakarma Fee',
            '0',
            opd.formData.panchakarmaFee,
            (v) => opd.updateField('panchakarmaFee', v),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),

          // Discount Type Dropdown
          _label('Discount Type'),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: opd.formData.discountType,
            decoration: InputDecoration(
              labelText: 'Discount Type',
              labelStyle: TextStyle(color: AppTheme.textSecondary),
              filled: true,
              fillColor: AppTheme.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.primary, width: 2),
              ),
            ),
            dropdownColor: AppTheme.surface,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: 16,
            ),
            items: const [
              DropdownMenuItem(value: 'None', child: Text('None')),
              DropdownMenuItem(value: '₹', child: Text('₹ (Amount)')),
              DropdownMenuItem(value: '%', child: Text('% (Percentage)')),
            ],
            onChanged: (v) {
              if (v != null) opd.updateField('discountType', v);
            },
          ),
          const SizedBox(height: 16),

          // Discount Value (enabled only when discount type is not None)
          _textField(
            'Discount Value',
            '0',
            opd.formData.discount,
            (v) => opd.updateField('discount', v),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),

          // Total Fee (read-only, auto-calculated)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppTheme.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Subtotal',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '₹${opd.formData.subtotal.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                if (opd.formData.discountType != 'None' && (double.tryParse(opd.formData.discount) ?? 0) > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Discount (${opd.formData.discountType})',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '-₹${opd.formData.discountType == '%'
                            ? ((opd.formData.subtotal * (double.tryParse(opd.formData.discount) ?? 0) / 100).toStringAsFixed(0))
                            : opd.formData.discount}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Amount',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '₹${opd.formData.totalFee.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Payment Mode
          _label('Payment Mode'),
          ChipSelector(
            options: AppConstants.paymentModes,
            selected: opd.formData.paymentMode,
            onSelected: (v) => opd.updateField('paymentMode', v),
          ),
          const SizedBox(height: 16),

          // Charge Type
          _label('Charge Type'),
          ChipSelector(
            options: AppConstants.chargeTypes,
            selected: opd.formData.chargeType,
            onSelected: (v) => opd.updateField('chargeType', v),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _textField(
    String label,
    String hint,
    String value,
    ValueChanged<String> onChanged, {
    int maxLines = 1,
    TextInputType? keyboardType,
    IconData? prefixIcon,
    bool isRequired = false,
    String? Function(String?)? validator,
    TextInputAction? textInputAction,
  }) {
    return TextFormField(
      controller: TextEditingController(text: value)
        ..selection = TextSelection.collapsed(offset: value.length),
      onChanged: onChanged,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: textInputAction == TextInputAction.done
          ? (_) => FocusScope.of(context).unfocus()
          : null,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      validator: validator,
      style: const TextStyle(fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        labelStyle: TextStyle(
          color: isRequired && _hasTriedSubmit && value.isEmpty
              ? AppTheme.danger
              : AppTheme.textSecondary,
        ),
        hintText: hint,
        hintStyle: TextStyle(color: AppTheme.textTertiary),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        filled: true,
        fillColor: AppTheme.surface,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: AppTheme.primary, size: 20)
            : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.danger, width: 2),
        ),
      ),
    );
  }
}

// ─── STEP PROGRESS INDICATOR ─────────────────────────────────
class MediStepProgressIndicator extends StatefulWidget {
  final int currentStep;
  final List<String> stepLabels;

  const MediStepProgressIndicator({
    super.key,
    required this.currentStep,
    required this.stepLabels,
  });

  @override
  State<MediStepProgressIndicator> createState() =>
      _MediStepProgressIndicatorState();
}

class _MediStepProgressIndicatorState extends State<MediStepProgressIndicator>
    with TickerProviderStateMixin {
  late AnimationController _springController;
  late Animation<double> _labelAnim;
  String _displayedLabel = '';

  @override
  void initState() {
    super.initState();
    _displayedLabel = widget.stepLabels[widget.currentStep];
    _springController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _labelAnim = CurvedAnimation(
      parent: _springController,
      curve: Curves.elasticOut,
    );
    _springController.value = 1.0;
  }

  @override
  void didUpdateWidget(MediStepProgressIndicator old) {
    super.didUpdateWidget(old);
    if (widget.currentStep != old.currentStep) {
      setState(() {
        _displayedLabel = widget.stepLabels[widget.currentStep];
      });
      _springController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int totalSteps = widget.stepLabels.length;
    final int currentStep = widget.currentStep;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step ${currentStep + 1} of $totalSteps',
                style: AppTheme.label.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.primary,
                ),
              ),
              AnimatedBuilder(
                animation: _labelAnim,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 0.9 + (_labelAnim.value * 0.1),
                    child: child,
                  );
                },
                child: Text(
                  _displayedLabel,
                  style: AppTheme.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final double width = constraints.maxWidth;

              return SizedBox(
                height: 34,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(1),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOutCubic,
                          height: 2,
                          width:
                              (width - 28) *
                              (totalSteps > 1
                                  ? currentStep / (totalSteps - 1)
                                  : 1),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(totalSteps, (index) {
                        final bool isCompleted = index < currentStep;
                        final bool isActive = index == currentStep;
                        return AnimatedScale(
                          scale: isActive ? 1.0 : 0.85,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.elasticOut,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            width: isActive ? 34 : 28,
                            height: isActive ? 34 : 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isCompleted
                                  ? AppTheme.primary
                                  : isActive
                                  ? AppTheme.cardBg
                                  : AppTheme.surfaceVariant,
                              border: Border.all(
                                color: isCompleted || isActive
                                    ? AppTheme.primary
                                    : AppTheme.divider,
                                width: isActive ? 2.5 : 2,
                              ),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.primary.withValues(
                                          alpha: 0.25,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(scale: anim, child: child),
                                child: isCompleted
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 16,
                                        key: ValueKey('check'),
                                      )
                                    : Text(
                                        '${index + 1}',
                                        key: ValueKey('num_$index'),
                                        style: TextStyle(
                                          fontSize: isActive ? 13 : 12,
                                          fontWeight: FontWeight.bold,
                                          color: isActive
                                              ? AppTheme.primary
                                              : AppTheme.textTertiary,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
