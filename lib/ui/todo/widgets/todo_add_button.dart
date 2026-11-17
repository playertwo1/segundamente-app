import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The round + button of the Todo screen, drawn with the home screen asset at
/// 72 dp (the visible circle is about 56 dp). Presses scale 1 to 0.92 and back.
class TodoAddButton extends StatefulWidget {
  const TodoAddButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<TodoAddButton> createState() => _TodoAddButtonState();
}

class _TodoAddButtonState extends State<TodoAddButton>
    with SingleTickerProviderStateMixin {
  static const _leg = Duration(milliseconds: 140);

  late final AnimationController _scale = AnimationController(
    vsync: this,
    duration: _leg,
    lowerBound: 0.92,
    upperBound: 1,
    value: 1,
  );

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  Future<void> _press() async {
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onTap();
      return;
    }
    await _scale.animateTo(0.92, duration: _leg, curve: Curves.easeOut);
    if (!mounted) return;
    unawaited(_scale.animateTo(1, duration: _leg, curve: Curves.easeOut));
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _press,
        child: ScaleTransition(
          scale: _scale,
          child: SizedBox(
            width: 72,
            height: 72,
            child: SvgPicture.asset(
              'assets/icons/nav_add_button.svg',
              width: 72,
              height: 72,
            ),
          ),
        ),
      );
}
