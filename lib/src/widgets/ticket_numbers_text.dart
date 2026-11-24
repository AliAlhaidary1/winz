import 'package:flutter/material.dart';

/// Displays the numbers played on a ticket, always on a single line.
///
/// `FittedBox(scaleDown)` shrinks long combinations instead of letting the
/// `Text` wrap. Wrapping is what produced the reported bug where the last
/// digit (e.g. the "5" of "1 2 5") appeared alone on its own line.
class TicketNumbersText extends StatelessWidget {
  final String numbers;
  final double fontSize;
  final double letterSpacing;
  final TextStyle style;
  final TextAlign textAlign;

  const TicketNumbersText({
    super.key,
    required this.numbers,
    required this.fontSize,
    required this.letterSpacing,
    this.style = const TextStyle(),
    this.textAlign = TextAlign.center,
  });

  /// "1,2,5" -> "1 2 5" (single spaces, never double — double spaces used to
  /// push the last digit onto a new line on narrow screens).
  static String normalize(String raw) =>
      raw.replaceAll(RegExp(r'\s*,\s*'), ' ').trim();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text(
        normalize(numbers),
        style: style.copyWith(
          fontFamily: 'Courier',
          fontWeight: FontWeight.w900,
          fontSize: fontSize,
          letterSpacing: letterSpacing,
        ),
        maxLines: 1,
        overflow: TextOverflow.clip,
        textAlign: textAlign,
      ),
    );
  }
}
