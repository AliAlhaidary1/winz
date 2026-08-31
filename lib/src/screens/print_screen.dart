import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../data/database.dart';
import '../utils/format.dart';

class PrintScreen extends StatelessWidget {
  final Map<String, dynamic>? ticket;
  const PrintScreen({super.key, this.ticket});

  pw.Widget _pdfTicket(Map<String, dynamic> t, String company, String footer) {
    final numbers = (t['numbers'] as String).replaceAll(',', '  ');
    final isWinning = t['status'] == 'winning';
    final isPaid = t['status'] == 'paid';
    final prize = t['prizeAmount'] != null ? fmtMoney(t['prizeAmount']) : null;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(company, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text('NY LOTTERY OFFICIAL', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        pw.Divider(thickness: 0.5),
        pw.Text('${t['gameName']} • ${t['betType']}'.toUpperCase(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text('${t['drawName'] ?? 'Draw: -'}', style: const pw.TextStyle(fontSize: 8)),
        pw.Text('Draw Period: ${_periodFromName(t['drawName'])}', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Column(
            children: [
              pw.Text(numbers, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, letterSpacing: 4)),
              pw.SizedBox(height: 2),
              pw.Text('${t['betType']} • ${fmtMoney(t['amount'])}', style: const pw.TextStyle(fontSize: 9)),
              if (isWinning || isPaid)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Text(isPaid ? 'PAID • Prize $prize' : 'WINNER • Prize $prize', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Ticket ID:', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
                pw.Text('${t['id']}', style: const pw.TextStyle(fontSize: 7)),
                pw.SizedBox(height: 2),
                pw.Text('Serial:', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
                pw.Text('${t['serialNumber']}', style: const pw.TextStyle(fontSize: 7)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Date:', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
                pw.Text(fmtDate(t['createdAt']), style: const pw.TextStyle(fontSize: 7)),
                pw.SizedBox(height: 2),
                pw.Text('Operator:', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
                pw.Text('${t['operatorName']}', style: const pw.TextStyle(fontSize: 7)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Center(child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: t['barcode'] ?? t['id'], width: 90, height: 90)),
        pw.SizedBox(height: 2),
        pw.Text('${t['barcode'] ?? t['id']}', style: pw.TextStyle(fontSize: 6, letterSpacing: 1, color: PdfColors.grey700)),
        pw.Divider(thickness: 0.5),
        pw.Text(footer, style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600), textAlign: pw.TextAlign.center),
        pw.Text('Keep ticket safe. Must be 18+ to play.', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600), textAlign: pw.TextAlign.center),
        pw.SizedBox(height: 2),
        pw.Text('--- CUT HERE ---', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey400)),
      ],
    );
  }

  static String _periodFromName(String? name) {
    if (name == null) return '-';
    if (name.contains('Midday')) return 'Midday';
    if (name.contains('Evening')) return 'Evening';
    if (name.contains('Night')) return 'Night';
    return 'Standard';
  }

  Future<void> _printPdf(BuildContext context, Map<String, dynamic> t) async {
    final db = context.read<AppDatabase>();
    final cfg = await db.getAppConfig();
    final map = {for (var c in cfg) c['key'] as String: c['value'] as String};
    final company = map['company_name'] ?? 'NY Lottery POS';
    final footer = map['ticket_footer'] ?? 'Good luck! Please play responsibly.';
    final doc = pw.Document();
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.roll80, build: (_) => _pdfTicket(t, company, footer)));
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  Future<void> _sharePdf(BuildContext context, Map<String, dynamic> t) async {
    final db = context.read<AppDatabase>();
    final cfg = await db.getAppConfig();
    final map = {for (var c in cfg) c['key'] as String: c['value'] as String};
    final company = map['company_name'] ?? 'NY Lottery POS';
    final footer = map['ticket_footer'] ?? 'Good luck! Please play responsibly.';
    final doc = pw.Document();
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.roll80, build: (_) => _pdfTicket(t, company, footer)));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'ticket_${t['id']}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final t = ticket ?? (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?);
    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Print'), backgroundColor: const Color(0xFF0B8A3E), foregroundColor: Colors.white),
        body: const Center(child: Text('No ticket selected — open from Tickets → Detail → Print')),
      );
    }
    const green = Color(0xFF0B8A3E);
    final numbers = (t['numbers'] as String).replaceAll(',', '  ');
    final period = _periodFromName(t['drawName'] as String?);
    return Scaffold(
      appBar: AppBar(title: const Text('Print — Ticket'), backgroundColor: green, foregroundColor: Colors.white),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text('Ticket Preview — 58mm Thermal (NY Official Style)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const Divider(),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey, width: 0.5), borderRadius: BorderRadius.circular(8), color: Colors.white),
                          child: Column(
                            children: [
                              const Text('NY LOTTERY POS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1)),
                              const Text('NY LOTTERY OFFICIAL', style: TextStyle(fontSize: 8, color: Colors.grey, letterSpacing: 1)),
                              const Divider(height: 12),
                              Text('${t['gameName']} • ${t['betType']}'.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              Text('${t['drawName'] ?? '-'} • $period', style: const TextStyle(fontSize: 9, color: Colors.black54)),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(border: Border.all(color: Colors.black87, width: 1.2), borderRadius: BorderRadius.circular(6)),
                                child: Column(
                                  children: [
                                    Text(numbers, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 4)),
                                    const SizedBox(height: 4),
                                    Text('${t['betType']} • ${fmtMoney(t['amount'])}', style: const TextStyle(fontSize: 10)),
                                    if (t['status'] == 'winning' || t['status'] == 'paid')
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(t['status'] == 'paid' ? 'PAID • Prize ${fmtMoney(t['prizeAmount'] ?? 0)}' : 'WINNER • Prize ${fmtMoney(t['prizeAmount'] ?? 0)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: green)),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Ticket ID', style: TextStyle(fontSize: 7, color: Colors.grey)),
                                      Text('${t['id']}', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      const Text('Serial', style: TextStyle(fontSize: 7, color: Colors.grey)),
                                      Text('${t['serialNumber']}', style: const TextStyle(fontSize: 8)),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text('Date', style: TextStyle(fontSize: 7, color: Colors.grey)),
                                      Text(fmtDate(t['createdAt']), style: const TextStyle(fontSize: 8)),
                                      const SizedBox(height: 4),
                                      const Text('Operator', style: TextStyle(fontSize: 7, color: Colors.grey)),
                                      Text('${t['operatorName']}', style: const TextStyle(fontSize: 8)),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              QrImageView(data: t['barcode'] ?? t['id'], size: 120),
                              Text(t['barcode'] ?? t['id'], style: const TextStyle(fontSize: 8, letterSpacing: 1, color: Colors.black54)),
                              const Divider(height: 16),
                              const Text('Good luck! Please play responsibly. 18+ only.', style: TextStyle(fontSize: 7, color: Colors.grey), textAlign: TextAlign.center),
                              const Text('--- CUT HERE ---', style: TextStyle(fontSize: 7, color: Colors.grey)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.preview, size: 16), label: const Text('Preview'), onPressed: () => _printPdf(context, t))),
                            const SizedBox(width: 8),
                            Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.print, size: 16), label: const Text('Print'), style: ElevatedButton.styleFrom(backgroundColor: green, foregroundColor: Colors.white), onPressed: () => _printPdf(context, t))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(icon: const Icon(Icons.share, size: 16), label: const Text('Share PDF'), onPressed: () => _sharePdf(context, t)),
                        ),
                        const SizedBox(height: 8),
                        const Text('58mm thermal • Roll80 • QR + Barcode • Company name & footer from Settings • Draw period (Midday/Evening/Night) • Winning prize highlighted', style: TextStyle(fontSize: 9, color: Colors.black45), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
                Card(
                  color: Color(0xFFE8F5E9),
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Print Options', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: green)),
                        SizedBox(height: 4),
                        Text('• Ticket • Winning slip • Daily report • Receipt — all via same 58mm pipeline', style: TextStyle(fontSize: 10)),
                        Text('• Printer: Thermal 58/80mm, Bluetooth/USB/Network — config in Settings', style: TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
