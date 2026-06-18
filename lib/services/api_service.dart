import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://192.168.1.100:5000/api';

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
    );
    final data = await _handleResponse(res);
    await saveToken(data['token']);
    return data;
  }

  static Future<Map<String, dynamic>> register(String username, String password, {String name = 'Doctor'}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password, 'name': name}),
    );
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
    );
    return _handleResponse(res);
  }

  static Future<Map<String, dynamic>> syncPush({
    required List<Map<String, dynamic>> patients,
    required List<Map<String, dynamic>> opdRecords,
    required List<Map<String, dynamic>> appointments,
  }) async {
    await _loadToken();
    final res = await http.post(
      Uri.parse('$baseUrl/sync/push'),
      headers: _headers(),
      body: jsonEncode({
        'patients': patients,
        'opd_records': opdRecords,
        'appointments': appointments,
      }),
    );
    return _handleResponse(res);
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
