import 'package:flutter/material.dart';
import 'package:memex/domain/models/todo_item.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

/// Visual style of a task priority, used by the card, its pill, the completion
/// circle and the filter menu. Colour never stands alone: the pill carries the
/// label, and normal priority simply has no pill.
class TodoPriorityStyle {
  const TodoPriorityStyle._({
    required this.color,
    this.ring = AppColors.textTertiary,
    this.pillText,
    this.gradientStart,
    this.gradientMid,
  });

  /// Base colour: filter icon and the light sweep of a new task.
  final Color color;

  /// Completion circle border.
  final Color ring;

  /// Completion circle fill, when completed.
  Color get fill => pillText == null ? AppColors.primary : color;

  /// Light text colour of the priority pill. Null means no pill (normal).
  final Color? pillText;

  /// Card gradient alphas: strong at the top-left corner, soft at 45%.
  final double? gradientStart;
  final double? gradientMid;

  static const _radius = BorderRadius.all(Radius.circular(18));

  static const _normal = TodoPriorityStyle._(
    color: AppColors.textSecondary,
    ring: AppColors.textTertiary,
  );

  static TodoPriorityStyle of(TodoPriority priority) => switch (priority) {
        TodoPriority.urgent => const TodoPriorityStyle._(
            color: AppColors.danger,
            ring: AppColors.danger,
            pillText: Color(0xFFFDA4AF),
            gradientStart: 0.40,
            gradientMid: 0.14,
          ),
        TodoPriority.high => const TodoPriorityStyle._(
            color: AppColors.warning,
            ring: AppColors.warning,
            pillText: Color(0xFFFCD34D),
            gradientStart: 0.34,
            gradientMid: 0.12,
          ),
        TodoPriority.low => const TodoPriorityStyle._(
            color: AppColors.priorityLow,
            ring: AppColors.priorityLow,
            pillText: Color(0xFF93C5FD),
            gradientStart: 0.34,
            gradientMid: 0.12,
          ),
        TodoPriority.normal => _normal,
      };

  /// Background of the card. [fade] goes from 0 (tinted) to 1 (plain surface),
  /// used when a task is completed. Normal priority and done tasks are plain.
  BoxDecoration cardDecoration({double fade = 0}) {
    final start = gradientStart;
    final mid = gradientMid;
    if (start == null || mid == null || fade >= 1) {
      return const BoxDecoration(color: AppColors.surface, borderRadius: _radius);
    }
    Color blend(double alpha) =>
        Color.lerp(color.withValues(alpha: alpha), AppColors.surface, fade)!;
    return BoxDecoration(
      borderRadius: _radius,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0, .45, .9],
        colors: [blend(start), blend(mid), AppColors.surface],
      ),
    );
  }

  /// Background of the pill: the base colour at low alpha.
  Color get pillBackground => color.withValues(alpha: 0.16);
}
