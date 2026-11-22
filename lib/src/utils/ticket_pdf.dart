import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/database.dart';
import '../services/thermal_printer_service.dart';
import 'format.dart';

String ticketDisplayBet(String raw) {
  final n = raw
      .trim()
      .toLowerCase()
      .replaceAll('-', '/')
      .replaceAll('_', '/')
      .replaceAll(' ', '');
  if (n == 'all' ||
      n == 'all/box' ||
      n == 'all/straight' ||
      (n.contains('straight') && n.contains('box')) ||
      n == 'straightbox' ||
      n == 'str/box' ||
      n == 'strbox')
    return 'ST/BOX';
  if (n == 'straight') return 'ST';
  if (n == 'box') return 'BOX';
  if (n.contains('combo')) return 'COMBO';
  return raw;
}

bool is80mmPrinter(String? printerType) =>
    normalizePrinterType(printerType) == kPrinter80;

/// Sizes matching 203 DPI thermal printer dots:
/// 58mm printable ≈ 48mm = 384 dots — 80mm printable ≈ 72mm = 576 dots
class ThermalStyle {
  final bool mm80;
  const ThermalStyle(this.mm80);
  factory ThermalStyle.fromType(String? printerType) =>
      ThermalStyle(is80mmPrinter(printerType));

  double get pageWidthMm => mm80 ? 72 : 48;
  double get marginMm => mm80 ? 1.0 : 0.6;
  double get company => mm80 ? 18 : 11;
  double get kicker => mm80 ? 10 : 6.5;
  double get game => mm80 ? 14 : 9;
  double get total => mm80 ? 16 : 11;
  double get draw => mm80 ? 12 : 7.5;
  double get period => mm80 ? 10 : 6.5;
  double get numbers => mm80 ? 22 : 12;
  double get numbersTracking => mm80 ? 1.4 : 0.3;
  double get meta => mm80 ? 12 : 7;
  double get section => mm80 ? 12 : 7.5;
  double get qr => mm80 ? 100 : 62;
  double get tiny => mm80 ? 9 : 6;
  double get gap => mm80 ? 6 : 3;
  double get pad => mm80 ? 7 : 3;
}

PdfPageFormat getTicketPageFormat(String? printerType) {
  final s = ThermalStyle.fromType(printerType);
  return PdfPageFormat(
    s.pageWidthMm * PdfPageFormat.mm,
    double.infinity,
    marginAll: s.marginMm * PdfPageFormat.mm,
  );
}

pw.Widget _fitText(
  String text,
  pw.TextStyle style, {
  pw.TextAlign align = pw.TextAlign.center,
}) {
  final alignment = align == pw.TextAlign.left
      ? pw.Alignment.centerLeft
      : align == pw.TextAlign.right
      ? pw.Alignment.centerRight
      : pw.Alignment.center;
  return pw.FittedBox(
    fit: pw.BoxFit.scaleDown,
    alignment: alignment,
    child: pw.Text(text, style: style, maxLines: 1),
  );
}

