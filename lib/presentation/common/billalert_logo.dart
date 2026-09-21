import 'package:flutter/material.dart';

/// Local vector artwork from the approved Figma logo (253:2).
/// Brand colors are fixed in both themes, matching the Android launcher icon.
class BillAlertLogo extends StatelessWidget {
  const BillAlertLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'BillAlert logo',
    child: CustomPaint(
      size: Size.square(size),
      painter: const _BillAlertLogoPainter(),
    ),
  );
}

class _BillAlertLogoPainter extends CustomPainter {
  const _BillAlertLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 512, size.height / 512);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 512, 512),
        const Radius.circular(128),
      ),
      Paint()..color = const Color(0xFF4B6C25),
    );
    // Match the padded, optically centered legacy launcher artwork.
    canvas.translate(50.18, 55.51);
    canvas.scale(0.82);
    final white = Paint()..color = const Color(0xFFFAFCF5);
    final yellow = Paint()..color = const Color(0xFFFFC928);
    final stroke = Paint()
      ..color = const Color(0xFFFAFCF5)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 10;
    final chimney = Path()
      ..moveTo(354, 145)
      ..lineTo(354, 84)
      ..lineTo(388, 84)
      ..lineTo(388, 175);
    canvas.drawPath(chimney, white);
    canvas.drawPath(chimney, stroke);
    stroke.strokeWidth = 30;
    canvas.drawPath(
      Path()
        ..moveTo(64, 225)
        ..lineTo(243, 67)
        ..lineTo(423, 225),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(104, 259)
        ..lineTo(104, 412)
        ..lineTo(273, 412),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(261, 174)
        ..quadraticBezierTo(267, 168, 266, 177)
        ..lineTo(239, 252)
        ..lineTo(288, 252)
        ..quadraticBezierTo(296, 252, 291, 259)
        ..lineTo(220, 366)
        ..quadraticBezierTo(213, 376, 216, 364)
        ..lineTo(234, 291)
        ..lineTo(185, 291)
        ..quadraticBezierTo(178, 291, 183, 284)
        ..close(),
      white,
    );
    canvas.drawPath(
      Path()
        ..moveTo(369, 279)
        ..lineTo(369, 269)
        ..cubicTo(369, 253, 393, 253, 393, 269)
        ..lineTo(393, 279)
        ..close(),
      yellow,
    );
    canvas.drawPath(
      Path()
        ..moveTo(362, 415)
        ..cubicTo(362, 444, 400, 444, 400, 415)
        ..close(),
      yellow,
    );
    canvas.drawPath(
      Path()
        ..moveTo(313, 390)
        ..cubicTo(325, 377, 326, 362, 326, 340)
        ..lineTo(326, 326)
        ..cubicTo(326, 298, 349, 278, 381, 278)
        ..cubicTo(413, 278, 436, 298, 436, 326)
        ..lineTo(436, 340)
        ..cubicTo(436, 362, 437, 377, 449, 390)
        ..cubicTo(455, 397, 452, 405, 442, 405)
        ..lineTo(320, 405)
        ..cubicTo(310, 405, 307, 397, 313, 390)
        ..close(),
      yellow,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BillAlertLogoPainter oldDelegate) => false;
}
