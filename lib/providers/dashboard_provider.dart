import 'package:flutter/material.dart';
import '../models/collection_item.dart';
import '../models/patient.dart';
import '../repositories/opd_record_repository.dart';
import '../repositories/patient_repository.dart';
import '../utils/helpers.dart';

class DashboardProvider extends ChangeNotifier {
  final OpdRecordRepository _opdRepo = OpdRecordRepository();
  final PatientRepository _patientRepo = PatientRepository();

  String _selectedRange = '7 Days';
  String get selectedRange => _selectedRange;

  DateTimeRange? _customDateRange;
  DateTimeRange? get customDateRange => _customDateRange;

  String _revenuePeriod = 'Monthly';
  String get revenuePeriod => _revenuePeriod;

  // Active Dynamic Stats States
  int _todaysOpd = 0;
  int get todaysOpd => _todaysOpd;

  String _todaysRevenue = '₹0';
  String get todaysRevenue => _todaysRevenue;

  List<Patient> _recentPatients = [];
  List<Patient> get recentPatients => _recentPatients;

  // Cached SQLite rows (populated by loadDashboardData)
  List<Map<String, dynamic>> _allOpdRows = [];
  List<Map<String, dynamic>> _allPatientRows = [];

  DashboardProvider() {
    loadDashboardData();
  }

  Future<void> refresh() async {
    await loadDashboardData();
  }

  /// Calculates dynamic clinic summaries and charts from SQLite
  Future<void> loadDashboardData() async {
    try {
      _allOpdRows = await _opdRepo.getAll();
      _allPatientRows = await _patientRepo.getAll();
      final today = DateTime.now();

      // 1. Today's OPD count
      _todaysOpd = _allOpdRows.where((r) {
        final vd = _parseDateTime(r['visit_datetime']);
        return vd != null && _isSameDay(vd, today);
      }).length;

      // 2. Today's revenue
      final todayRecords = _allOpdRows.where((r) {
        final vd = _parseDateTime(r['visit_datetime']);
        return vd != null && _isSameDay(vd, today);
      });
      double todayRev = 0;
      for (final r in todayRecords) {
        todayRev += _extractFeeFromRow(r);
      }
      _todaysRevenue = '₹${todayRev.toInt().toString()}';

      // 4. Recent OPD Records: last 5 sorted by visit_datetime descending
      _recentPatients = _buildRecentPatients();

      notifyListeners();
    } catch (_) {
      // Graceful fallback during startup
    }
  }

