import 'package:flutter/material.dart';
import '../utils/responsive.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../data/database.dart';
import '../utils/format.dart';

class PrintScreen extends StatefulWidget {
  final Map<String, dynamic>? ticket;
  const PrintScreen({super.key, this.ticket});

  @override
  State<PrintScreen> createState() => _PrintScreenState();
}

class _PrintScreenState extends State<PrintScreen> {
  List<Map<String,dynamic>>? _lines;
  bool _loadingLines = true;

  @override
  void initState(){
    super.initState();
    _loadLines();
  }

  Future<void> _loadLines() async {
    // Need to defer until build; use post frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ticket = widget.ticket ?? (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?);
      if(ticket==null){ setState(()=> _loadingLines=false); return; }
      // If ticket already has lines embedded (from commitSale)
      if(ticket['lines'] != null && (ticket['lines'] as List).isNotEmpty){
        setState(()=> _lines = (ticket['lines'] as List).cast<Map<String,dynamic>>());
        setState(()=> _loadingLines=false);
        return;
      }
      final db = context.read<AppDatabase>();
      final lines = await db.getTicketLines(ticket['id']);
      if(mounted) setState(()=> {_lines = lines, _loadingLines=false});
    });
  }

  static String _displayBet(String raw){
    final n = raw.trim().toLowerCase().replaceAll('-', '/').replaceAll('_', '/').replaceAll(' ', '');
    if(n=='all' || n=='all/box' || n=='all/straight' || (n.contains('straight') && n.contains('box')) || n=='straightbox' || n=='str/box' || n=='strbox') return 'ST/BOX';
    if(n=='straight') return 'ST';
    if(n=='box') return 'BOX';
    if(n.contains('combo')) return 'COMBO';
    return raw;
  }

  pw.Widget _pdfTicket(Map<String, dynamic> t, List<Map<String,dynamic>> lines, String company, String footer) {
    final isWinning = t['status'] == 'winning';
    final isPaid = t['status'] == 'paid';
    final prize = t['prizeAmount'] != null ? fmtMoney(t['prizeAmount']) : null;
    final total = fmtMoney(t['total'] ?? t['amount']);
    // فاتورة محسّنة لكبار السن: أرقام كبيرة وواضحة بدون رمادي، بدون سيريال منفصل
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(company, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
        pw.Text('NY LOTTERY OFFICIAL', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
        pw.SizedBox(height: 4),
        pw.Divider(thickness: 0.7, color: PdfColors.black),
        // بدون عدد الألعاب — فقط اسم اللعبة والإجمالي
        pw.Text('${t['gameName']}'.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
        pw.Text('$total', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
        pw.SizedBox(height: 2),
        pw.Text('${t['drawName'] ?? 'Draw: -'}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
        pw.Text('Draw Period: ${_periodFromName(t['drawName'])}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
        pw.SizedBox(height: 8),
        // Multi-line plays — handle Both separation
        if(lines.isNotEmpty)
          () {
            final mid = lines.where((l)=> (l['periodId']?.toString().contains('MIDDAY')??false) || (l['drawName']?.toString().contains('Midday')??false)).toList();
            final eve = lines.where((l)=> (l['periodId']?.toString().contains('EVENING')??false) || (l['drawName']?.toString().contains('Evening')??false)).toList();
            final isBoth = mid.isNotEmpty && eve.isNotEmpty;
            if (isBoth) {
              pw.Widget block(String label, List<Map<String,dynamic>> lst) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(label, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                pw.SizedBox(height: 3),
                for(final l in lst)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 3),
                    child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                      pw.Text((l['numbers'] as String).replaceAll(',', ' '), style: pw.TextStyle(font: pw.Font.courierBold(), fontSize: 22, fontWeight: pw.FontWeight.bold, letterSpacing: 3, color: PdfColors.black)),
                      pw.Text(_displayBet(l['betType']), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                      pw.Text(fmtMoney(l['amount']), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                    ]),
                  ),
              ]);
              return pw.Column(children: [
                  block('MIDDAY', mid),
                  pw.SizedBox(height: 3),
                  pw.Text('--------------------', style: pw.TextStyle(fontSize: 8, color: PdfColors.black)),
                  pw.SizedBox(height: 3),
                  block('EVENING', eve),
                  pw.SizedBox(height: 6),
                  pw.Divider(thickness: 0.6, color: PdfColors.black),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text('TOTAL', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                    pw.Text(total, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                  ]),
                  if (isWinning || isPaid)
                    pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: pw.Text(isPaid ? 'PAID • Prize $prize' : 'WINNER • Prize $prize', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green900))),
                ]);
            }
            return pw.Column(
              children: [
                for(int i=0;i<lines.length;i++)
                  pw.Padding(
                    padding: pw.EdgeInsets.only(bottom: i==lines.length-1?0:3),
                    child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('${i+1}.', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                          pw.SizedBox(width: 6),
                          pw.Text((lines[i]['numbers'] as String).replaceAll(',', ' '), style: pw.TextStyle(font: pw.Font.courierBold(), fontSize: 22, fontWeight: pw.FontWeight.bold, letterSpacing: 3, color: PdfColors.black)),
                          pw.Spacer(),
                          pw.Text(_displayBet(lines[i]['betType']), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                          pw.SizedBox(width: 8),
                          pw.Text(fmtMoney(lines[i]['amount']), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                        ],
                      ),
                  ),
                pw.SizedBox(height: 6),
                pw.Divider(thickness: 0.6, color: PdfColors.black),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('TOTAL', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                  pw.Text(total, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                ]),
                if (isWinning || isPaid)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 6),
                    child: pw.Text(isPaid ? 'PAID • Prize $prize' : 'WINNER • Prize $prize', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                  ),
              ],
            );
          }()
        else
          pw.Column(
              children: [
                pw.Text((t['numbers'] as String).replaceAll(',', '  '), style: pw.TextStyle(font: pw.Font.courierBold(), fontSize: 30, fontWeight: pw.FontWeight.bold, letterSpacing: 5, color: PdfColors.black)),
                pw.SizedBox(height: 4),
                pw.Text('${_displayBet(t['betType'])} • ${fmtMoney(t['amount'])}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                if (isWinning || isPaid)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 6),
                    child: pw.Text(isPaid ? 'PAID • Prize $prize' : 'WINNER • Prize $prize', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                  ),
              ],
          ),
        pw.SizedBox(height: 8),
        // معلومات التذكرة بدون سيريال منفصل — الباركود يربط السيريال (ID = barcode)
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Ticket ID / Barcode:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                pw.Text('${t['barcode'] ?? t['id']}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Date:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                pw.Text(fmtDate(t['createdAt']), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                pw.SizedBox(height: 2),
                pw.Text('Operator:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                pw.Text('${t['operatorName']}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Center(child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: t['barcode'] ?? t['id'], width: 110, height: 110)),
        pw.SizedBox(height: 4),
        pw.Text('${t['barcode'] ?? t['id']}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, letterSpacing: 1, color: PdfColors.black)),
        pw.Divider(thickness: 0.6, color: PdfColors.black),
        pw.Text('Keep ticket safe. Must be 18+ to play.', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black), textAlign: pw.TextAlign.center),
        pw.SizedBox(height: 3),
        pw.Text('--- CUT HERE ---', style: pw.TextStyle(fontSize: 7, color: PdfColors.black)),
      ],
    );
  }

  static String _periodFromName(String? name) {
    if (name == null) return '-';
    if (name.contains('Midday') || name.contains('Morning')) return 'Midday';
    if (name.contains('Evening')) return 'Evening';
    if (name.contains('Night')) return 'Night';
    return 'Standard';
  }

  String _displayBetUI(String raw){
    final n = raw.trim().toLowerCase().replaceAll('-', '/').replaceAll('_', '/').replaceAll(' ', '');
    if(n=='all' || n=='all/box' || n=='all/straight' || (n.contains('straight') && n.contains('box')) || n=='straightbox' || n=='str/box' || n=='strbox') return 'ST/BOX';
    return raw;
  }
  Widget _printPeriodBlock(String periodLabel, List<Map<String,dynamic>> lines) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(periodLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.black)),
      const SizedBox(height: 3),
      for (final l in lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Text((l['numbers'] as String).replaceAll(',', ' '), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 3, fontFamily: 'Courier', color: Colors.black)),
            const Spacer(),
            Text(_displayBetUI(l['betType']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
            const SizedBox(width: 10),
            Text(fmtMoney(l['amount']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
          ]),
        ),
    ]);
  }

  Future<void> _printPdf(BuildContext context, Map<String, dynamic> t, List<Map<String,dynamic>> lines) async {
    final db = context.read<AppDatabase>();
    final cfg = await db.getAppConfig();
    final map = {for (var c in cfg) c['key'] as String: c['value'] as String};
    final company = map['company_name'] ?? 'NY Lottery POS';
    final footer = map['ticket_footer'] ?? '';
    final doc = pw.Document();
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.roll80, build: (_) => _pdfTicket(t, lines, company, footer)));
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  Future<void> _sharePdf(BuildContext context, Map<String, dynamic> t, List<Map<String,dynamic>> lines) async {
    final db = context.read<AppDatabase>();
    final cfg = await db.getAppConfig();
    final map = {for (var c in cfg) c['key'] as String: c['value'] as String};
    final company = map['company_name'] ?? 'NY Lottery POS';
    final footer = map['ticket_footer'] ?? '';
    final doc = pw.Document();
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.roll80, build: (_) => _pdfTicket(t, lines, company, footer)));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'ticket_${t['id']}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final tArg = widget.ticket ?? (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?);
    final t = tArg;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Print'), backgroundColor: const Color(0xFF0B8A3E), foregroundColor: Colors.white),
        body: const Center(child: Text('No ticket selected — open from Tickets → Detail → Print')),
      );
    }
    const green = Color(0xFF0B8A3E);
    final period = _periodFromName(t['drawName'] as String?);
    final lines = _lines ?? (t['lines'] as List<Map<String,dynamic>>?) ?? [];
    final isMulti = lines.isNotEmpty && lines.length>1;
    return Scaffold(
      appBar: AppBar(title: const Text('Print — Ticket'), backgroundColor: green, foregroundColor: Colors.white),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: Responsive.isTablet(context) || Responsive.isDesktop(context) ? 680 : 520),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
                    child: Column(
                      children: [
                        const Text('Ticket Preview — 58mm Thermal (NY Official Style)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const Divider(),
                        Container(
                          padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey, width: 0.5), borderRadius: BorderRadius.circular(8), color: Colors.white),
                          child: _loadingLines ? const Center(child: CircularProgressIndicator()) : Column(
                            children: [
                              const Text('NY LOTTERY POS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1, color: Colors.black)),
                              const Text('NY LOTTERY OFFICIAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black, letterSpacing: 1)),
                              const Divider(height: 12, color: Colors.black),
                              Text('${t['gameName']}'.toUpperCase(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                              Text(fmtMoney(t['total'] ?? t['amount']), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black)),
                              const SizedBox(height: 2),
                              Text('${t['drawName'] ?? '-'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
                              Text('Period: $period', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
                              const SizedBox(height: 8),
                              if(lines.isNotEmpty) Builder(builder: (ctx){
                                // Group by period for Both display (spec §15)
                                final midLines = lines.where((l)=> (l['periodId']?.toString().contains('MIDDAY')?? false) || (l['drawName']?.toString().contains('Midday')??false) ).toList();
                                final eveLines = lines.where((l)=> (l['periodId']?.toString().contains('EVENING')?? false) || (l['drawName']?.toString().contains('Evening')??false) ).toList();
                                final isBoth = midLines.isNotEmpty && eveLines.isNotEmpty;
                                if(isBoth){
                                  return Column(children: [
                                      _printPeriodBlock('MIDDAY', midLines),
                                      const SizedBox(height: 6),
                                      const Text('--------------------', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
                                      const SizedBox(height: 6),
                                      _printPeriodBlock('EVENING', eveLines),
                                      const Divider(height: 12, color: Colors.black),
                                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)), Text(fmtMoney(t['total'] ?? t['amount']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black))]),
                                      if (t['status'] == 'winning' || t['status'] == 'paid')
                                        Padding(padding: const EdgeInsets.only(top: 4), child: Text(t['status'] == 'paid' ? 'PAID • Prize ${fmtMoney(t['prizeAmount'] ?? 0)}' : 'WINNER • Prize ${fmtMoney(t['prizeAmount'] ?? 0)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: green))),
                                    ]);
                                }
                                return Column(children: [
                                  for(int i=0;i<lines.length;i++)
                                    Padding(
                                      padding: EdgeInsets.only(bottom: i==lines.length-1?0:4),
                                      child: Row(children: [
                                        Text('${i+1}.', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
                                        const SizedBox(width: 8),
                                        Text((lines[i]['numbers'] as String).replaceAll(',', ' '), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 3, fontFamily: 'Courier', color: Colors.black)),
                                        const Spacer(),
                                        Text(_displayBetUI(lines[i]['betType']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
                                        const SizedBox(width: 10),
                                        Text(fmtMoney(lines[i]['amount']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
                                      ]),
                                    ),
                                  const Divider(height: 12, color: Colors.black),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black)), Text(fmtMoney(t['total'] ?? t['amount']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black))]),
                                  if (t['status'] == 'winning' || t['status'] == 'paid')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(t['status'] == 'paid' ? 'PAID • Prize ${fmtMoney(t['prizeAmount'] ?? 0)}' : 'WINNER • Prize ${fmtMoney(t['prizeAmount'] ?? 0)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: green)),
                                    ),
                                ]);
                              }) else Column(
                                  children: [
                                    Text((t['numbers'] as String).replaceAll(',', '  '), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 5, fontFamily: 'Courier', color: Colors.black)),
                                    const SizedBox(height: 6),
                                    Text('${_displayBetUI(t['betType'])} • ${fmtMoney(t['amount'])}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
                                    if (t['status'] == 'winning' || t['status'] == 'paid')
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(t['status'] == 'paid' ? 'PAID • Prize ${fmtMoney(t['prizeAmount'] ?? 0)}' : 'WINNER • Prize ${fmtMoney(t['prizeAmount'] ?? 0)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: green)),
                                      ),
                                  ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Ticket ID / Barcode', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
                                      Text('${t['barcode'] ?? t['id']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text('Date', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
                                      Text(fmtDate(t['createdAt']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
                                      const SizedBox(height: 4),
                                      const Text('Operator', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
                                      Text('${t['operatorName']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              QrImageView(data: t['barcode'] ?? t['id'], size: 130),
                              Text(t['barcode'] ?? t['id'], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.black)),
                              const Divider(height: 16, color: Colors.black),
                              const Text('--- CUT HERE ---', style: TextStyle(fontSize: 8, color: Colors.black)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.preview, size: 16), label: const Text('Preview'), onPressed: () => _printPdf(context, t, lines))),
                            const SizedBox(width: 8),
                            Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.print, size: 16), label: const Text('Print'), style: ElevatedButton.styleFrom(backgroundColor: green, foregroundColor: Colors.white), onPressed: () => _printPdf(context, t, lines))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(icon: const Icon(Icons.share, size: 16), label: const Text('Share PDF'), onPressed: () => _sharePdf(context, t, lines)),
                        ),
                        const SizedBox(height: 8),
                        Text(isMulti ? '${lines.length} plays on ONE ticket • SALE invoice • ${fmtMoney(t['total'])} total' : '58mm thermal • Roll80 • QR + Barcode', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black), textAlign: TextAlign.center),
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
