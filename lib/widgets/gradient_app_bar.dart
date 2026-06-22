import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/sync_manager.dart';

// ─── Cloud Sync Status Icon Widget ───────────────────────────

class SyncCloudStatusIcon extends StatelessWidget {
  const SyncCloudStatusIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SyncManager>(
      builder: (context, syncMgr, child) {
        Widget icon;
        switch (syncMgr.syncState) {
          case SyncState.offline:
            icon = Icon(Icons.cloud_off, color: Colors.white.withValues(alpha: 0.5), size: 22);
            break;
          case SyncState.syncing:
            icon = const _SpinningCloudIcon();
            break;
          case SyncState.synced:
            icon = Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.cloud_outlined, color: Colors.white.withValues(alpha: 0.9), size: 22),
                const Positioned(
                  bottom: 0,
                  right: 0,
                  child: Icon(Icons.check_circle, color: AppTheme.success, size: 10),
                ),
              ],
            );
            break;
          case SyncState.error:
            icon = Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.cloud_outlined, color: Colors.white.withValues(alpha: 0.9), size: 22),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 10, minHeight: 10),
                    child: const Center(
                      child: Text(
                        '!',
                        style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            );
            break;
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Tooltip(
            message: 'Sync Status: ${syncMgr.syncState.name.toUpperCase()}',
            child: icon,
          ),
        );
      },
    );
  }
}

class _SpinningCloudIcon extends StatefulWidget {
  const _SpinningCloudIcon();
  @override
  State<_SpinningCloudIcon> createState() => _SpinningCloudIconState();
}

class _SpinningCloudIconState extends State<_SpinningCloudIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.cloud_outlined, color: AppTheme.primaryLighter, size: 22),
        RotationTransition(
          turns: _controller,
          child: const Icon(Icons.sync, color: Colors.white, size: 12),
        ),
      ],
    );
  }
}

// ─── GradientAppBar ───────────────────────────────────────────

class GradientAppBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;
  final Widget? bottom;
  final double bottomPadding;

  const GradientAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
    this.bottom,
    this.bottomPadding = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (onBack != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: GestureDetector(
                        onTap: onBack,
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Image.asset(
                    'assets/images/logo.png',
                    height: 80,
                    width: 80,
                    fit: BoxFit.contain,
                  ),
                  const SyncCloudStatusIcon(),
                  if (trailing != null) trailing!,
                ],
              ),
              if (bottom != null) ...[
                const SizedBox(height: 16),
                bottom!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── SliverGradientAppBar ──────────────────────────────────────

class SliverGradientAppBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;
  final Widget? bottom;
  final double expandedHeight;

  const SliverGradientAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
    this.bottom,
    this.expandedHeight = 160.0,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasBottom = bottom != null;
    return SliverAppBar(
      expandedHeight: hasBottom ? expandedHeight : 130.0,
      floating: false,
      pinned: true,
      elevation: 4,
      backgroundColor: AppTheme.primary,
      leading: onBack != null
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: onBack,
            )
          : null,
      title: hasBottom
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                  ),
              ],
            )
          : null,
      actions: [
        Image.asset(
          'assets/images/logo.png',
          height: 80,
          width: 80,
          fit: BoxFit.contain,
        ),
        const SyncCloudStatusIcon(),
        if (trailing != null) trailing!,
        if (trailing != null) const SizedBox(width: 8),
      ],
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.primaryGradient,
        ),
        child: FlexibleSpaceBar(
          centerTitle: false,
          titlePadding: EdgeInsets.only(
            left: onBack != null ? 56 : 16,
            bottom: 14,
            right: 16,
          ),
          title: hasBottom
              ? null
              : Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
          background: hasBottom
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 76, 16, 16),
                    child: bottom,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
