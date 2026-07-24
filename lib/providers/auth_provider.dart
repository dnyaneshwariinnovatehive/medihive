import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/backup_code_service.dart';
import '../services/firebase_messaging_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final StorageService _storageService = StorageService();

  bool _isAuthenticated = false;
  bool _isLoading = false;
  bool _hasLoadedCredentials = false;
  bool _rememberMe = false;
  String _username = '';
  String _password = '';
  AppUser? _currentUser;
  bool _needs2FA = false;
  String _pendingUsername = '';
  String _loginError = '';

  AuthProvider() {
    loadSavedCredentials();
  }

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  bool get hasLoadedCredentials => _hasLoadedCredentials;
  bool get rememberMe => _rememberMe;
  String get username => _username;
  String get password => _password;
  AppUser? get currentUser => _currentUser;
  bool get needs2FA => _needs2FA;
  String get loginError => _loginError;

  bool get isLoggedIn => _isAuthenticated;

  void setUsername(String value) {
    _username = value;
    _loginError = '';
    notifyListeners();
  }

  void setPassword(String value) {
    _password = value;
    _loginError = '';
    notifyListeners();
  }

  void toggleRememberMe() {
    _rememberMe = !_rememberMe;
    notifyListeners();
  }

  void setRememberMe(bool value) {
    _rememberMe = value;
    notifyListeners();
  }

  Future<bool> signIn() async {
    final username = _username.trim();
    final password = _password.trim();

    _isLoading = true;
    _loginError = '';
    notifyListeners();

    final user = await _authService.login(username, password);

    if (user != null) {
      _needs2FA = await BackupCodeService.is2FAEnabled();

      if (_needs2FA) {
        _pendingUsername = username;
        _currentUser = user;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      _isAuthenticated = true;
      _currentUser = user;
      FirebaseMessagingService().subscribeToUserTopic(user.id);
      await _storageService.setLoggedIn(_rememberMe);
      if (_rememberMe) {
        await _storageService.setRememberMe(true);
        await _storageService.setUsername(username);
      } else {
        await _storageService.clearAuth();
      }
    } else {
      _loginError = 'Invalid username or password';
    }

    _isLoading = false;
    notifyListeners();
    return user != null;
  }

  Future<bool> verify2FACode(String code) async {
    final valid = await BackupCodeService.verifyAndConsumeCode(code);
    if (!valid) return false;

    _isAuthenticated = true;
    if (_currentUser != null) {
      FirebaseMessagingService().subscribeToUserTopic(_currentUser!.id);
    }
    if (_rememberMe) {
      await _storageService.setRememberMe(true);
      await _storageService.setUsername(_pendingUsername);
    } else {
      await _storageService.clearAuth();
    }
    await _storageService.setLoggedIn(true);
    _pendingUsername = '';
    notifyListeners();
    return true;
  }

  void cancel2FA() {
    _needs2FA = false;
    _pendingUsername = '';
    _currentUser = null;
    notifyListeners();
  }

  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    notifyListeners();

    final user = await _authService.signInWithGoogle();

    if (user != null) {
      _isAuthenticated = true;
      _currentUser = user;
      FirebaseMessagingService().subscribeToUserTopic(user.id);
      await _storageService.setLoggedIn(true);
    }

    _isLoading = false;
    notifyListeners();
    return user != null;
  }

  Future<void> signOut() async {
    if (_currentUser != null) {
      FirebaseMessagingService().unsubscribeFromUserTopic(_currentUser!.id);
    }
    _isAuthenticated = false;
    _currentUser = null;
    _username = '';
    _password = '';
    _needs2FA = false;
    _pendingUsername = '';
    await _authService.logout();
    await _storageService.clearAuth();
    notifyListeners();
  }

  Future<bool> login() => signIn();
  Future<void> logout() => signOut();

  Future<void> loadSavedCredentials() async {
    _rememberMe = await _storageService.getRememberMe();
    final wasLoggedIn = await _storageService.getLoggedIn();

    if (wasLoggedIn) {
      final user = await _authService.signInSilently();
      if (user != null) {
        _isAuthenticated = true;
        _currentUser = user;
        FirebaseMessagingService().subscribeToUserTopic(user.id);
      } else if (_rememberMe) {
        _username = await _storageService.getUsername();
        _isAuthenticated = true;
        _currentUser = AppUser(id: '1', name: 'Dr. $_username', email: '$_username@medihive.com');
        FirebaseMessagingService().subscribeToUserTopic(_currentUser!.id);
      }
    }
    _hasLoadedCredentials = true;
    notifyListeners();
  }
}
