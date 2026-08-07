import 'package:flutter/material.dart';

class PulsingRadar extends StatefulWidget {
  final Widget child;
  final Color color;

  const PulsingRadar({
    super.key,
    required this.child,
    this.color = Colors.blue,
  });

  @override
  State<PulsingRadar> createState() => _PulsingRadarState();
}

class _PulsingRadarState extends State<PulsingRadar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 100 + (_controller.value * 200),
              height: 100 + (_controller.value * 200),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(
                  alpha: (1.0 - _controller.value) * 0.3,
                ),
              ),
            ),
            Container(
              width: 100 + (_controller.value * 100),
              height: 100 + (_controller.value * 100),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(
                  alpha: (1.0 - _controller.value) * 0.5,
                ),
              ),
            ),
            widget.child,
          ],
        );
      },
    );
  }
}
