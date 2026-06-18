import 'package:google_sign_in/google_sign_in.dart';
import 'api_service.dart';

class AppUser {
  final String id;
  final String name;
  final String email;
  final String? photoUrl;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.photoUrl,
  });
}

class AuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.appdata',
    ],
  );

  /// Standard email/password login via Flask API
  Future<AppUser?> login(String username, String password) async {
    try {
      final data = await ApiService.login(username, password);
      final user = data['user'] as Map<String, dynamic>;
      return AppUser(
        id: user['id']?.toString() ?? '',
        name: user['name']?.toString() ?? 'Doctor',
        email: '${user['username']}@medihive.com',
      );
    } catch (e) {
      return null;
    }
  }

  /// Register a new user via Flask API
  Future<AppUser?> register(String username, String password, {String name = 'Doctor'}) async {
    try {
      final data = await ApiService.register(username, password, name: name);
      final user = data['user'] as Map<String, dynamic>;
      return AppUser(
        id: user['id']?.toString() ?? '',
        name: user['name']?.toString() ?? 'Doctor',
        email: '${user['username']}@medihive.com',
      );
    } catch (e) {
      return null;
    }
  }

  /// Google Sign In
  Future<AppUser?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account != null) {
        return AppUser(
          id: account.id,
          name: account.displayName ?? 'Doctor',
          email: account.email,
          photoUrl: account.photoUrl,
        );
      }
    } catch (e) {
      // Google Sign-In not configured yet
    }
    return null;
  }

  /// Silent sign in for Google
  Future<AppUser?> signInSilently() async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signInSilently();
      if (account != null) {
        return AppUser(
          id: account.id,
          name: account.displayName ?? 'Doctor',
          email: account.email,
          photoUrl: account.photoUrl,
        );
      }
    } catch (e) {
      // Google Sign-In not configured yet
    }
    return null;
  }

  /// Logout
  Future<void> logout() async {
    await ApiService.clearToken();
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
    } catch (_) {}
  }
}