pw.Widget _playRow(
  ThermalStyle s, {
  required String numbers,
  required String bet,
  required String amount,
}) {
  final metaStyle = pw.TextStyle(
    fontSize: s.meta,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.black,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2.5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          flex: 3,
          child: _fitText(
            numbers,
            pw.TextStyle(
              font: pw.Font.courierBold(),
              fontSize: s.numbers,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: s.numbersTracking,
              color: PdfColors.black,
            ),
            align: pw.TextAlign.left,
          ),
        ),
        pw.SizedBox(width: 2),
        pw.Flexible(
          flex: 4,
          child: _fitText(
            '$bet  $amount',
            metaStyle,
            align: pw.TextAlign.right,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _playsBlock(
  ThermalStyle s,
  String label,
  List<Map<String, dynamic>> lst,
) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Text(
        label,
        style: pw.TextStyle(
          fontSize: s.section,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
      pw.SizedBox(height: 2),
      for (final l in lst)
        _playRow(
          s,
          numbers: (l['numbers'] as String).replaceAll(',', ' '),
          bet: ticketDisplayBet(l['betType']),
          amount: fmtMoney(l['amount']),
        ),
    ],
  );
}

pw.Widget buildTicketPdfWidget(
  Map<String, dynamic> t,
  List<Map<String, dynamic>> lines,
  String company,
  String footer, {
  String? printerType,
}) {
  final s = ThermalStyle.fromType(printerType);
  final isWinning = t['status'] == 'winning';
  final isPaid = t['status'] == 'paid';
  final prize = t['prizeAmount'] != null ? fmtMoney(t['prizeAmount']) : null;
  final total = fmtMoney(t['total'] ?? t['amount']);
  final id = '${t['barcode'] ?? t['id']}';
  final customerRaw = t['customerName'];
  final customerName = (customerRaw is String && customerRaw.trim().isNotEmpty)
      ? customerRaw.trim()
      : 'Cash Customer';
  pw.Widget winner() {
    if (!isWinning && !isPaid) return pw.SizedBox.shrink();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4),
      child: _fitText(
        isPaid ? 'PAID • Prize $prize' : 'WINNER • Prize $prize',
        pw.TextStyle(
          fontSize: s.meta,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.green900,
        ),
      ),
    );
  }

  String _classify(Map<String, dynamic> l) {
    final pid = (l['periodId'] ?? '').toString().toUpperCase();
    if (pid.contains('MIDDAY') ||
        pid.contains('MORNING') ||
        pid.contains('MID_'))
      return 'MIDDAY';
    if (pid.contains('EVENING') || pid.contains('EVE') || pid.contains('NIGHT'))
      return 'EVENING';
    final dn = (l['drawName'] ?? '').toString().toUpperCase();
    if (dn.contains('MIDDAY') || dn.contains('MORNING')) return 'MIDDAY';
    if (dn.contains('EVENING')) return 'EVENING';
    final dt = (l['drawType'] ?? '').toString().toUpperCase();
    if (dt.contains('MIDDAY') || dt.contains('MORNING') || dt.contains('MID'))
      return 'MIDDAY';
    if (dt.contains('EVENING') || dt.contains('EVE')) return 'EVENING';
    return '';
  }

  pw.Widget plays() {
    if (lines.isEmpty) {
      // fallback single: try to show period header from ticket drawName if available
      final dn = (t['drawName'] ?? '').toString();
      String? header;
      final up = dn.toUpperCase();
      if (up.contains('MIDDAY') || up.contains('MORNING'))
        header = 'MIDDAY';
      else if (up.contains('EVENING'))
        header = 'EVENING';
      return pw.Column(
        children: [
          if (header != null) ...[
            pw.Text(
              header,
              style: pw.TextStyle(
                fontSize: s.section,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
            pw.SizedBox(height: 2),
          ],
          _fitText(
            (t['numbers'] as String? ?? '').replaceAll(',', ' '),
            pw.TextStyle(
              font: pw.Font.courierBold(),
              fontSize: s.numbers + 2,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: s.numbersTracking,
              color: PdfColors.black,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            '${ticketDisplayBet(t['betType'] ?? '')} • ${fmtMoney(t['amount'])}',
            style: pw.TextStyle(
              fontSize: s.meta,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
          winner(),
        ],
      );
    }
    final mid = lines.where((l) => _classify(l) == 'MIDDAY').toList();
    final eve = lines.where((l) => _classify(l) == 'EVENING').toList();
    final other = lines.where((l) => _classify(l) == '').toList();
    final hasMid = mid.isNotEmpty;
    final hasEve = eve.isNotEmpty;
    final hasOther = other.isNotEmpty;
    // When all lines are uncategorized -> show them without a header (legacy fallback)
    if (!hasMid && !hasEve) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          for (final l in lines)
            _playRow(
              s,
              numbers: (l['numbers'] as String).replaceAll(',', ' '),
              bet: ticketDisplayBet(l['betType']),
              amount: fmtMoney(l['amount']),
            ),
          pw.SizedBox(height: 4),
          pw.Divider(thickness: 0.5, color: PdfColors.black),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL',
                style: pw.TextStyle(
                  fontSize: s.game,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
              pw.Text(
                total,
                style: pw.TextStyle(
                  fontSize: s.total,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
            ],
          ),
          winner(),
        ],
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (hasMid) _playsBlock(s, 'MIDDAY', mid),
        if (hasMid && hasEve) ...[
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              '- - - - - - - - - -',
              style: pw.TextStyle(fontSize: s.tiny, color: PdfColors.black),
            ),
          ),
          pw.SizedBox(height: 2),
        ],
        if (hasEve) _playsBlock(s, 'EVENING', eve),
        if (hasOther) ...[
          if (hasMid || hasEve) ...[
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                '- - - - - - - - - -',
                style: pw.TextStyle(fontSize: s.tiny, color: PdfColors.black),
              ),
            ),
            pw.SizedBox(height: 2),
          ],
          for (final l in other)
            _playRow(
              s,
              numbers: (l['numbers'] as String).replaceAll(',', ' '),
              bet: ticketDisplayBet(l['betType']),
              amount: fmtMoney(l['amount']),
            ),
        ],
        pw.SizedBox(height: 4),
        pw.Divider(thickness: 0.5, color: PdfColors.black),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'TOTAL',
              style: pw.TextStyle(
                fontSize: s.game,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
            pw.Text(
              total,
              style: pw.TextStyle(
                fontSize: s.total,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ],
        ),
        winner(),
      ],
    );
  }

  // invoice meta widget — moved under SALES REPORT header per user request
  pw.Widget invoiceMeta() {
    if (s.mm80) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Ticket ID',
                  style: pw.TextStyle(
                    fontSize: s.tiny,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                _fitText(
                  id,
                  pw.TextStyle(
                    fontSize: s.meta,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                  align: pw.TextAlign.left,
                ),
                _fitText(
                  'Customer: $customerName',
                  pw.TextStyle(
                    fontSize: s.tiny,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                  align: pw.TextAlign.left,
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 6),
          pw.SizedBox(
            width: 96,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                _fitText(
                  'Date: ${fmtDate(t['createdAt'])}',
                  pw.TextStyle(
                    fontSize: s.tiny,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                  align: pw.TextAlign.right,
                ),
                pw.SizedBox(height: 1),
                _fitText(
                  'Op: ${t['operatorName']}',
                  pw.TextStyle(
                    fontSize: s.tiny,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                  align: pw.TextAlign.right,
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'Ticket ID',
            style: pw.TextStyle(
              fontSize: s.tiny,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
          _fitText(
            id,
            pw.TextStyle(
              fontSize: s.meta,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
            align: pw.TextAlign.left,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Date: ${fmtDate(t['createdAt'])}',
            style: pw.TextStyle(
              fontSize: s.tiny,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
          pw.Text(
            'Op: ${t['operatorName']}',
            style: pw.TextStyle(
              fontSize: s.tiny,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
          _fitText(
            'Customer: $customerName',
            pw.TextStyle(
              fontSize: s.tiny,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
            align: pw.TextAlign.left,
          ),
        ],
      );
    }
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      _fitText(
        'INVOICE REPORT',
        pw.TextStyle(
          fontSize: s.kicker,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Divider(thickness: 0.6, color: PdfColors.black),
      pw.SizedBox(height: s.gap),
      // Invoice number + date directly under the sales report
      invoiceMeta(),
      pw.SizedBox(height: s.gap),
      pw.Divider(thickness: 0.4, color: PdfColors.grey300),
      pw.SizedBox(height: s.gap),
      plays(),
      pw.SizedBox(height: s.gap),
      pw.Center(
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: id,
          width: s.qr,
          height: s.qr,
        ),
      ),
      pw.SizedBox(height: 2),
      _fitText(
        id,
        pw.TextStyle(
          fontSize: s.tiny,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.4,
          color: PdfColors.black,
        ),
      ),
      pw.Divider(thickness: 0.5, color: PdfColors.black),
      pw.Center(
        child: pw.Text(
          footer.trim().isEmpty ? '' : footer.trim(),
          style: pw.TextStyle(
            fontSize: s.tiny,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Center(
        child: pw.Text(
          '--- CUT HERE ---',
          style: pw.TextStyle(fontSize: s.tiny, color: PdfColors.black),
        ),
      ),
    ],
  );
}

/// Attempts direct printing on the default printer if present — returns null if no printer exists
Future<PrintJobResult?> tryDirectPrintTicket(
  BuildContext context,
  Map<String, dynamic> ticket,
  List<Map<String, dynamic>> lines,
) async {
  try {
    final db = context.read<AppDatabase>();
    final cfg = await db.getAppConfig();
    final map = {for (var c in cfg) c['key'] as String: c['value'] as String};
    if ((map['default_printer_url'] ?? '').trim().isEmpty) return null;
    final company = map['company_name'] ?? 'NY Lottery POS';
    final footer = map['ticket_footer'] ?? '';
    final printerType = normalizePrinterType(map['printer_type']);
    final format = getTicketPageFormat(printerType);
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (_) => buildTicketPdfWidget(
          ticket,
          lines,
          company,
          footer,
          printerType: printerType,
        ),
      ),
    );
    final escPos = await buildTicketEscPos(
      ticket: ticket,
      lines: lines,
      company: company,
      footer: footer,
      printerType: printerType,
    );
    return await printPdfBytes(
      db: db,
      pdfBytes: await doc.save(),
      format: format,
      jobName: 'Ticket ${ticket['id']}',
      bluetoothBytes: escPos,
    );
  } catch (e) {
    return PrintJobResult.fail('$e');
  }
}
