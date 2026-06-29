import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:hive/hive.dart';
import '../models/appointment_model.dart';
import '../repositories/patient_repository.dart';
import '../repositories/opd_record_repository.dart';

class ExcelExportService {
  static final ExcelExportService _instance = ExcelExportService._internal();
  factory ExcelExportService() => _instance;
  ExcelExportService._internal();

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    return '$day/$month/$year';
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '';
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final amPm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '${displayHour.toString().padLeft(2, '0')}:$minute $amPm';
  }

  CellValue? _toCellValue(dynamic val) {
    if (val == null) return null;
    if (val is int) return IntCellValue(val);
    if (val is double) return DoubleCellValue(val);
    if (val is bool) return BoolCellValue(val);
    return TextCellValue(val.toString());
  }

  String generateFileName(String clinicName, {int recordCount = 0}) {
    final cleanClinicName = clinicName.replaceAll(RegExp(r'\s+'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'MediHive_${cleanClinicName}_${recordCount}_records_$timestamp.xlsx';
  }

  Future<Uint8List> generateExcelFile({String clinicName = 'Shree Clinic'}) async {
    final patientRepo = PatientRepository();
    final opdRepo = OpdRecordRepository();
    final patients = await patientRepo.getAll();
    final opdRecords = await opdRepo.getAll();
    final appointments = Hive.box<AppointmentModel>('appointments').values.toList();

    return _buildExcel(patients, opdRecords, appointments, clinicName);
  }

  Future<Uint8List> generateDailyReport({String clinicName = 'Shree Clinic'}) async {
    final today = DateTime.now();

    bool isToday(DateTime date) {
      return date.year == today.year && date.month == today.month && date.day == today.day;
    }

    final patientRepo = PatientRepository();
    final opdRepo = OpdRecordRepository();
    final allPatients = await patientRepo.getAll();
    final allOpd = await opdRepo.getAll();
    final patients = allPatients.where((p) {
      final dt = DateTime.tryParse(p['created_at'] as String? ?? '');
      return dt != null && isToday(dt);
    }).toList();
    final opdRecords = allOpd.where((r) {
      final visitDt = DateTime.tryParse(r['visit_datetime'] as String? ?? '');
      final createdDt = DateTime.tryParse(r['created_at'] as String? ?? '');
      return (visitDt != null && isToday(visitDt)) ||
          (createdDt != null && isToday(createdDt));
    }).toList();
    final appointments = Hive.box<AppointmentModel>('appointments')
        .values
        .where((a) => isToday(a.dateTime) || isToday(a.createdAt))
        .toList();

    return _buildExcel(patients, opdRecords, appointments, clinicName);
  }

  Future<Uint8List> _buildExcel(
    List<Map<String, dynamic>> patients,
    List<Map<String, dynamic>> opdRecords,
    List<AppointmentModel> appointments,
    String clinicName,
  ) async {
    final excel = Excel.createExcel();

    final CellStyle headerStyle = CellStyle(
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#1565C0'),
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final CellStyle normalStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Left,
    );

    final CellStyle altStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#F5F5F5'),
      horizontalAlign: HorizontalAlign.Left,
    );

    final now = DateTime.now();
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year;
    final dashboardSheetName = 'MediHive_Backup_$day-$month-$year';

    excel.rename('Sheet1', dashboardSheetName);
    final dashboardSheet = excel[dashboardSheetName];

    _writeRow(dashboardSheet, 0, ['MediHive Clinic Backup Dashboard'], headerStyle);

    _writeRow(dashboardSheet, 2, ['Clinic Name', clinicName], normalStyle);
    _writeRow(dashboardSheet, 3, ['Backup Date', '$day/$month/$year'], altStyle);
    _writeRow(dashboardSheet, 4, ['Total Patients In File', patients.length.toString()], normalStyle);
    _writeRow(dashboardSheet, 5, ['Total OPD Records In File', opdRecords.length.toString()], altStyle);
    _writeRow(dashboardSheet, 6, ['Total Appointments In File', appointments.length.toString()], normalStyle);

    _autoFitColumns(dashboardSheet);

    final patientsSheet = excel['Patients'];
    final patientsHeaders = [
      'Patient ID',
      'Full Name',
      'DOB',
      'Age',
      'Mobile',
      'Address',
      'Total Visits',
      'Last Visit',
      'Created At',
      'Updated At',
    ];
    _writeRow(patientsSheet, 0, patientsHeaders, headerStyle);

    for (int i = 0; i < patients.length; i++) {
      final p = patients[i];
      final rowStyle = i % 2 == 1 ? altStyle : normalStyle;

      final pId = 'P${p['id']}';
      final totalVisits = opdRecords
          .where((r) => r['patient_id'] == p['id'])
          .length;
      final patientOpd = opdRecords
          .where((r) => r['patient_id'] == p['id'])
          .toList();
      String lastVisitStr = 'Never';
      if (patientOpd.isNotEmpty) {
        patientOpd.sort((a, b) {
          final aDt = DateTime.tryParse(a['visit_datetime'] as String? ?? '') ?? DateTime(2000);
          final bDt = DateTime.tryParse(b['visit_datetime'] as String? ?? '') ?? DateTime(2000);
          return bDt.compareTo(aDt);
        });
        final lastDt = DateTime.tryParse(patientOpd.first['visit_datetime'] as String? ?? '');
        if (lastDt != null) lastVisitStr = _formatDate(lastDt);
      }
      final createdDt = DateTime.tryParse(p['created_at'] as String? ?? '');

      final data = [
        pId,
        p['full_name'] as String? ?? '',
        p['dob'] as String? ?? '',
        (p['age'] as int? ?? 0).toString(),
        p['mobile_number'] as String? ?? '',
        p['address'] as String? ?? '',
        totalVisits.toString(),
        lastVisitStr,
        _formatDate(createdDt),
        _formatDate(createdDt),
      ];
      _writeRow(patientsSheet, i + 1, data, rowStyle);
    }
    _autoFitColumns(patientsSheet);

    final opdSheet = excel['OPD Records'];
    final opdHeaders = [
      'Record ID',
      'Patient ID',
      'Patient Name',
      'Visit Type',
      'Visit Date',
      'Symptoms',
      'Diagnosis',
      'Medicines',
      'Dosage',
      'Notes',
      'Draft Status',
      'Updated At',
    ];
    _writeRow(opdSheet, 0, opdHeaders, headerStyle);

    for (int i = 0; i < opdRecords.length; i++) {
      final r = opdRecords[i];
      final rowStyle = i % 2 == 1 ? altStyle : normalStyle;

      final rPatientId = r['patient_id'];
      final patient = patients.cast<Map<String, dynamic>?>().firstWhere(
        (p) => p?['id'] == rPatientId,
        orElse: () => null,
      );
      final patientName = patient?['full_name'] as String? ?? 'Unknown Patient';
      final rCreatedDt = DateTime.tryParse(r['created_at'] as String? ?? '');

      final data = [
        r['opd_id'] as String? ?? '',
        'P$rPatientId',
        patientName,
        r['opd_type'] as String? ?? '',
        _formatDate(DateTime.tryParse(r['visit_datetime'] as String? ?? '')),
        r['symptoms'] as String? ?? '',
        r['diagnosis'] as String? ?? '',
        r['medicines'] as String? ?? '',
        'N/A',
        'N/A',
        'Final',
        _formatDate(rCreatedDt),
      ];
      _writeRow(opdSheet, i + 1, data, rowStyle);
    }
    _autoFitColumns(opdSheet);

    final apptSheet = excel['Appointments'];
    final apptHeaders = [
      'Appt ID',
      'Patient Name',
      'Date',
      'Time',
      'Notes',
      'Status',
      'Updated At',
    ];
    _writeRow(apptSheet, 0, apptHeaders, headerStyle);

    for (int i = 0; i < appointments.length; i++) {
      final a = appointments[i];
      final rowStyle = i % 2 == 1 ? altStyle : normalStyle;

      final patient = patients.cast<Map<String, dynamic>?>().firstWhere(
        (p) => p?['id'] == int.tryParse(a.patientId.replaceAll(RegExp(r'[^0-9]'), '')),
        orElse: () => null,
      );
      final patientName = patient?['full_name'] as String? ?? 'Unknown Patient';

      final data = [
        a.id,
        patientName,
        _formatDate(a.dateTime),
        _formatTime(a.dateTime),
        a.notes,
        a.isSynced ? 'Synced' : 'Pending Sync',
        _formatDate(a.updatedAt),
      ];
      _writeRow(apptSheet, i + 1, data, rowStyle);
    }
    _autoFitColumns(apptSheet);

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  void _writeRow(Sheet sheet, int rowIndex, List<String> values, CellStyle style) {
    for (int colIndex = 0; colIndex < values.length; colIndex++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIndex, rowIndex: rowIndex));
      cell.value = _toCellValue(values[colIndex]);
      cell.cellStyle = style;
    }
  }

  void _autoFitColumns(Sheet sheet) {
    final maxCols = sheet.maxColumns;
    final maxRows = sheet.maxRows;
    for (int col = 0; col < maxCols; col++) {
      int maxLength = 0;
      for (int row = 0; row < maxRows; row++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
        if (cell.value != null) {
          final strLen = cell.value.toString().length;
          if (strLen > maxLength) {
            maxLength = strLen;
          }
        }
      }
      sheet.setColumnWidth(col, (maxLength + 5).toDouble().clamp(12.0, 45.0));
    }
  }
}
