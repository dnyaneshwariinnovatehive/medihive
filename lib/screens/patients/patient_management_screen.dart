import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../providers/patient_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/patient.dart';
import '../../repositories/opd_record_repository.dart';
import '../../repositories/patient_repository.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/pressable_card.dart';
import '../../utils/helpers.dart';
import '../../widgets/standard_header.dart';

class PatientManagementScreen extends StatefulWidget {
  const PatientManagementScreen({super.key});

  @override
  State<PatientManagementScreen> createState() =>
      _PatientManagementScreenState();
}

class _PatientManagementScreenState extends State<PatientManagementScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showFab = true;
  DateTime _selectedDate = DateTime.now();
  Set<String> _datePatientIds = {};

  void _onPatientProviderChanged() {
    if (mounted) {
      _loadDateRecords();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<PatientProvider>();
      provider.loadPatients();
      provider.addListener(_onPatientProviderChanged);
      _loadDateRecords();
    });
    _scrollController.addListener(() {
      final show =
          _scrollController.position.userScrollDirection ==
          ScrollDirection.forward;
      if (show != _showFab) {
        setState(() => _showFab = show);
      }
    });
  }

  @override
  void dispose() {
    try {
      context.read<PatientProvider>().removeListener(_onPatientProviderChanged);
    } catch (_) {}
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildInfoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          fontSize: 11,
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  Future<void> _loadDateRecords() async {
    try {
      final opdRepo = OpdRecordRepository();
      final rows = await opdRepo.getByDate(_selectedDate);
      if (rows.isEmpty) {
        _datePatientIds = {};
      } else {
        final patientIds = rows
            .map((r) => Helpers.toInt(r['patient_id']))
            .toSet()
            .toList();
        final patientRepo = PatientRepository();
        final patientRows = await Future.wait(
          patientIds.map(patientRepo.getById),
        );
        _datePatientIds = patientRows
            .whereType<Map<String, dynamic>>()
            .map<String>(
              (r) =>
                  r['sync_id']?.toString() ??
                  'P${Helpers.toInt(r['id']).toString().padLeft(3, '0')}',
            )
            .where((id) => id.isNotEmpty)
            .toSet();
      }
    } catch (_) {
      _datePatientIds = {};
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadDateRecords();
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsProvider>();
    final provider = context.watch<PatientProvider>();
    final allPatients = provider.filteredPatients;
    final dateFilteredPatients = allPatients
        .where((p) => _datePatientIds.contains(p.id))
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ═══════════════════════════════════════════════════
          // PREMIUM GRADIENT HEADER
          // ═══════════════════════════════════════════════════
          const StandardHeader(title: 'Patient Management'),

          // PATIENT COUNT
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Text(
                '${dateFilteredPatients.length} Patient${dateFilteredPatients.length == 1 ? '' : 's'}',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ),
          ),

          // ═══════════════════════════════════════════════════
          // DATE PICKER
          // ═══════════════════════════════════════════════════
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.calendar_month_rounded,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat(
                                'EEEE, d MMMM yyyy',
                              ).format(_selectedDate),
                              style: AppTheme.body.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              _isToday ? 'Today' : 'Selected date',
                              style: AppTheme.caption.copyWith(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down,
                        color: AppTheme.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ═══════════════════════════════════════════════════
          // PATIENTS LIST / EMPTY STATES
          // ═══════════════════════════════════════════════════
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Builder(
                builder: (context) {
                  if (dateFilteredPatients.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.people_outline,
                              size: 48,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _isToday
                                ? 'No Patients Yet'
                                : 'No Patients on This Date',
                            style: AppTheme.heading.copyWith(
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_isToday) ...[
                            Text(
                              'Add your first patient via OPD Registration',
                              style: AppTheme.body.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () => context.go('/app/opd'),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('New OPD'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  } else {
                    final patientList = dateFilteredPatients;
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: ListView.builder(
                        key: ValueKey<String>(provider.searchQuery),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: patientList.length,
                        itemBuilder: (context, index) {
                          final Patient patient = patientList[index];
                          final name = patient.name;
                          final id = patient.id;
                          final age = patient.age;
                          final gender = patient.gender;
                          final lastDiagnosis = patient.diagnosis.isNotEmpty
                              ? patient.diagnosis
                              : 'No diagnosis';
                          final lastVisitDate = patient.lastVisit;

                          return AnimatedListItem(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: PressableCard(
                                onTap: () => context.go('/app/patients/$id'),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppTheme.cardBg,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: AppTheme.cardShadow,
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Hero(
                                        tag: 'patient_avatar_$id',
                                        child: CircleAvatar(
                                          radius: 24,
                                          backgroundColor: AppTheme.primary
                                              .withValues(alpha: 0.12),
                                          child: Text(
                                            name.isNotEmpty
                                                ? name
                                                      .substring(0, 1)
                                                      .toUpperCase()
                                                : 'P',
                                            style: TextStyle(
                                              color: AppTheme.primary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: AppTheme.body.copyWith(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: _buildInfoChip(
                                                    'ID: $id',
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: _buildInfoChip(
                                                    'Age: $age',
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: _buildInfoChip(gender),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              lastDiagnosis,
                                              style: AppTheme.caption.copyWith(
                                                color: AppTheme.textSecondary,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            lastVisitDate,
                                            style: AppTheme.caption.copyWith(
                                              color: AppTheme.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              GestureDetector(
                                                onTap: () => context.go(
                                                  '/app/patients/$id',
                                                ),
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.primary
                                                        .withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Icon(
                                                    Icons.visibility_outlined,
                                                    size: 16,
                                                    color: AppTheme.primary,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              GestureDetector(
                                                onTap: () => context.go(
                                                  '/app/patients/$id/edit',
                                                ),
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.warning
                                                        .withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Icon(
                                                    Icons.edit_outlined,
                                                    size: 16,
                                                    color: AppTheme.warning,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _isToday
          ? AnimatedSlide(
              offset: _showFab ? Offset.zero : const Offset(0, 2.5),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: FloatingActionButton(
                onPressed: () => context.go('/app/opd'),
                backgroundColor: AppTheme.primary,
                child: const Icon(Icons.add, color: Colors.white, size: 28),
              ),
            )
          : null,
    );
  }
}
