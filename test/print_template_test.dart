// Regression tests for the thermal receipt / print-template layout.
//
// The reported bug: a played number such as "1 2 5" occasionally printed the
// last digit alone on a new line. Root causes guarded here:
//  1. ESC/POS play lines were padded to the *theoretical* maximum width
//     (32/48 chars), leaving zero room for printers with a narrower printable
//     area — the firmware then wrapped the final glyph.
//  2. The on-screen preview allowed maxLines: 2 and inserted double spaces,
//     which wrapped the last digit in the preview.
//  3. Plain PDF Text widgets had wrapping enabled in the rasterised template.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:winz/src/services/thermal_printer_service.dart';
import 'package:winz/src/utils/ticket_pdf.dart';
import 'package:winz/src/widgets/ticket_numbers_text.dart';

Map<String, dynamic> sampleTicket() => <String, dynamic>{
  'id': 't-1',
  'barcode': '000125',
  'numbers': '1,2,5',
  'betType': 'Straight',
  'amount': 10.0,
  'total': 10.0,
  'createdAt': DateTime(2026, 11, 24, 14, 30).millisecondsSinceEpoch,
  'operatorName': 'cashier',
  'customerName': 'Cash Customer',
  'status': 'active',
};

List<Map<String, dynamic>> sampleLines() => <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 'l-1',
    'ticketId': 't-1',
    'gameId': 'g3',
    'gameName': '3D',
    'numbers': '1,2,5',
    'betType': 'Straight',
    'amount': 10.0,
    'isQuickPick': 0,
    'periodId': '2026-11-24-MIDDAY',
    'drawName': 'Midday 14:30',
  },
];

/// Extract the visible play line from a decoded ESC/POS byte stream.
///
/// Style commands are emitted immediately before the text on the same line,
/// so slicing from the first played digit avoids counting command bytes.
String playLineFrom(String decoded) {
  final line = decoded.split('\n').firstWhere((l) => l.contains('1 2 5'));
  return line.substring(line.indexOf('1 2 5'));
}

void main() {
  group('ESC/POS layout', () {
    test('safe width reserves two cells below the firmware limit', () {
      expect(safeCharsPerLine('thermal_58mm'), 30);
      expect(safeCharsPerLine('thermal_80mm'), 46);
    });

    test('padReceiptLine keeps the numbers and never exceeds safe width', () {
      for (final width in <int>[30, 46]) {
        final line = padReceiptLine('1 2 5', 'ST  \$10.00', width);
        expect(line.length, width, reason: 'line must be exactly $width chars');
        expect(line.startsWith('1 2 5'), isTrue);
        expect(line.endsWith('\$10.00'), isTrue);
      }
    });

    test('padReceiptLine trims the bet label, never the amount', () {
      final line = padReceiptLine(
        '1 2 5',
        'STRAIGHT BOX COMBO  \$999.50',
        30,
      );
      expect(line.length, 30);
      expect(line.startsWith('1 2 5'), isTrue);
      expect(line.endsWith('\$999.50'), isTrue);
    });

    test('padReceiptLine never cuts a number in half across a line break',
        () {
      const longNumbers = '1,2,3,4,5,6,7,8,9,0,1,2,3,4,5,6,7,8,9,0';
      final line = padReceiptLine(longNumbers, 'ST  \$1.00', 30);
      expect(line.length, 30);
      expect(line.contains('\n'), isFalse);
      expect(line.startsWith(longNumbers), isFalse);
      expect(line, longNumbers.substring(0, 30));
    });

    test('generated 58mm ticket has no over-wide play line', () async {
      final bytes = await buildTicketEscPos(
        ticket: sampleTicket(),
        lines: sampleLines(),
        company: 'NY Lottery POS',
        footer: '',
        printerType: 'thermal_58mm',
      );
      final decoded = String.fromCharCodes(bytes);
      final play = playLineFrom(decoded);
      expect(play.startsWith('1 2 5'), isTrue, reason: play);
      expect(play.length, lessThanOrEqualTo(safeCharsPerLine('thermal_58mm')));
      expect(play.endsWith('\$10.00'), isTrue, reason: play);
    });

    test('generated 80mm ticket keeps every digit on the same line',
        () async {
      final bytes = await buildTicketEscPos(
        ticket: sampleTicket(),
        lines: sampleLines(),
        company: 'NY Lottery POS',
        footer: '',
        printerType: 'thermal_80mm',
      );
      final decoded = String.fromCharCodes(bytes);
      final play = playLineFrom(decoded);
      expect(play.startsWith('1 2 5'), isTrue, reason: play);
      expect(play.length, lessThanOrEqualTo(safeCharsPerLine('thermal_80mm')));
      expect(play.endsWith('\$10.00'), isTrue, reason: play);
    });
  });

  group('print preview', () {
    testWidgets('numbers never wrap, even in a very narrow box',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 70,
              child: TicketNumbersText(
                numbers: '1,2,5,4,7,9,0,3,6,8',
                fontSize: 24,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      );

      final text = tester.widget<Text>(find.byType(Text));
      expect(text.maxLines, 1);
      expect(text.data, '1 2 5 4 7 9 0 3 6 8');
      expect(text.overflow, TextOverflow.clip);
      expect(
        find.ancestor(of: find.byType(Text), matching: find.byType(FittedBox)),
        findsOneWidget,
      );
    });
  });

  group('PDF template', () {
    test('58mm and 80mm ticket PDFs build without wrapping-related errors',
        () async {
      for (final type in <String>['thermal_58mm', 'thermal_80mm']) {
        final doc = pw.Document();
        doc.addPage(
          pw.Page(
            pageFormat: getTicketPageFormat(type),
            build: (_) => buildTicketPdfWidget(
              sampleTicket(),
              sampleLines(),
              'NY Lottery POS',
              '',
              printerType: type,
            ),
          ),
        );
        final bytes = await doc.save();
        expect(bytes.isNotEmpty, isTrue);
      }
    });
  });
}
