import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import '../theme/app_theme.dart';
import '../services/google_auth_service.dart';
import '../services/sync_manager.dart';
import '../repositories/clinic_settings_repository.dart';

class SettingsProvider extends ChangeNotifier {
  final ClinicSettingsRepository _settingsRepo = ClinicSettingsRepository();

  bool _darkMode = false;

  // Doctor Profile
  String _doctorName = 'Dr. Rajas Gavas';
  String _doctorSpecialty = 'General Physician';
  String _doctorLicense = 'I-107200-A';
  String _doctorEmail = 'dr.rajas@gmail.com';
  String _doctorPhone = '+91 98765 43210';
  String _doctorProfileImage = '';

  // Clinic Info
  String _clinicName = 'Shree Clinic';
  String _clinicPhone = '+91 22 2345 6789';
  String _clinicAddress = 'Suite 101, Medical Plaza, Mumbai';
  String _clinicHours = '09:00 AM - 01:00 PM, 04:00 PM - 08:00 PM';
  String _clinicWebsite = '';
  String _clinicLogoPath = '';

  // Google Sign-In & Backup state (lazy to avoid web crash)
  GoogleAuthService? _googleAuthServiceInstance;
  GoogleAuthService get _googleAuthService {
    _googleAuthServiceInstance ??= GoogleAuthService();
    return _googleAuthServiceInstance!;
  }
  bool _isGoogleSigningIn = false;
  GoogleSignInAccount? _googleUser;
  String? _googleAuthError;
  String _lastSyncTime = 'Never';
  bool _isSyncEnabled = false;
  bool _isSyncing = false;
  StreamSubscription? _googleAuthSub;
  int _authRefreshAttempts = 0;

  // Getters
  bool get darkMode => _darkMode;
  String get doctorName => _doctorName;
  String get doctorSpecialty => _doctorSpecialty;
  String get doctorLicense => _doctorLicense;
  String get doctorEmail => _doctorEmail;
  String get doctorPhone => _doctorPhone;
  String get doctorProfileImage => _doctorProfileImage;

  String get clinicName => _clinicName;
  String get clinicPhone => _clinicPhone;
  String get clinicAddress => _clinicAddress;
  String get clinicHours => _clinicHours;
  String get clinicWebsite => _clinicWebsite;
  String get clinicLogoPath => _clinicLogoPath;

  // Google Getters
  bool get isGoogleConnected => _googleUser != null;
  bool get isGoogleSigningIn => _isGoogleSigningIn;
  GoogleSignInAccount? get googleUser => _googleUser;
  String? get googleAuthError => _googleAuthError;
  String get lastSyncTime => _lastSyncTime;
  bool get isSyncEnabled => _isSyncEnabled;
  bool get isSyncing => _isSyncing;

  SettingsProvider() {
    _loadSettings();
    _checkGoogleSignInStatus();
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    try {
      _googleAuthSub = _googleAuthService.onAuthStateChanged.listen((account) {
        _googleUser = account;
        if (account == null) {
          _isSyncEnabled = false;
          _isSyncing = false;
          _googleAuthError = null;
        } else {
          _isSyncEnabled = true;
        }
        notifyListeners();
      });
    } catch (_) {}
  }

  Future<void> _checkGoogleSignInStatus() async {
    try {
      final signedIn = await _googleAuthService.isSignedIn();
      if (signedIn) {
        _googleUser = _googleAuthService.currentUser;
        final prefs = await SharedPreferences.getInstance();
        _lastSyncTime = prefs.getString('lastSyncTime') ?? 'Never';
        _isSyncEnabled = prefs.getBool('isSyncEnabled') ?? false;
      }
      _googleAuthError = null;
      notifyListeners();
    } catch (e) {
      _googleAuthError = null;
      notifyListeners();
    }
  }

  Future<void> signInGoogle() async {
    _isGoogleSigningIn = true;
    _googleAuthError = null;
    notifyListeners();

    try {
      final account = await _googleAuthService.signInWithGoogle();
      _googleUser = account;
      _authRefreshAttempts = 0;
      if (account != null) {
        _isSyncEnabled = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isSyncEnabled', true);
      }
    } catch (e) {
      _googleAuthError = 'Sign-in failed: $e';
      rethrow;
    } finally {
      _isGoogleSigningIn = false;
      notifyListeners();
    }
  }

  Future<void> signOutGoogle() async {
    _googleAuthError = null;
    notifyListeners();

    try {
      await _googleAuthService.signOut();
      _googleUser = null;
      _isSyncEnabled = false;
      _authRefreshAttempts = 0;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isSyncEnabled', false);
      await prefs.remove('lastSyncTime');
      _lastSyncTime = 'Never';
    } catch (e) {
      _googleAuthError = 'Disconnect failed. Please try again.';
    } finally {
      notifyListeners();
    }
  }

