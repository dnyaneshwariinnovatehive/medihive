import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../models/appointment.dart';
import '../models/appointment_model.dart';
import '../repositories/calendar_notes_repository.dart';
import '../repositories/patient_repository.dart';
import '../repositories/opd_record_repository.dart';
import 'notification_provider.dart';
import '../services/daily_summary_service.dart';
import '../services/sync_manager.dart';
import '../utils/sync_id_generator.dart';
import '../utils/helpers.dart';

class AppointmentProvider extends ChangeNotifier {
  final CalendarNotesRepository _notesRepo = CalendarNotesRepository();

  DateTime _currentDate = DateTime.now();
  int _selectedDay = DateTime.now().day;
  final Map<String, List<String>> _dayNotes = {};

  DateTime get currentDate => _currentDate;
  int get selectedDay => _selectedDay;

  List<String> get dayNotes {
    final key = _noteKeyFor(_currentDate.year, _currentDate.month, _selectedDay);
    return _dayNotes[key] ?? [];
  }

  bool hasNotesForDay(int day) {
    final key = _noteKeyFor(_currentDate.year, _currentDate.month, day);
    return _dayNotes[key]?.isNotEmpty == true;
  }

  String _noteKeyFor(int year, int month, int day) => '$year-$month-$day';

  Future<void> _loadNotes() async {
    try {
      final rows = await _notesRepo.getAll();
      _dayNotes.clear();
      for (final row in rows) {
        final noteDate = row['note_date'] as String? ?? '';
        final noteText = row['note_text'] as String? ?? '';
        List<String> notes;
        try {
          final decoded = jsonDecode(noteText);
          if (decoded is List) {
            notes = decoded.cast<String>();
          } else {
            notes = noteText.isEmpty ? [] : [noteText];
          }
        } catch (_) {
          notes = noteText.isEmpty ? [] : [noteText];
        }
        final parts = noteDate.split('-');
        if (parts.length == 3) {
          final hiveKey =
              '${int.parse(parts[0])}-${int.parse(parts[1])}-${int.parse(parts[2])}';
          _dayNotes[hiveKey] = notes;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  final List<Appointment> _appointments = [];
  StreamSubscription? _apptSubscription;
  bool _loadingHive = false;
  bool _needsReload = false;

  AppointmentProvider() {
    _loadFromHive();
    _loadNotes();
    _refreshHasRealData();
    _apptSubscription = Hive.box<AppointmentModel>('appointments').watch().listen((_) {
      _requestReload();
    });
  }

  void _requestReload() {
    if (_loadingHive) {
      _needsReload = true;
      return;
    }
    _loadFromHive();
  }

  Future<void> _loadFromHive() async {
    if (_loadingHive) return;
    _loadingHive = true;
    try {
      final box = Hive.box<AppointmentModel>('appointments');
      final temp = <Appointment>[];
      for (final m in box.values) {
        final patientName = await _patientNameFromId(m.patientId);
        temp.add(Appointment(
          id: m.id,
          dateTime: m.dateTime,
          type: m.notes == 'Follow-up' ? 'Follow-up' : 'Consultation',
          patient: patientName,
          time: '${m.dateTime.hour.toString().padLeft(2, '0')}:${m.dateTime.minute.toString().padLeft(2, '0')}',
        ));
      }
      _appointments
        ..clear()
        ..addAll(temp);
      notifyListeners();
    } catch (_) {}
    _loadingHive = false;
    if (_needsReload) {
      _needsReload = false;
      _loadFromHive();
    }
  }

  Future<String> _patientNameFromId(String patientId) async {
    try {
      final patient = await PatientRepository().getBySyncId(patientId);
      if (patient != null) {
        final name = patient['full_name'] as String?;
        if (name != null && name.isNotEmpty) return name;
      }
    } catch (_) {}
    return patientId;
  }

  List<Appointment> get appointments => _appointments;

  List<Appointment> get selectedDayAppointments =>
      _appointments.where((a) =>
          a.dateTime.day == _selectedDay &&
          a.dateTime.month == _currentDate.month &&
          a.dateTime.year == _currentDate.year,
      ).toList();

  bool _hasRealDataCached = false;

  Future<void> _refreshHasRealData() async {
    try {
      final patientCount = await PatientRepository().count();
      final opdCount = await OpdRecordRepository().count();
      final apptCount = Hive.box<AppointmentModel>('appointments').length;
      _hasRealDataCached = patientCount > 0 || opdCount > 0 || apptCount > 0;
    } catch (_) {
      _hasRealDataCached = false;
    }
  }

  bool get _hasRealData => _hasRealDataCached;

  List<Appointment> get upcomingFollowUps {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _appointments.where((a) {
      if (a.type != 'Follow-up') return false;
      final aptDate = DateTime(a.dateTime.year, a.dateTime.month, a.dateTime.day);
      return !aptDate.isBefore(today);
    }).toList();
  }

  List<Appointment> get selectedDayFollowUps =>
      _appointments.where((a) =>
          a.type == 'Follow-up' &&
          a.dateTime.day == _selectedDay &&
          a.dateTime.month == _currentDate.month &&
          a.dateTime.year == _currentDate.year,
      ).toList();

  final Map<String, List<String>> _dayReminders = {};

  List<String> get dayReminders {
    final key = '${_currentDate.year}-${_currentDate.month}-$_selectedDay';
    return _dayReminders[key] ?? [];
  }

  void addReminder(String value) {
    if (value.trim().isEmpty) return;
    final key = '${_currentDate.year}-${_currentDate.month}-$_selectedDay';
    _dayReminders.putIfAbsent(key, () => []);
    _dayReminders[key]!.add(value.trim());
    NotificationProvider.addNotificationSilently(
      'Reminder: $_selectedDay ${_currentDate.month}/${_currentDate.year}',
      value.trim(),
    );
    notifyListeners();
  }

  void removeReminderAt(int index) {
    final key = '${_currentDate.year}-${_currentDate.month}-$_selectedDay';
    final reminders = _dayReminders[key];
    if (reminders != null && index < reminders.length) {
      reminders.removeAt(index);
      if (reminders.isEmpty) _dayReminders.remove(key);
      notifyListeners();
    }
  }

  void setSelectedDay(int day) {
    _selectedDay = day;
    notifyListeners();
  }

  void addNote(String value) {
    if (value.trim().isEmpty) return;
    final key = _noteKeyFor(_currentDate.year, _currentDate.month, _selectedDay);
    _dayNotes.putIfAbsent(key, () => []);
    _dayNotes[key]!.add(value.trim());
    _saveNotesForDate(key, _dayNotes[key]!);
    notifyListeners();

    _scheduleNoteReminder(_currentDate.year, _currentDate.month, _selectedDay, value.trim());
  }

  void _scheduleNoteReminder(int year, int month, int day, String note) {
    final noteDate = DateTime(year, month, day);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    if (noteDate.isBefore(todayDate)) return;
    DailySummaryService.scheduleNoteReminder(
      year: year,
      month: month,
      day: day,
      noteText: note,
    );
  }

  void removeNoteAt(int index) {
    final key = _noteKeyFor(_currentDate.year, _currentDate.month, _selectedDay);
    final notes = _dayNotes[key];
    if (notes != null && index < notes.length) {
      notes.removeAt(index);
      if (notes.isEmpty) {
        _dayNotes.remove(key);
        _deleteNotesForDate(key);
      } else {
        _saveNotesForDate(key, notes);
      }
      notifyListeners();
    }
  }

  void removeNoteForDay(int day) {
    final key = _noteKeyFor(_currentDate.year, _currentDate.month, day);
    _dayNotes.remove(key);
    _deleteNotesForDate(key);
    notifyListeners();
  }

  void previousMonth() {
    _currentDate = DateTime(_currentDate.year, _currentDate.month - 1);
    final daysInNewMonth = DateTime(_currentDate.year, _currentDate.month + 1, 0).day;
    if (_selectedDay > daysInNewMonth) _selectedDay = daysInNewMonth;
    notifyListeners();
  }

  void nextMonth() {
    _currentDate = DateTime(_currentDate.year, _currentDate.month + 1);
    final daysInNewMonth = DateTime(_currentDate.year, _currentDate.month + 1, 0).day;
    if (_selectedDay > daysInNewMonth) _selectedDay = daysInNewMonth;
    notifyListeners();
  }

  bool hasAppointment(int day) {
    return _appointments.any((a) =>
        a.dateTime.day == day &&
        a.dateTime.month == _currentDate.month &&
        a.dateTime.year == _currentDate.year);
  }

  List<Appointment> appointmentsForDay(int day) {
    return _appointments.where((a) =>
        a.dateTime.day == day &&
        a.dateTime.month == _currentDate.month &&
        a.dateTime.year == _currentDate.year).toList();
  }

  Future<void> addAppointment({
    required DateTime dateTime,
    required String type,
    required String patient,
    required String time,
    String? patientId,
  }) async {
    final id = 'apt_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999).toString().padLeft(4, '0')}';
    try {
      final box = Hive.box<AppointmentModel>('appointments');
      if (patientId == null || patientId.isEmpty) {
        final allPatients = await PatientRepository().getAll();
        for (final p in allPatients) {
          if ((p['full_name'] as String?) == patient) {
            patientId = p['sync_id'] as String? ?? 'P${p['id']}';
            break;
          }
        }
      }
      // Prevent duplicate appointment for the same patient on the same day
      final isDuplicate = _appointments.any((a) =>
        a.patient == patient &&
        a.dateTime.year == dateTime.year &&
        a.dateTime.month == dateTime.month &&
        a.dateTime.day == dateTime.day);
      if (isDuplicate) return;
      _appointments.add(Appointment(
        id: id,
        dateTime: dateTime,
        type: type,
        patient: patient,
        time: time,
      ));
      box.put(id, AppointmentModel(
        id: id,
        patientId: patientId ?? '',
        dateTime: dateTime,
        notes: type == 'Follow-up' ? 'Follow-up' : '',
        isSynced: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    } catch (_) {}
    notifyListeners();
  }

  void removeAppointment(String id) {
    _appointments.removeWhere((a) => a.id == id);
    try {
      final box = Hive.box<AppointmentModel>('appointments');
      box.delete(id);
    } catch (_) {}
    notifyListeners();
  }

  String _hiveKeyToSqlDate(String hiveKey) {
    final parts = hiveKey.split('-');
    if (parts.length == 3) {
      return '${parts[0].padLeft(4, '0')}-${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}';
    }
    return hiveKey;
  }

  Future<void> _saveNotesForDate(String hiveKey, List<String> notes) async {
    try {
      final sqlDate = _hiveKeyToSqlDate(hiveKey);
      final noteText = jsonEncode(notes);
      final existing = await _notesRepo.getByDate(sqlDate);
      final now = DateTime.now().toIso8601String();
      if (existing != null) {
        await _notesRepo.update(Helpers.toInt(existing['id']), {
          'note_text': noteText,
          'updated_at': now,
        });
      } else {
        await _notesRepo.insert({
          'id': SyncIdGenerator.nextId(),
          'note_date': sqlDate,
          'note_text': noteText,
          'created_at': now,
          'updated_at': now,
        });
      }
      // Trigger sync so other devices get updated notes
      try {
        SyncManager().forceSyncNow();
      } catch (_) {}
    } catch (e, st) {
      debugPrint('SYNC QUEUE INSERT FAILED: $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  Future<void> _deleteNotesForDate(String hiveKey) async {
    try {
      final sqlDate = _hiveKeyToSqlDate(hiveKey);
      await _notesRepo.deleteByDate(sqlDate);
      // Trigger sync so other devices get the deletion
      try {
        SyncManager().forceSyncNow();
      } catch (_) {}
    } catch (e, st) {
      debugPrint('DELETE NOTES FAILED: $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  @override
  void dispose() {
    _apptSubscription?.cancel();
    super.dispose();
  }
}
