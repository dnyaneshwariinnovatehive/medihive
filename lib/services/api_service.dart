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
  }) async {
    await _loadToken();
    print("BASE URL = $baseUrl");
    debugPrint('SYNC API syncPush: token=($_token != null) url=$baseUrl/sync/push patients=${patients.length} opdRecords=${opdRecords.length} appointments=${appointments.length}');
    final res = await http.post(
      Uri.parse('$baseUrl/sync/push'),
      headers: _headers(),
      body: jsonEncode({
        'patients': patients,
        'opd_records': opdRecords,
        'appointments': appointments,
      }),
    ).timeout(const Duration(seconds: 120));
    debugPrint('SYNC API syncPush response: status=${res.statusCode}');
    return _handleResponse(res);
  }

  static Future<Map<String, dynamic>> pushImages(
    String opdId,
    List<File> images,
  ) async {
    await _loadToken();

    final uri = Uri.parse('$baseUrl/sync/push/images/$opdId');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $_token';

    for (final image in images) {
      request.files.add(
        await http.MultipartFile.fromPath('images', image.path),
      );
    }

    final streamedResponse = await request.send().timeout(const Duration(seconds: 120));
    final response = await http.Response.fromStream(streamedResponse).timeout(const Duration(seconds: 120));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
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
