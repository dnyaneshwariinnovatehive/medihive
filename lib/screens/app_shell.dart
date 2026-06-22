import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/settings_provider.dart';

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsProvider>();
    final currentIndex = navigationShell.currentIndex;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: navigationShell,
      bottomNavigationBar: Container(
        height: 80,
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          border: Border(
            top: BorderSide(color: AppTheme.divider, width: 1.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_outlined, Icons.home, 'Home', currentIndex, () => navigationShell.goBranch(0), null),
                _buildNavItem(1, Icons.assignment_outlined, Icons.assignment, 'OPD', currentIndex, () => navigationShell.goBranch(1), null),
                _buildNavItem(2, Icons.people_outline, Icons.people, 'Patients', currentIndex, () => navigationShell.goBranch(2), null),
                _buildNavItem(3, Icons.calendar_today_outlined, Icons.calendar_today, 'Calendar', currentIndex, () => navigationShell.goBranch(3), null),
                _buildNavItem(4, Icons.settings_outlined, Icons.settings, 'Settings', currentIndex, () => navigationShell.goBranch(4), null),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label, int currentIndex, VoidCallback onTap, int? badge) {
    final isActive = index == currentIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primary.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedScale(
                    scale: isActive ? 1.15 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: Icon(
                      isActive ? activeIcon : icon,
                      color: isActive ? AppTheme.primary : AppTheme.textHint,
                      size: 24,
                    ),
                  ),
                  if (badge != null && badge > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.danger,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text(
                          badge > 9 ? '9+' : badge.toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: isActive ? AppTheme.primary : AppTheme.textHint,
                  fontSize: isActive ? 11 : 10,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  letterSpacing: 0.2,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
