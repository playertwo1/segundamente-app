import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/timeline/view_models/card_tasks_viewmodel.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';

const Cubic _enterCurve = Cubic(0.16, 1, 0.3, 1);
const Cubic _leaveCurve = Cubic(0.4, 0, 1, 1);

/// Every motion becomes a plain fade of this length when the platform asks
/// for reduced motion.
const int _reducedMs = 150;
const int _introFirstDelayMs = 80;
const int _introStepMs = 60;
const int _introRowMs = 320;
const int _leaveMs = 220;
const int _leaveStepMs = 55;
const int _fadeMs = 160;
const int _resizeMs = 340;
const int _countMs = 220;
const int _toggleCheckMs = 240;
const int _doneIconDelayMs = 90;
const int _doneIconMs = 440;
const int _doneTextDelayMs = 160;
const int _doneTextMs = 300;
const int _doneTotalMs = _doneIconDelayMs + _doneIconMs;
const int _snackSeconds = 5;

int _introTotalMs(int rows) =>
    _introFirstDelayMs + (math.max(rows, 1) - 1) * _introStepMs + _introRowMs;

int _leaveTotalMs(int selected) =>
    _leaveMs + (math.max(selected, 1) - 1) * _leaveStepMs;

/// Progress of one motion inside a timeline that lasts [totalMs]: the window
/// runs from [startMs] to [endMs], shaped by [curve].
double _window(
  double t,
  num startMs,
  num endMs,
  double totalMs,
  Curve curve,
) {
  final begin = (startMs / totalMs).clamp(0.0, 1.0).toDouble();
  final end = (endMs / totalMs).clamp(0.0, 1.0).toDouble();
  if (end <= begin) return t >= end ? 1.0 : 0.0;
  return Interval(begin, end, curve: curve).transform(t);
}

/// The "Tarefas deste registro" block: tasks suggested by one record, each
/// added to Todo only after the user taps the button. The caller calls
/// [CardTasksViewModel.load] once when it creates the view model.
class CardTasksSection extends StatefulWidget {
  const CardTasksSection({
    super.key,
    required this.viewModel,
    required this.onOpenTodo,
  });

  final CardTasksViewModel viewModel;
  final VoidCallback onOpenTodo;

  @override
  State<CardTasksSection> createState() => _CardTasksSectionState();
}