  Future<void> triggerSync() async {
    if (_isSyncing) return;

    _isSyncing = true;
    _googleAuthError = null;
    notifyListeners();

    try {
      // 1. ALWAYS run Flask API sync first (writes OPD data to Google Sheet
      //    via the service account — does NOT require user's Google Drive).
      //    This ensures OPD records are synced regardless of Drive connection.
      if (!kIsWeb) {
        try {
          await SyncManager().triggerManualSync();
        } catch (e) {
          debugPrint('SettingsProvider.triggerSync: SyncManager error: $e');
        }
      }

      // 2. Check Google Drive connection for backup features (optional).
      //    If not connected, the Flask sync above still succeeded.
      final signedIn = await _googleAuthService.isSignedIn();
      if (!signedIn) {
        _googleAuthError = 'Google Drive not connected — OPD data was synced to sheet, but Drive backup skipped.';
        _isSyncing = false;
        notifyListeners();
        return;
      }
      _googleUser = _googleAuthService.currentUser;

      _googleAuthError = null;
      _authRefreshAttempts = 0;

      final now = DateTime.now();
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final String amPm = now.hour >= 12 ? 'PM' : 'AM';
      final int displayHour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
      final String minuteStr = now.minute.toString().padLeft(2, '0');
      _lastSyncTime = '${now.day} ${months[now.month - 1]} ${now.year}, ${displayHour.toString().padLeft(2, '0')}:$minuteStr $amPm';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastSyncTime', _lastSyncTime);
    } catch (e) {
      _googleAuthError = 'Sync failed. Please try again.';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _loadSettings() async {
    try {
      final row = await _settingsRepo.getFirst();
      if (row != null) {
        _doctorName = row['doctor_name'] as String? ?? 'Dr. Rajas Gavas';
        _doctorEmail = row['doctor_email'] as String? ?? 'dr.rajas@gmail.com';
        _doctorPhone = row['doctor_contact'] as String? ?? '+91 98765 43210';
        _doctorLicense = row['doctor_license_no'] as String? ?? 'I-107200-A';
        _doctorProfileImage = row['doctor_photo_path'] as String? ?? '';
        _clinicName = row['clinic_name'] as String? ?? 'Shree Clinic';
        _clinicPhone = row['clinic_phone'] as String? ?? '+91 22 2345 6789';
        _clinicAddress = row['clinic_address'] as String? ?? 'Suite 101, Medical Plaza, Mumbai';
        _clinicHours = row['operating_hours'] as String? ?? '09:00 AM - 01:00 PM, 04:00 PM - 08:00 PM';
        _clinicWebsite = row['website'] as String? ?? '';
        _clinicLogoPath = row['clinic_logo_path'] as String? ?? '';
      }

      final prefs = await SharedPreferences.getInstance();
      _darkMode = prefs.getBool('darkMode') ?? false;
      AppTheme.isDarkMode = _darkMode;
      _doctorSpecialty = prefs.getString('doctorSpecialty') ?? 'General Physician';
      notifyListeners();
    } catch (_) {
      // Silently handle — settings will use defaults
    }
  }

  Future<void> _saveClinicSettingsRow() async {
    await _settingsRepo.upsert({
      'doctor_name': _doctorName,
      'doctor_email': _doctorEmail,
      'doctor_contact': _doctorPhone,
      'doctor_license_no': _doctorLicense,
      'doctor_photo_path': _doctorProfileImage,
      'clinic_name': _clinicName,
      'clinic_phone': _clinicPhone,
      'clinic_address': _clinicAddress,
      'website': _clinicWebsite,
      'clinic_logo_path': _clinicLogoPath,
      'operating_hours': _clinicHours,
      'updated_at': DateTime.now().toIso8601String(),
    });
    // Trigger sync so other devices get updated settings
    try {
      SyncManager().forceSyncNow();
    } catch (_) {}
  }

  Future<void> toggleDarkMode() async {
    _darkMode = !_darkMode;
    AppTheme.isDarkMode = _darkMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', _darkMode);
  }

  Future<void> updateDoctorProfile({
    required String name,
    required String specialty,
    required String license,
    required String email,
    required String phone,
  }) async {
    _doctorName = name;
    _doctorSpecialty = specialty;
    _doctorLicense = license;
    _doctorEmail = email;
    _doctorPhone = phone;
    notifyListeners();

    await _saveClinicSettingsRow();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('doctorSpecialty', specialty);
  }

  Future<void> updateDoctorProfileImage(String base64Image) async {
    _doctorProfileImage = base64Image;
    notifyListeners();
    await _saveClinicSettingsRow();
  }

  Future<void> updateClinicInfo({
    required String name,
    required String phone,
    required String address,
    required String hours,
    String website = '',
  }) async {
    _clinicName = name;
    _clinicPhone = phone;
    _clinicAddress = address;
    _clinicHours = hours;
    _clinicWebsite = website;
    notifyListeners();

    await _saveClinicSettingsRow();
  }

  @override
  void dispose() {
    _googleAuthSub?.cancel();
    super.dispose();
  }

}
