import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
static String get baseUrl =>
    dotenv.env['API_BASE_URL'] ??
    'http://192.168.31.91:5000/api';
  static String get cloudBaseUrl =>
      dotenv.env['CLOUD_BASE_URL'] ?? '';
  static String? _token;

  static Future<void> _loadToken() async {
    if (_token != null) return;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('api_token');
  }

  static Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_token', token);
  }

  static Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('api_token');
  }

  /// Ensures a valid API token exists. If not, attempts to log in
  /// using credentials from the .env file (LOCAL_USERNAME/LOCAL_PASSWORD).
  /// Call this before any sync operation to avoid 401 errors.
  static Future<void> ensureToken() async {
    await _loadToken();
    if (_token != null) return;

    final envUser = dotenv.env['LOCAL_USERNAME'];
    final envPass = dotenv.env['LOCAL_PASSWORD'];
    if (envUser != null && envPass != null && envUser.isNotEmpty && envPass.isNotEmpty) {
      try {
        debugPrint('API: No token found — attempting login with .env credentials');
        await login(envUser, envPass);
        debugPrint('API: Token obtained successfully');
      } catch (e) {
        debugPrint('API: Token acquisition failed: $e');
        rethrow;
      }
    } else {
      debugPrint('API: No token and no .env credentials available');
    }
  }

  static Map<String, String> _headers() {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (_token != null) {
      h['Authorization'] = 'Bearer $_token';
    }
    return h;
  }

  static Future<Map<String, dynamic>> _handleResponse(http.Response res) async {
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }
    throw ApiException(res.statusCode, body['error']?.toString() ?? 'Unknown error');
  }

  // ─── Auth ───────────────────────────────────────────

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    ).timeout(const Duration(seconds: 5));
    final data = await _handleResponse(res);
    await saveToken(data['token']);
    return data;
  }

  static Future<Map<String, dynamic>> register(String username, String password, {String name = 'Doctor'}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password, 'name': name}),
    ).timeout(const Duration(seconds: 5));
    final data = await _handleResponse(res);
    await saveToken(data['token']);
    return data;
  }

  static Future<Map<String, dynamic>> getMe() async {
    await _loadToken();
    final res = await http.get(Uri.parse('$baseUrl/auth/me'), headers: _headers());
    return _handleResponse(res);
  }

  // ─── Patients ──────────────────────────────────────

  static Future<List<dynamic>> getPatients({String? search}) async {
    await _loadToken();
    final uri = Uri.parse('$baseUrl/patients').replace(queryParameters: search != null ? {'search': search} : null);
    final res = await http.get(uri, headers: _headers());
    final data = await _handleResponse(res);
    return data['patients'] as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getPatient(String id) async {
    await _loadToken();
    final res = await http.get(Uri.parse('$baseUrl/patients/$id'), headers: _headers());
    final data = await _handleResponse(res);
    return data['patient'] as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createPatient(Map<String, dynamic> patient) async {
    await _loadToken();
    final res = await http.post(
      Uri.parse('$baseUrl/patients'),
      headers: _headers(),
      body: jsonEncode(patient),
    );
    final data = await _handleResponse(res);
    return data['patient'] as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updatePatient(String id, Map<String, dynamic> data) async {
    await _loadToken();
    final res = await http.put(
      Uri.parse('$baseUrl/patients/$id'),
      headers: _headers(),
      body: jsonEncode(data),
    );
    final r = await _handleResponse(res);
    return r['patient'] as Map<String, dynamic>;
  }

  static Future<void> deletePatient(String id) async {
    await _loadToken();
    final res = await http.delete(Uri.parse('$baseUrl/patients/$id'), headers: _headers());
    await _handleResponse(res);
  }

  // ─── OPD Records ───────────────────────────────────

  static Future<List<dynamic>> getOPDRecords({String? patientId}) async {
    await _loadToken();
    final uri = Uri.parse('$baseUrl/opd').replace(queryParameters: patientId != null ? {'patient_id': patientId} : null);
    final res = await http.get(uri, headers: _headers());
    final data = await _handleResponse(res);
    return data['records'] as List<dynamic>;
  }

  static Future<Map<String, dynamic>> createOPDRecord(Map<String, dynamic> record) async {
    await _loadToken();
    final res = await http.post(
      Uri.parse('$baseUrl/opd'),
      headers: _headers(),
      body: jsonEncode(record),
    );
    final data = await _handleResponse(res);
    return data['record'] as Map<String, dynamic>;
  }

  static Future<void> deleteOPDRecord(String id) async {
    await _loadToken();
    final res = await http.delete(Uri.parse('$baseUrl/opd/$id'), headers: _headers());
    await _handleResponse(res);
  }

  // ─── Appointments ──────────────────────────────────

  static Future<List<dynamic>> getAppointments({String? date}) async {
    await _loadToken();
    final uri = Uri.parse('$baseUrl/appointments').replace(queryParameters: date != null ? {'date': date} : null);
    final res = await http.get(uri, headers: _headers());
    final data = await _handleResponse(res);
    return data['appointments'] as List<dynamic>;
  }

  static Future<Map<String, dynamic>> createAppointment(Map<String, dynamic> appointment) async {
    await _loadToken();
    final res = await http.post(
      Uri.parse('$baseUrl/appointments'),
      headers: _headers(),
      body: jsonEncode(appointment),
    );
    final data = await _handleResponse(res);
    return data['appointment'] as Map<String, dynamic>;
  }

  static Future<void> deleteAppointment(String id) async {
    await _loadToken();
    final res = await http.delete(Uri.parse('$baseUrl/appointments/$id'), headers: _headers());
    await _handleResponse(res);
  }

  // ─── Clear All Data ───────────────────────────────

  static Future<Map<String, dynamic>> clearAllData() async {
    await _loadToken();
    final res = await http.post(
      Uri.parse('$baseUrl/sync/clear-data'),
      headers: _headers(),
    ).timeout(const Duration(seconds: 60));
    return _handleResponse(res);
  }

  // ─── Sync ──────────────────────────────────────────

  static Future<Map<String, dynamic>> syncPull(String lastSync) async {
    await _loadToken();
    final res = await http.post(
      Uri.parse('$baseUrl/sync/pull'),
      headers: _headers(),
      body: jsonEncode({'last_sync': lastSync}),
    ).timeout(const Duration(seconds: 30));
    return _handleResponse(res);
  }

  static Future<Map<String, dynamic>> syncPush({
    required List<Map<String, dynamic>> patients,
    required List<Map<String, dynamic>> opdRecords,
    required List<Map<String, dynamic>> appointments,
    List<Map<String, String>> deletedEntities = const [],
    List<Map<String, dynamic>> calendarNotes = const [],
    List<Map<String, dynamic>> clinicSettings = const [],
    List<Map<String, dynamic>> medicines = const [],
    List<Map<String, dynamic>> symptoms = const [],
  }) async {
    await _loadToken();
    print("BASE URL = $baseUrl");
    debugPrint('SYNC API syncPush: token=($_token != null) url=$baseUrl/sync/push patients=${patients.length} opdRecords=${opdRecords.length} appointments=${appointments.length} deleted=${deletedEntities.length}');
    final body = <String, dynamic>{
      'patients': patients,
      'opd_records': opdRecords,
      'appointments': appointments,
    };
    if (deletedEntities.isNotEmpty) {
      body['deleted_entities'] = deletedEntities;
    }
    if (calendarNotes.isNotEmpty) {
      body['calendar_notes'] = calendarNotes;
    }
    if (clinicSettings.isNotEmpty) {
      body['clinic_settings'] = clinicSettings;
    }
    if (medicines.isNotEmpty) {
      body['medicines'] = medicines;
    }
    if (symptoms.isNotEmpty) {
      body['symptoms'] = symptoms;
    }
    final res = await http.post(
      Uri.parse('$baseUrl/sync/push'),
      headers: _headers(),
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 120));
    debugPrint('SYNC API syncPush response: status=${res.statusCode}');
    return _handleResponse(res);
  }

  // ─── Cloud Sync ────────────────────────────────────

  static Future<Map<String, dynamic>> cloudRegisterDevice({
    required String deviceId,
    required String deviceName,
    required String clinicId,
    String appVersion = '1.0.0',
  }) async {
    await _loadToken();
    final res = await http.post(
      Uri.parse('$cloudBaseUrl/cloud/register-device'),
      headers: _headers(),
      body: jsonEncode({
        'device_id': deviceId,
        'device_name': deviceName,
        'clinic_id': clinicId,
        'app_version': appVersion,
      }),
    ).timeout(const Duration(seconds: 10));
    return _handleResponse(res);
  }

  static Future<Map<String, dynamic>> cloudUpload({
    required String deviceId,
    required String clinicId,
    required List<Map<String, dynamic>> patients,
    required List<Map<String, dynamic>> opdRecords,
    required List<Map<String, dynamic>> appointments,
    List<Map<String, String>> deletedEntities = const [],
    List<Map<String, dynamic>> calendarNotes = const [],
    List<Map<String, dynamic>> clinicSettings = const [],
    List<Map<String, dynamic>> medicines = const [],
    List<Map<String, dynamic>> symptoms = const [],
  }) async {
    // LOG: First line inside cloudUpload
    debugPrint('CLOUD_DEBUG: cloudUpload ENTERED deviceId=$deviceId clinicId=$clinicId patients=${patients.length} opd=${opdRecords.length} appts=${appointments.length}');
    debugPrint('CLOUD_DEBUG: cloudUpload cloudBaseUrl="$cloudBaseUrl"');

    await _loadToken();
    final body = <String, dynamic>{
      'device_id': deviceId,
      'clinic_id': clinicId,
      'patients': patients,
      'opd_records': opdRecords,
      'appointments': appointments,
    };
    if (deletedEntities.isNotEmpty) {
      body['deleted_entities'] = deletedEntities;
    }
    if (calendarNotes.isNotEmpty) {
      body['calendar_notes'] = calendarNotes;
    }
    if (clinicSettings.isNotEmpty) {
      body['clinic_settings'] = clinicSettings;
    }
    if (medicines.isNotEmpty) {
      body['medicines'] = medicines;
    }
    if (symptoms.isNotEmpty) {
      body['symptoms'] = symptoms;
    }
    final url = '$cloudBaseUrl/cloud/upload-changes';
    final encoded = jsonEncode(body);

    // LOG: URL, payload, token before HTTP call
    debugPrint('CLOUD_DEBUG: upload full URL="$url"');
    debugPrint('CLOUD_DEBUG: upload body size=${encoded.length} bytes');
    debugPrint('CLOUD_DEBUG: upload token=${_token != null ? "present (${_token!.length} chars)" : "null"}');

    try {
      // LOG: Immediately before http.post
      debugPrint('CLOUD_DEBUG: upload ABOUT to call http.post timeout=120s');

      final res = await http.post(
        Uri.parse(url),
        headers: _headers(),
        body: encoded,
      ).timeout(const Duration(seconds: 120));

      // LOG: Immediately after http.post returned
      debugPrint('CLOUD_DEBUG: upload AFTER http.post status=${res.statusCode}');
      debugPrint('CLOUD_DEBUG: upload response body=${res.body.length > 500 ? "${res.body.substring(0, 500)}..." : res.body}');

      return _handleResponse(res);
    } catch (e) {
      debugPrint('CLOUD_DEBUG: upload EXCEPTION caught: $e');
      debugPrint('CLOUD_DEBUG: upload EXCEPTION type=${e.runtimeType}');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> cloudDownload({
    required String deviceId,
    required String clinicId,
    required String lastSync,
  }) async {
    await _loadToken();
    final res = await http.post(
      Uri.parse('$cloudBaseUrl/cloud/download-changes'),
      headers: _headers(),
      body: jsonEncode({
        'device_id': deviceId,
        'clinic_id': clinicId,
        'last_sync': lastSync,
      }),
    ).timeout(const Duration(seconds: 30));
    return _handleResponse(res);
  }

  static Future<void> cloudHeartbeat({
    required String deviceId,
  }) async {
    await _loadToken();
    try {
      await http.post(
        Uri.parse('$cloudBaseUrl/cloud/heartbeat'),
        headers: _headers(),
        body: jsonEncode({'device_id': deviceId}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> pushImages(
    String opdId,
    List<File> images,
  ) async {
    print('API pushImages ENTER: opdId=$opdId fileCount=${images.length}');
    await _loadToken();
    print('API pushImages: token loaded, token=${_token?.substring(0, 20)}...');

    final uri = Uri.parse('$baseUrl/sync/push/images/$opdId');
    print('API pushImages: uri=$uri');

    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $_token';

    for (int i = 0; i < images.length; i++) {
      final image = images[i];
      final fileLen = await image.length();
      print('API pushImages: adding file[$i] path=${image.path} size=$fileLen');
      request.files.add(
        await http.MultipartFile.fromPath('images', image.path),
      );
    }

    print('API pushImages: sending request...');
    final stopwatch = Stopwatch()..start();
    try {
      final streamedResponse = await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamedResponse).timeout(const Duration(seconds: 120));
      stopwatch.stop();
      print('API pushImages: response received in ${stopwatch.elapsedMilliseconds}ms status=${response.statusCode}');
      print('API pushImages: response body=${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        print('API pushImages: SUCCESS - opdId=$opdId drive_urls=${decoded['drive_urls']}');
        return decoded;
      }

      final errorBody = response.body.isNotEmpty
          ? (jsonDecode(response.body)['error']?.toString() ?? 'Unknown error')
          : 'Empty response';
      print('API pushImages: FAILED - status=${response.statusCode} error=$errorBody');
      throw ApiException(
        response.statusCode,
        errorBody,
      );
    } catch (e) {
      stopwatch.stop();
      print('API pushImages: EXCEPTION after ${stopwatch.elapsedMilliseconds}ms: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> cloudUploadImages(
    String opdId,
    List<File> images,
  ) async {
    final uri = Uri.parse('$cloudBaseUrl/cloud/upload-images/$opdId');
    final request = http.MultipartRequest('POST', uri);

    debugPrint('CLOUD IMAGE DEBUG: endpoint=$uri');
    debugPrint('CLOUD IMAGE DEBUG: file count=${images.length}');

    for (final image in images) {
      final exists = image.existsSync();
      debugPrint('CLOUD IMAGE DEBUG: file exists=$exists path=${image.path}');
      request.files.add(
        await http.MultipartFile.fromPath('images', image.path),
      );
    }

    debugPrint('CLOUD IMAGE DEBUG: request.files count=${request.files.length}');
    debugPrint('CLOUD IMAGE DEBUG: sending request...');
    final streamedResponse = await request.send().timeout(const Duration(seconds: 120));
    debugPrint('CLOUD IMAGE DEBUG: streamedResponse statusCode=${streamedResponse.statusCode}');
    final response = await http.Response.fromStream(streamedResponse).timeout(const Duration(seconds: 120));

    debugPrint('CLOUD IMAGE DEBUG: response status=${response.statusCode}');
    debugPrint('CLOUD IMAGE DEBUG: response body=${response.body}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      debugPrint('CLOUD IMAGE DEBUG: upload success, decoding response');
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    debugPrint('CLOUD IMAGE DEBUG: upload failed with status ${response.statusCode}');
    throw ApiException(
      response.statusCode,
      jsonDecode(response.body)['error']?.toString() ?? 'Image upload failed',
    );
  }

  static Future<void> updateFcmToken(String token) async {
    try {
      await _loadToken();
      final res = await http.post(
        Uri.parse('$baseUrl/fcm/token'),
        headers: _headers(),
        body: jsonEncode({'fcm_token': token}),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        debugPrint('FCM token registered successfully');
      } else {
        debugPrint('FCM token registration failed: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('FCM token registration error: $e');
    }
  }

  /// Sends a prescription PDF directly to a patient's WhatsApp via the
  /// WhatsApp Cloud API running on the backend. The backend uploads the
  /// file to WhatsApp's servers and delivers it to the patient's chat
  /// with the PDF already attached.
  static Future<Map<String, dynamic>> sendPrescriptionViaWhatsApp({
    required String phone,
    required List<int> fileBytes,
    String fileName = 'Prescription.pdf',
  }) async {
    await _loadToken();
    final base64Data = base64Encode(fileBytes);
    final res = await http.post(
      Uri.parse('$baseUrl/whatsapp/send-prescription'),
      headers: _headers(),
      body: jsonEncode({
        'phone': phone,
        'file_base64': base64Data,
        'file_name': fileName,
      }),
    ).timeout(const Duration(seconds: 60));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