class _CardTasksSectionState extends State<CardTasksSection>
    with TickerProviderStateMixin {
  /// Rows fading and rising in, staggered.
  late final AnimationController _intro = AnimationController(vsync: this);

  /// Rows leaving to the right, and the button fading, while a task is added.
  late final AnimationController _leave = AnimationController(vsync: this);

  /// The added row's icon and text.
  late final AnimationController _done = AnimationController(vsync: this);
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Listenable _motion =
      Listenable.merge([_intro, _leave, _done, _shake]);

  CardTasksPhase? _shownPhase;
  bool _adding = false;
  int _lastCount = 0;
  bool _countUp = true;

  @override
  void dispose() {
    _intro.dispose();
    _leave.dispose();
    _done.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => _content(context, vm),
    );
  }

  Widget _content(BuildContext context, CardTasksViewModel vm) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    // The list stays on screen until the add motion has finished.
    final shown = _adding && vm.phase == CardTasksPhase.added
        ? CardTasksPhase.selecting
        : vm.phase;
    _syncShown(shown, reduce);
    if (shown == CardTasksPhase.loading || shown == CardTasksPhase.hidden) {
      return const SizedBox.shrink();
    }
    final selecting = shown == CardTasksPhase.selecting;
    final count = vm.selectedCount;
    if (count != _lastCount) {
      _countUp = count > _lastCount;
      _lastCount = count;
    }
    final l10n = UserStorage.l10n;

    final content = AnimatedBuilder(
      animation: _motion,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.cardTasksTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (selecting)
                Text(
                  l10n.cardTasksNoDate,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (selecting) ..._selectingBody(vm, reduce) else _addedRow(vm, reduce),
        ],
      ),
    );
    // Reduced motion skips the resize: a zero-length AnimatedSize restarts
    // its animation inside layout.
    if (reduce) return content;
    return AnimatedSize(
      duration: const Duration(milliseconds: _resizeMs),
      curve: _enterCurve,
      alignment: Alignment.topCenter,
      child: content,
    );
  }

  /// Starts the entry motion when the block shows the list or the added row.
  void _syncShown(CardTasksPhase shown, bool reduce) {
    if (shown == _shownPhase) return;
    _shownPhase = shown;
    if (shown != CardTasksPhase.selecting && shown != CardTasksPhase.added) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (shown == CardTasksPhase.selecting) {
        final rows = widget.viewModel.candidates.length;
        _leave.value = 0;
        _intro.duration = Duration(
          milliseconds: reduce ? _reducedMs : _introTotalMs(rows),
        );
        _intro.forward(from: 0);
      } else {
        _done.duration = Duration(
          milliseconds: reduce ? _reducedMs : _doneTotalMs,
        );
        _done.forward(from: 0);
      }
    });
  }

  List<Widget> _selectingBody(CardTasksViewModel vm, bool reduce) {
    final l10n = UserStorage.l10n;
    final introTotal =
        (_intro.duration?.inMilliseconds ?? _introRowMs).toDouble();
    final leaveTotal =
        (_leave.duration?.inMilliseconds ?? _leaveMs).toDouble();
    final children = <Widget>[];
    var leavingOrder = 0;

    for (var i = 0; i < vm.candidates.length; i++) {
      final checked = vm.isSelected(i);
      final start = _introFirstDelayMs + i * _introStepMs;
      final enter = reduce
          ? _intro.value
          : _window(
              _intro.value,
              start,
              start + _introRowMs,
              introTotal,
              _enterCurve,
            );
      final double leave;
      if (checked) {
        final leaveStart = leavingOrder * _leaveStepMs;
        leave = reduce
            ? _leave.value
            : _window(
                _leave.value,
                leaveStart,
                leaveStart + _leaveMs,
                leaveTotal,
                _leaveCurve,
              );
        leavingOrder++;
      } else {
        leave = reduce
            ? _leave.value
            : _window(_leave.value, 0, _fadeMs, leaveTotal, Curves.linear);
      }
      children.add(
        Opacity(
          opacity: (enter * (1 - leave)).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(
              checked && !reduce ? 18 * leave : 0,
              reduce ? 0 : 6 * (1 - enter),
            ),
            child: _TaskRow(
              text: vm.candidates[i].text,
              checked: checked,
              reduce: reduce,
              onTap: () => vm.toggle(i),
            ),
          ),
        ),
      );
    }

    final fade = reduce
        ? _leave.value
        : _window(_leave.value, 0, _fadeMs, leaveTotal, Curves.linear);
    children
      ..add(const SizedBox(height: 14))
      ..add(
        Opacity(
          opacity: (1 - fade).clamp(0.0, 1.0),
          child: Row(
            children: [
              Expanded(child: _actionButton(vm, reduce)),
              const SizedBox(width: 8),
              TextButton(
                onPressed: vm.busy ? null : _dismiss,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
                child: Text(l10n.cardTasksNotNow),
              ),
            ],
          ),
        ),
      );
    return children;
  }

  Widget _actionButton(CardTasksViewModel vm, bool reduce) {
    final l10n = UserStorage.l10n;
    final count = vm.selectedCount;
    final enabled = count > 0;
    final label =
        enabled ? l10n.cardTasksAddButton(count) : l10n.cardTasksCheckOne;
    final shakeT = _shake.value;
    final shake = reduce ? 0.0 : 5 * math.sin(shakeT * 4 * math.pi) * (1 - shakeT);
    void onTap() {
      if (enabled) {
        _addSelected();
      } else {
        _shake.forward(from: 0);
      }
    }

    final VoidCallback? tap = vm.busy ? null : onTap;
    return Transform.translate(
      offset: Offset(shake, 0),
      child: Semantics(
        button: true,
        enabled: enabled && !vm.busy,
        label: label,
        excludeSemantics: true,
        onTap: tap,
        child: SizedBox(
          height: 44,
          child: Material(
            color: enabled ? AppColors.primary : AppColors.taskDisabledFill,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: tap,
              child: Center(
                child: AnimatedSwitcher(
                  duration: Duration(milliseconds: reduce ? _reducedMs : _countMs),
                  transitionBuilder: (child, animation) => AnimatedBuilder(
                    animation: animation,
                    child: child,
                    builder: (context, child) => Opacity(
                      opacity: animation.value,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          reduce
                              ? 0
                              : (1 - animation.value) *
                                  10 *
                                  (_countUp ? 1 : -1),
                        ),
                        child: child,
                      ),
                    ),
                  ),
                  child: Text(
                    label,
                    key: ValueKey(label),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: enabled
                          ? AppColors.taskOnAccent
                          : AppColors.taskMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _addedRow(CardTasksViewModel vm, bool reduce) {
    final l10n = UserStorage.l10n;
    final count = vm.addedCount;
    final t = _done.value;
    final iconT = reduce
        ? t
        : _window(
            t,
            _doneIconDelayMs,
            _doneIconDelayMs + _doneIconMs,
            _doneTotalMs.toDouble(),
            _enterCurve,
          );
    final textT = reduce
        ? t
        : _window(
            t,
            _doneTextDelayMs,
            _doneTextDelayMs + _doneTextMs,
            _doneTotalMs.toDouble(),
            _enterCurve,
          );
    final label = l10n.cardTasksInTodo(count);
    return InkWell(
      onTap: widget.onOpenTodo,
      child: Semantics(
        button: true,
        label: '$label, ${l10n.cardTasksOpen}',
        excludeSemantics: true,
        onTap: widget.onOpenTodo,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Opacity(
                opacity: reduce ? iconT : 1.0,
                child: Transform.scale(
                  scale: reduce ? 1.0 : math.max(iconT, 0.001),
                  child: Transform.rotate(
                    angle: reduce ? 0 : -math.pi / 2 * (1 - iconT),
                    child: const Icon(
                      Icons.check_circle,
                      size: 22,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Opacity(
                  opacity: textT,
                  child: Transform.translate(
                    offset: Offset(reduce ? 0 : -6 * (1 - textT), 0),
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.taskBody,
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                l10n.cardTasksOpen,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primary,
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addSelected() async {
    final vm = widget.viewModel;
    if (vm.busy || vm.selectedCount == 0) return;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final totalMs = reduce ? _reducedMs : _leaveTotalMs(vm.selectedCount);
    _leave.duration = Duration(milliseconds: totalMs);
    setState(() => _adding = true);
    _leave.forward(from: 0);
    final saving = vm.addSelected();
    if (!reduce) await Future<void>.delayed(Duration(milliseconds: totalMs));
    final ok = await saving;
    if (!mounted) return;
    setState(() => _adding = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserStorage.l10n.cardTasksAdded(vm.addedCount)),
          duration: const Duration(seconds: _snackSeconds),
          action: SnackBarAction(
            label: UserStorage.l10n.todoUndo,
            onPressed: _undo,
          ),
        ),
      );
    } else {
      _leave.reverse();
      _showError(vm.errorMessage);
    }
  }

  Future<void> _undo() async {
    final vm = widget.viewModel;
    final ok = await vm.undo();
    if (!mounted || ok) return;
    _showError(vm.errorMessage);
  }

  Future<void> _dismiss() async {
    final vm = widget.viewModel;
    final ok = await vm.dismiss();
    if (!mounted || ok) return;
    _showError(vm.errorMessage);
  }

  void _showError(String? message) {
    if (message == null || !mounted) return;
    ToastHelper.showError(context, message);
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.text,
    required this.checked,
    required this.reduce,
    required this.onTap,
  });

  final String text;
  final bool checked;
  final bool reduce;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: checked,
      label: text,
      onTap: onTap,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.taskDivider),
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  _Checkbox(checked: checked, reduce: reduce),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        color: checked
                            ? AppColors.textPrimary
                            : AppColors.taskMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.checked, required this.reduce});

  final bool checked;
  final bool reduce;

  @override
  Widget build(BuildContext context) {
    // Keyed by the state so each toggle replays the pop from its start.
    return TweenAnimationBuilder<double>(
      key: ValueKey(checked),
      tween: Tween<double>(begin: reduce ? 1.0 : 0.82, end: 1.0),
      duration: const Duration(milliseconds: 200),
      curve: _enterCurve,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: checked ? AppColors.primary : null,
          borderRadius: BorderRadius.circular(6),
          border: checked
              ? null
              : Border.all(color: AppColors.taskCheckBorder, width: 1.5),
        ),
        child: checked ? _CheckMark(reduce: reduce) : null,
      ),
    );
  }
}

class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.reduce});

  final bool reduce;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: _toggleCheckMs),
      curve: _enterCurve,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: reduce ? 0 : -25 * math.pi / 180 * (1 - t),
          child: Transform.scale(
            scale: reduce ? 1 : 0.3 + 0.7 * t,
            child: child,
          ),
        ),
      ),
      child: const Icon(Icons.check, size: 14, color: AppColors.onPrimary),
    );
  }
}
