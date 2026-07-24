import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/patient.dart';

class VisitTimelineItem extends StatelessWidget {
  final VisitRecord visit;
  final bool isLast;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const VisitTimelineItem({
    super.key,
    required this.visit,
    this.isLast = false,
    this.onDelete,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: AppTheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          visit.date,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      _buildTypeCapsule(visit.type),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Diagnosis',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    visit.diagnosis,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Clinical Notes',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    visit.notes,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  if (visit.panchakarmaNotes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Panchakarma Notes',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      visit.panchakarmaNotes,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Divider(height: 1, color: AppTheme.border),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Fees',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (onEdit != null)
                            GestureDetector(
                              onTap: onEdit,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.edit_outlined,
                                  size: 16,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                          if (onDelete != null)
                            GestureDetector(
                              onTap: onDelete,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                  color: AppTheme.danger,
                                ),
                              ),
                            ),
                          Text(
                            '₹${visit.fees}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeCapsule(String type) {
    final isFollowUp = type == 'Follow-up' || type == 'follow_up';
    final label = isFollowUp ? 'FOLLOW-UP' : 'CONSULTATION';
    final color = isFollowUp ? AppTheme.warning : AppTheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 9,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
