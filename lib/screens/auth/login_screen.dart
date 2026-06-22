import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _showPassword = false;
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _lastSyncedUsername = '';
  late AnimationController _staggerController;
  late List<Animation<double>> _staggerAnimations;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..forward();

    _staggerAnimations = List.generate(4, (i) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(i * 0.15, 0.45 + (i * 0.1), curve: Curves.easeOutCubic),
        ),
      );
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    if (auth.username != _lastSyncedUsername &&
        auth.username != _usernameController.text) {
      _lastSyncedUsername = auth.username;
      _usernameController.text = auth.username;
      _usernameController.selection = TextSelection.collapsed(
        offset: _usernameController.text.length,
      );
    }
  }

  Future<void> _submitLogin(AuthProvider auth) async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final success = await auth.login();
    if (success && mounted) {
      context.go('/app');
    }
  }

  Widget _staggeredItem(int index, Widget child) {
    return AnimatedBuilder(
      animation: _staggerAnimations[index],
      builder: (context, child) {
        return Opacity(
          opacity: _staggerAnimations[index].value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - _staggerAnimations[index].value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.hasLoadedCredentials && auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go('/app');
        }
      });
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(),
                  _buildDivider(),
                  _buildForm(auth),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: AppTheme.headerGradient,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
      child: Column(
        children: [
          Image.asset(
            'assets/images/logo.png',
            width: 150,
            height: 150,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 12),
          Text(
            'Welcome to Medihive',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Professional Healthcare Management',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      color: AppTheme.border,
    );
  }

  Widget _buildForm(AuthProvider auth) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _staggeredItem(0, const Text(
              'Sign in to your account',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            )),
            const SizedBox(height: 24),
            _staggeredItem(1, TextFormField(
              controller: _usernameController,
              enabled: !auth.isLoading,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              onChanged: (value) {
                _lastSyncedUsername = value;
                auth.setUsername(value);
              },
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter your username';
                }
                return null;
              },
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                labelText: 'Username',
                labelStyle: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: AppTheme.surfaceVariant,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 16, right: 8),
                  child: Icon(
                    Icons.person_outline,
                    size: 22,
                    color: AppTheme.primary,
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
            )),
            const SizedBox(height: 14),
            _staggeredItem(1, TextFormField(
              controller: _passwordController,
              enabled: !auth.isLoading,
              obscureText: !_showPassword,
              onChanged: auth.setPassword,
              onFieldSubmitted: (_) => _submitLogin(auth),
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter your password';
                }
                return null;
              },
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                labelText: 'Password',
                labelStyle: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: AppTheme.surfaceVariant,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 16, right: 8),
                  child: Icon(
                    Icons.lock_outline,
                    size: 22,
                    color: AppTheme.primary,
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: 22,
                      color: AppTheme.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
            )),
            const SizedBox(height: 8),
            _staggeredItem(2, Row(
              children: [
                SizedBox(
                  height: 24,
                  child: Checkbox(
                    value: auth.rememberMe,
                    onChanged: auth.isLoading
                        ? null
                        : (value) =>
                            auth.setRememberMe(value ?? false),
                    activeColor: AppTheme.primary,
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                GestureDetector(
                  onTap: auth.isLoading
                      ? null
                      : () =>
                          auth.setRememberMe(!auth.rememberMe),
                  child: Text(
                    'Remember Me',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {},
                  child: const Text(
                    'Forgot Password',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            )),
            const SizedBox(height: 20),
            _staggeredItem(3, SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: auth.isLoading
                    ? null
                    : () => _submitLogin(auth),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                child: auth.isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('LOG IN'),
              ),
            )),
            const SizedBox(height: 12),
            _staggeredItem(3, SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: auth.isLoading
                    ? null
                    : () async {
                        final success =
                            await auth.signInWithGoogle();
                        if (success && mounted) {
                          context.go('/app');
                        } else if (!success && mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Google Sign-In failed'),
                            ),
                          );
                        }
                      },
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(Colors.white),
                  foregroundColor: WidgetStateProperty.all(Colors.black87),
                  surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
                  shadowColor: WidgetStateProperty.all(Colors.transparent),
                  elevation: WidgetStateProperty.all(0),
                  side: WidgetStateProperty.all(BorderSide(color: Colors.grey.shade300)),
                  shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 14, horizontal: 24)),
                ),
                icon: const Text(
                  'G',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4285F4),
                  ),
                ),
                label: const Text('SIGN IN WITH GOOGLE'),
              ),
            )),
          ],
        ),
      ),
    );
  }
}
