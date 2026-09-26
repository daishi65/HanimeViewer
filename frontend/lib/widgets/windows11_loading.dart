import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Windows 11 风格的 Loading 动画。
///
/// 视觉：一条极细的圆弧，尾部匀速旋转，头部按正弦波伸缩（弧长变化）。
class Windows11Loading extends StatefulWidget {
  /// 整体尺寸（正方形边长）
  final double size;

  /// 圆弧颜色。为空时跟随主题：
  /// - 深色主题：白偏灰（0xFFE0E0E0）
  /// - 浅色主题：黑偏灰（0xFF5A5A5A）
  final Color? color;

  /// 圆弧粗细。为空时按 size 自动推算（size / 14，限制 2.5 ~ 5.0）
  final double? strokeWidth;

  /// 一个完整循环的时长
  final Duration duration;

  /// 圆弧最短时的角度（弧度）
  final double minSweep;

  /// 圆弧最长时的角度（弧度）
  final double maxSweep;

  const Windows11Loading({
    super.key,
    this.size = 48,
    this.color,
    this.strokeWidth,
    this.duration = const Duration(milliseconds: 1000),
    this.minSweep = 0.40 * math.pi,
    this.maxSweep = 1.00 * math.pi,
  });

  @override
  State<Windows11Loading> createState() =>
      _Windows11LoadingState();
}

class _Windows11LoadingState extends State<Windows11Loading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 颜色：优先用调用方传入的，否则跟随主题
    final color = widget.color ??
        (Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFFE0E0E0)
            : const Color(0xFF5A5A5A));

    // 线宽：默认按 size / 14，限制 2.5 ~ 5.0
    final strokeWidth = widget.strokeWidth ??
        (widget.size / 14).clamp(2.5, 5.0);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _Windows11LoadingPainter(
              progress: _controller.value,
              color: color,
              strokeWidth: strokeWidth,
              minSweep: widget.minSweep,
              maxSweep: widget.maxSweep,
            ),
          );
        },
      ),
    );
  }
}

class _Windows11LoadingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final double minSweep;
  final double maxSweep;

  _Windows11LoadingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.minSweep,
    required this.maxSweep,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final rect = Rect.fromCircle(
      center: center,
      radius: radius,
    );

    // 尾部角度：匀速前进，每周期 2π
    final startAngle =
        progress * 2 * math.pi - math.pi / 2;

    // 弧长变化：正弦波 0 → 1 → 0
    final raw =
        (1 - math.cos(progress * 2 * math.pi)) / 2;
    final lengthProgress = math.pow(raw, 0.9).toDouble();

    final sweepAngle =
        minSweep + (maxSweep - minSweep) * lengthProgress;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _Windows11LoadingPainter old) {
    return old.progress != progress ||
        old.color != color ||
        old.strokeWidth != strokeWidth ||
        old.minSweep != minSweep ||
        old.maxSweep != maxSweep;
  }
}