  List<Patient> _buildRecentPatients() {
    final seenIds = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final r in _allOpdRows) {
      final opdId = r['opd_id']?.toString() ?? '';
      if (seenIds.add(opdId)) {
        unique.add(r);
      }
    }
    unique.sort((a, b) {
      final aDate = _parseDateTime(a['visit_datetime']);
      final bDate = _parseDateTime(b['visit_datetime']);
      return (bDate ?? DateTime.now()).compareTo(aDate ?? DateTime.now());
    });
    return unique.take(5).map((opd) {
      final pid = Helpers.toInt(opd['patient_id']);
      final patient = _allPatientRows.cast<Map<String, dynamic>?>().firstWhere(
        (p) => p?['id'] == pid,
        orElse: () => null,
      );
      final visitDt = _parseDateTime(opd['visit_datetime']);
      final timeStr = visitDt != null
          ? '${visitDt.hour.toString().padLeft(2, '0')}:${visitDt.minute.toString().padLeft(2, '0')}'
          : '00:00';
      final status = opd['opd_type']?.toString() ?? 'waiting';
      return Patient(
        id: _toStringId(pid),
        name: patient?['full_name']?.toString() ?? 'Unknown Patient',
        age: patient?['age'] as int? ?? 0,
        gender: status,
        mobile: patient?['mobile_number']?.toString() ?? '',
        lastVisit: timeStr,
        dob: '',
        visitCount: 1,
        diagnosis: '',
      );
    }).toList();
  }

  double _extractFeeFromRow(Map<String, dynamic> row) {
    final consultation = (row['consultation_fee'] as num?)?.toDouble() ?? 0;
    final medicine = (row['medicine_fee'] as num?)?.toDouble() ?? 0;
    final disc = (row['discount_value'] as num?)?.toDouble() ?? 0;
    final total = consultation + medicine - disc;
    final opdType = row['opd_type']?.toString() ?? '';
    return total > 0 ? total : (opdType == 'follow_up' ? 200.0 : 500.0);
  }

  void setRevenuePeriod(String period) {
    _revenuePeriod = period;
    notifyListeners();
  }

  void setSelectedRange(String range, {DateTimeRange? customRange}) {
    _selectedRange = range;
    _customDateRange = customRange;
    notifyListeners();
  }

  // ─── Dynamic Revenue Period Split ──────────────────────────
  List<RevenueData> get revenueSplit {
    try {
      final today = DateTime.now();

      List<Map<String, dynamic>> filtered = [];
      if (_revenuePeriod == 'Weekly') {
        final startOfWeek = today.subtract(Duration(days: today.weekday));
        filtered = _allOpdRows.where((r) {
          final vd = _parseDateTime(r['visit_datetime']);
          return vd != null && !vd.isBefore(startOfWeek);
        }).toList();
      } else if (_revenuePeriod == 'Yearly') {
        filtered = _allOpdRows.where((r) {
          final vd = _parseDateTime(r['visit_datetime']);
          return vd != null && vd.year == today.year;
        }).toList();
      } else {
        filtered = _allOpdRows.where((r) {
          final vd = _parseDateTime(r['visit_datetime']);
          return vd != null && vd.year == today.year && vd.month == today.month;
        }).toList();
      }

      final consultRecords = filtered.where((r) => r['opd_type']?.toString() != 'follow_up');
      final followRecords = filtered.where((r) => r['opd_type']?.toString() == 'follow_up');

      double consultRevenue = 0;
      for (final r in consultRecords) {
        consultRevenue += _extractFeeFromRow(r);
      }
      double followRevenue = 0;
      for (final r in followRecords) {
        followRevenue += _extractFeeFromRow(r);
      }

      return [
        RevenueData(name: 'Consultation', value: consultRevenue),
        RevenueData(name: 'Follow-up', value: followRevenue),
      ];
    } catch (_) {
      return const [
        RevenueData(name: 'Consultation', value: 0),
        RevenueData(name: 'Follow-up', value: 0),
      ];
    }
  }

  double get totalRevenuePeriod =>
      revenueSplit.fold(0, (sum, item) => sum + item.value);

  String get formattedRevenuePeriodTotal {
    final val = totalRevenuePeriod;
    if (val >= 100000) {
      return '₹${(val / 100000).toStringAsFixed(1)}L';
    } else if (val >= 1000) {
      return '₹${(val / 1000).toStringAsFixed(1)}K';
    }
    return '₹${val.toInt()}';
  }

  // ─── Clinic Overview ───────────────────────────────────────
  int get totalVisits => _allOpdRows.length;

  int get newPatients => _allPatientRows.length;

  int get weeklyVisits {
    try {
      final today = DateTime.now();
      final startOfWeek = today.subtract(Duration(days: today.weekday));
      return _allOpdRows.where((r) {
        final vd = _parseDateTime(r['visit_datetime']);
        return vd != null && !vd.isBefore(startOfWeek);
      }).length;
    } catch (_) {
      return 0;
    }
  }

  int get monthlyVisits {
    try {
      final today = DateTime.now();
      return _allOpdRows.where((r) {
        final vd = _parseDateTime(r['visit_datetime']);
        return vd != null && vd.year == today.year && vd.month == today.month;
      }).length;
    } catch (_) {
      return 0;
    }
  }

  String get weeklyRevenue {
    try {
      final today = DateTime.now();
      final startOfWeek = today.subtract(Duration(days: today.weekday));
      final records = _allOpdRows.where((r) {
        final vd = _parseDateTime(r['visit_datetime']);
        return vd != null && !vd.isBefore(startOfWeek);
      });
      double total = 0;
      for (final r in records) {
        total += _extractFeeFromRow(r);
      }
      return '₹${total.toInt().toString()}';
    } catch (_) {
      return '₹0';
    }
  }

  String get monthlyRevenue {
    try {
      final today = DateTime.now();
      final records = _allOpdRows.where((r) {
        final vd = _parseDateTime(r['visit_datetime']);
        return vd != null && vd.year == today.year && vd.month == today.month;
      });
      double total = 0;
      for (final r in records) {
        total += _extractFeeFromRow(r);
      }
      return '₹${total.toInt().toString()}';
    } catch (_) {
      return '₹0';
    }
  }

  String get followUpRate {
    try {
      if (_allOpdRows.isEmpty) return '0%';
      final followUps = _allOpdRows.where((r) => r['opd_type']?.toString() == 'follow_up').length;
      final rate = (followUps / _allOpdRows.length) * 100;
      return '${rate.toStringAsFixed(0)}%';
    } catch (_) {
      return '0%';
    }
  }

  // ─── Line Chart ────────────────────────────────────────────
  List<OpdTrendData> get opdTrendData {
    try {
      final today = DateTime.now();
      final List<OpdTrendData> list = [];
      final weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

      for (int i = 6; i >= 0; i--) {
        final day = today.subtract(Duration(days: i));
        final count = _allOpdRows.where((r) {
          final vd = _parseDateTime(r['visit_datetime']);
          return vd != null && _isSameDay(vd, day);
        }).length;

        list.add(OpdTrendData(day: weekdays[day.weekday % 7], count: count));
      }
      return list;
    } catch (_) {
      return List.generate(7, (index) => OpdTrendData(day: 'Day', count: 0));
    }
  }

  // ─── Revenue Pie Chart ─────────────────────────────────────
  List<RevenueData> get revenueData {
    try {
      final consults = _allOpdRows.where((r) => r['opd_type']?.toString() != 'follow_up');
      final follows = _allOpdRows.where((r) => r['opd_type']?.toString() == 'follow_up');

      double consultRevenue = 0;
      for (final r in consults) {
        consultRevenue += _extractFeeFromRow(r);
      }
      double followRevenue = 0;
      for (final r in follows) {
        followRevenue += _extractFeeFromRow(r);
      }

      return [
        RevenueData(name: 'Consultation', value: consultRevenue),
        RevenueData(name: 'Follow-up', value: followRevenue),
      ];
    } catch (_) {
      return const [
        RevenueData(name: 'Consultation', value: 0),
        RevenueData(name: 'Follow-up', value: 0),
      ];
    }
  }

  double get totalRevenue =>
      revenueData.fold(0, (sum, item) => sum + item.value);

  // ─── Today's Collection ────────────────────────────────────
  List<CollectionItem> get todaysCollection {
    try {
      final today = DateTime.now();
      final todayRecords = _allOpdRows.where((r) {
        final vd = _parseDateTime(r['visit_datetime']);
        return vd != null && _isSameDay(vd, today);
      }).toList();

      return todayRecords.map((r) {
        final pid = Helpers.toInt(r['patient_id']);
        final patient = _allPatientRows.cast<Map<String, dynamic>?>().firstWhere(
          (p) => p?['id'] == pid,
          orElse: () => null,
        );
        return CollectionItem(
          name: patient?['full_name']?.toString() ?? 'Unknown Patient',
          amount: _extractFeeFromRow(r).toInt(),
          mode: 'Cash',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Helpers ───────────────────────────────────────────────

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _toStringId(int sqliteId) =>
      'P${sqliteId.toString().padLeft(3, '0')}';
}
