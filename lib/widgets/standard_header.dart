import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StandardHeader extends StatelessWidget {
  final String title;
  final List<Widget>? trailingActions;
  final bool showBack;
  final VoidCallback? onBack;

  const StandardHeader({
    super.key,
    required this.title,
    this.trailingActions,
    this.showBack = false,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      toolbarHeight: 64,
      centerTitle: true,
      pinned: true,
      elevation: 0,
      automaticallyImplyLeading: false,
      backgroundColor: AppTheme.primary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      leadingWidth: showBack ? 100 : 66,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showBack)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: GestureDetector(
                onTap: onBack ?? () => Navigator.maybePop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(left: showBack ? 4 : 16),
            child: Icon(
              Icons.medical_services_outlined,
              size: 30,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        ...?trailingActions,
      ],
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
      ),
    );
  }
}
