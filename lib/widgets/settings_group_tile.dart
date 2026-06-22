import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Settings group tile matching the web app's settings row pattern.
class SettingsGroupTile extends StatelessWidget {
  final IconData icon;
  final Color? iconBgColor;
  final Color iconColor;
  final String label;
  final String? badge;
  final bool isToggle;
  final bool toggleValue;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggleChanged;
  final bool showDivider;

  const SettingsGroupTile({
    super.key,
    required this.icon,
    this.iconBgColor,
    this.iconColor = AppTheme.primary,
    required this.label,
    this.badge,
    this.isToggle = false,
    this.toggleValue = false,
    this.onTap,
    this.onToggleChanged,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: isToggle
              ? () => onToggleChanged?.call(!toggleValue)
              : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconBgColor ?? AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.danger,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (badge != null) SizedBox(width: 8),
                if (isToggle)
                  Switch(
                    value: toggleValue,
                    onChanged: onToggleChanged,
                    activeThumbColor: AppTheme.primary,
                    activeTrackColor: AppTheme.primary.withValues(alpha: 0.4),
                    inactiveThumbColor: AppTheme.textTertiary,
                    inactiveTrackColor: AppTheme.border,
                  )
                else
                  Icon(Icons.chevron_right,
                      color: AppTheme.textTertiary, size: 20),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 68,
            color: AppTheme.isDarkMode
                ? AppTheme.textOnPrimary.withValues(alpha: 0.08)
                : AppTheme.actionButton,
          ),
      ],
    );
  }
}


