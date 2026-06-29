import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../theme/app_theme.dart';
import '../../widgets/standard_header.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/patient.dart';
import '../../widgets/section_card.dart';

import 'package:flutter/rendering.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  bool _showFab = true;
  
  late AnimationController _chartAnim;
  late AnimationController _listAnim;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final show = _scrollController.position.userScrollDirection == ScrollDirection.forward ||
          _scrollController.position.pixels < 50;
      if (show != _showFab) {
        setState(() => _showFab = show);
      }
    });

    _chartAnim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800)
    );

    _listAnim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600)
    );

    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _chartAnim.forward();
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _listAnim.forward();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _chartAnim.dispose();
    _listAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardProvider>();
    final settings = context.watch<SettingsProvider>();
    final appointments = context.watch<AppointmentProvider>();

    // Dynamic greeting based on time of day
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good Morning' : hour < 17 ? 'Good Afternoon' : 'Good Evening';

    // Dynamic date formatting
    final now = DateTime.now();
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final formattedDate = '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';

    // Calculate upcoming follow-ups from calendar appointments
    final upcomingFollowUps = appointments.upcomingFollowUps.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      dashboard.setFollowUpsDue(upcomingFollowUps);
    });

    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: AnimatedSlide(
        offset: _showFab ? Offset.zero : const Offset(0, 2.5),
        duration: const Duration(milliseconds: 300),
        curve: _showFab ? Curves.easeOutCubic : Curves.easeInCubic,
        child: AnimatedOpacity(
          opacity: _showFab ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          child: FloatingActionButton(
            backgroundColor: AppTheme.primary,
            onPressed: () => context.push('/app/opd/new'),
            child: Icon(Icons.add, color: AppTheme.textOnPrimary),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        backgroundColor: AppTheme.lightSurface,
        strokeWidth: 2.5,
        displacement: 60,
        onRefresh: () async {
          await dashboard.loadDashboardData();
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ═══════════════════════════════════════════════════
          // PREMIUM CLINICAL GRADIENT HEADER
          // ═══════════════════════════════════════════════════
          StandardHeader(
            title: '$greeting, ${settings.doctorName}',
          ),

          // DATE SUBTITLE
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Text(
                formattedDate,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ),

          // ═══════════════════════════════════════════════════
          // BODY SECTIONS (Scrollable)
          // ═══════════════════════════════════════════════════
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Visits Grid (3 cards)
                    _buildVisitsGrid(dashboard),
                    const SizedBox(height: 24),

                    // CLINIC OVERVIEW SECTION
                    _buildClinicOverview(context, dashboard),
                    const SizedBox(height: 24),

                    // REVENUE SPLIT
                    _buildRevenueSplit(dashboard),
                    const SizedBox(height: 24),

                    // RECENT PATIENTS
                    _buildRecentPatients(context, dashboard.recentPatients.take(5).toList()),

                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Clinic Overview Line Chart with Curved lines and grid
  Widget _buildClinicOverview(BuildContext context, DashboardProvider dashboard) {
    double maxCount = dashboard.opdTrendData
        .map((e) => e.count.toDouble())
        .fold(0.0, (max, count) => count > max ? count : max);

    double calculatedMaxY = maxCount > 0 ? (maxCount * 1.15).ceilToDouble() : 5.0;
    if (calculatedMaxY < 5) calculatedMaxY = 5;

    double yInterval = (calculatedMaxY / 4).ceilToDouble();
    if (yInterval < 1) yInterval = 1;
    calculatedMaxY = yInterval * 4;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Clinic Overview',
                style: AppTheme.subHeading.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              // Segmented control style — 3 small pill buttons
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  children: ['7 Days', '30 Days', '6 Months'].map((range) {
                    final isActive = dashboard.selectedRange == range;
                    return GestureDetector(
                      onTap: () => dashboard.setSelectedRange(range),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive ? AppTheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          range,
                          style: AppTheme.caption.copyWith(
                            color: isActive ? Colors.white : AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Line Chart
          SizedBox(
            height: 180,
            child: AnimatedBuilder(
              animation: _chartAnim,
              builder: (context, child) {
                return ClipRect(
                  clipper: _ChartClipper(
                    Curves.easeOutCubic.transform(_chartAnim.value)
                  ),
                  child: child,
                );
              },
              child: LineChart(
                LineChartData(
                  lineTouchData: const LineTouchData(enabled: true),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: yInterval,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: AppTheme.divider,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            value.toInt().toString(),
                            style: AppTheme.caption.copyWith(
                              fontSize: 10,
                              color: AppTheme.textHint,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < dashboard.opdTrendData.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                dashboard.opdTrendData[index].day,
                                style: AppTheme.caption.copyWith(
                                  fontSize: 10,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: dashboard.opdTrendData
                          .asMap()
                          .entries
                          .map((e) => FlSpot(e.key.toDouble(), e.value.count.toDouble()))
                          .toList(),
                      isCurved: true,
                      color: AppTheme.primary,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                          radius: 3,
                          color: AppTheme.primary,
                          strokeWidth: 0,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary.withValues(alpha: 0.15),
                            AppTheme.primary.withValues(alpha: 0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                  minY: 0,
                  maxY: calculatedMaxY,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Revenue split card
  Widget _buildRevenueSplit(DashboardProvider dashboard) {
    const colors = [AppTheme.primary, AppTheme.success];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Revenue Split',
                style: AppTheme.subHeading.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  children: ['Weekly', 'Monthly', 'Yearly'].map((period) {
                    final isActive = dashboard.revenuePeriod == period;
                    return GestureDetector(
                      onTap: () => dashboard.setRevenuePeriod(period),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive ? AppTheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          period,
                          style: AppTheme.caption.copyWith(
                            color: isActive ? Colors.white : AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 110,
                height: 110,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 28,
                    sections: dashboard.revenueSplit.asMap().entries.map((e) {
                      return PieChartSectionData(
                        value: e.value.value,
                        color: colors[e.key % colors.length],
                        radius: 18,
                        showTitle: false,
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    ...dashboard.revenueSplit.asMap().entries.map((e) {
                      final val = e.value.value;
                      final formatted = val >= 100000
                          ? '₹${(val / 100000).toStringAsFixed(1)}L'
                          : val >= 1000
                              ? '₹${(val / 1000).toStringAsFixed(1)}K'
                              : '₹${val.toInt()}';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: colors[e.key % colors.length],
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(e.value.name,
                                    style: AppTheme.caption.copyWith(color: AppTheme.textSecondary)),
                              ],
                            ),
                            Text(formatted,
                                style: AppTheme.caption.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary)),
                          ],
                        ),
                      );
                    }),
                    const Divider(),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total',
                            style: AppTheme.caption.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary)),
                        Text(dashboard.formattedRevenuePeriodTotal,
                            style: AppTheme.caption.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Recent Patients list with dividers
  Widget _buildRecentPatients(BuildContext context, List<Patient> recentPatientsList) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent OPD Activity',
                style: AppTheme.subHeading.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              GestureDetector(
                onTap: () => context.go('/app/patients'),
                child: Row(
                  children: [
                    Text(
                      'View All',
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward, size: 14, color: AppTheme.primary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recentPatientsList.isEmpty)
            _buildEmptyState('No recent patients found', Icons.people_outline),
          if (recentPatientsList.isNotEmpty)
            ...recentPatientsList.asMap().entries.map((entry) {
            final index = entry.key;
            final patient = entry.value;
            final isLast = index == recentPatientsList.length - 1;

            final delay = (index * 0.1).clamp(0.0, 0.5);

            return AnimatedBuilder(
              animation: _listAnim,
              builder: (context, child) {
                final progress = ((_listAnim.value - delay) / (1.0 - delay)).clamp(0.0, 1.0);
                final curve = Curves.easeOutCubic.transform(progress);
                return Opacity(
                  opacity: curve,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - curve)),
                    child: child,
                  ),
                );
              },
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => context.go('/app/patients/${patient.id}'),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Hero(
                            tag: 'patient_avatar_${patient.id}',
                            child: CircleAvatar(
                              radius: 22,
                              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                              child: Text(
                              patient.initial,
                              style: AppTheme.caption.copyWith(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  patient.name,
                                  style: AppTheme.body.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ID: ${patient.id} • Age ${patient.age}',
                                  style: AppTheme.caption.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(patient.gender).withValues(alpha: 0.1), // gender was hacked to store status
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  patient.gender.toUpperCase(),
                                  style: AppTheme.caption.copyWith(
                                    color: _getStatusColor(patient.gender),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Time: ${patient.lastVisit}',
                                style: AppTheme.caption.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!isLast) const Divider(height: 1, thickness: 0.8),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildVisitsGrid(DashboardProvider dashboard) {
    return Row(
      children: [
        Expanded(child: _buildVisitCard(
          icon: Icons.calendar_today,
          value: dashboard.todaysOpd.toString(),
          label: "Today's Visits",
          onTap: () => _showRevenueSheet(context, 'Today', dashboard.todaysRevenue),
        )),
        const SizedBox(width: 8),
        Expanded(child: _buildVisitCard(
          icon: Icons.date_range,
          value: dashboard.weeklyVisits.toString(),
          label: 'Weekly Visits',
          onTap: () => _showRevenueSheet(context, 'This Week', dashboard.weeklyRevenue),
        )),
        const SizedBox(width: 8),
        Expanded(child: _buildVisitCard(
          icon: Icons.calendar_month,
          value: dashboard.monthlyVisits.toString(),
          label: 'Monthly Visits',
          onTap: () => _showRevenueSheet(context, 'This Month', dashboard.monthlyRevenue),
        )),
        const SizedBox(width: 8),
        Expanded(child: _buildVisitCard(
          icon: Icons.repeat,
          value: dashboard.followUpsDue.toString(),
          label: 'Follow-ups Due',
          onTap: () => context.go('/app/calendar'),
        )),
      ],
    );
  }

  Widget _buildVisitCard({
    required IconData icon,
    required String value,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primary, size: 20),
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: AppTheme.display.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTheme.overline.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showRevenueSheet(BuildContext context, String period, String revenue) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textHint.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.currency_rupee, color: AppTheme.primary, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              '$period Revenue',
              style: AppTheme.subHeading.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              revenue,
              style: AppTheme.display.copyWith(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: AppTheme.textOnPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Generic empty state for lists
  Widget _buildEmptyState(String message, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: AppTheme.primary.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: AppTheme.body.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return AppTheme.success;
      case 'in progress':
        return AppTheme.primary;
      case 'cancelled':
        return AppTheme.danger;
      case 'waiting':
      default:
        return Colors.orange;
    }
  }
}

class _ChartClipper extends CustomClipper<Rect> {
  final double progress;
  _ChartClipper(this.progress);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * progress, size.height);
  }

  @override
  bool shouldReclip(_ChartClipper old) => old.progress != progress;
}
