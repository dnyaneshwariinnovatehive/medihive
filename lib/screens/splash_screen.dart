import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/medical_pulse.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _sequenceController;
  late Animation<Offset> _appNameSlide;
  late Animation<double> _appNameFade;
  late Animation<double> _taglineFade;
  late Animation<double> _exitFade;
  late AnimationController _bgPulseController;

  @override
  void initState() {
    super.initState();

    _bgPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _sequenceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    _appNameSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _sequenceController,
      curve: const Interval(500/2800, 900/2800, curve: Curves.easeOutCubic),
    ));
    _appNameFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _sequenceController,
      curve: const Interval(500/2800, 900/2800, curve: Curves.easeOutCubic),
    ));

    _taglineFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _sequenceController,
      curve: const Interval(800/2800, 1200/2800, curve: Curves.easeOut),
    ));

    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(
      parent: _sequenceController,
      curve: const Interval(2300/2800, 2800/2800, curve: Curves.easeIn),
    ));

    _sequenceController.forward().then((_) async {
      if (mounted) {
        final auth = context.read<AuthProvider>();
        await auth.loadSavedCredentials();
        if (mounted) {
          context.go(auth.isLoggedIn ? '/app' : '/login');
        }
      }
    });
  }

  @override
  void dispose() {
    _sequenceController.dispose();
    _bgPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _exitFade,
        child: AnimatedBuilder(
          animation: _bgPulseController,
          builder: (context, child) {
            final pulse = 0.7 + (0.3 * _bgPulseController.value);
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(const Color(0xFF103848), const Color(0xFF1A506C), pulse)!,
                    Color.lerp(const Color(0xFF1A506C), const Color(0xFF2A6E90), pulse)!,
                  ],
                ),
              ),
              child: child,
            );
          },
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: MedicalPulse(
                    size: 200,
                    child: const Icon(
                      Icons.medical_services_outlined,
                      size: 80,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                FadeTransition(
                  opacity: _appNameFade,
                  child: SlideTransition(
                    position: _appNameSlide,
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.white, Color(0xFFB0CCDA)],
                      ).createShader(bounds),
                      child: const Text(
                        'MediHive',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FadeTransition(
                  opacity: _taglineFade,
                  child: Text(
                    'Smart Clinic Management',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.75),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                AnimatedBuilder(
                  animation: _sequenceController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _sequenceController.value > (1000/2800) ? 1.0 : 0.0,
                      child: child,
                    );
                  },
                  child: const _LoadingDots(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  const _LoadingDots();

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Widget _buildDot(int index) {
    final delay = (index * 180) / 700.0;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        double t = (_pulseController.value - delay) % 1.0;
        if (t < 0) t += 1.0;
        final pulse = sin(t * pi);

        return Transform.scale(
          scale: 1.0 + (0.6 * pulse),
          child: Opacity(
            opacity: 0.5 + (0.5 * pulse),
            child: child,
          ),
        );
      },
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildDot(0),
        const SizedBox(width: 8),
        _buildDot(1),
        const SizedBox(width: 8),
        _buildDot(2),
      ],
    );
  }
}
