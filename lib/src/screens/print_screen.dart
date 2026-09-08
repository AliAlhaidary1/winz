import 'package:flutter/material.dart';
import '../utils/responsive.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import '../data/database.dart';
import '../services/thermal_printer_service.dart';
import '../utils/format.dart';
import '../utils/ticket_pdf.dart';

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
            Expanded(
              child: Text((l['numbers'] as String).replaceAll(',', ' '), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 3, fontFamily: 'Courier', color: Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Text(_displayBetUI(l['betType']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
            const SizedBox(width: 8),
            Text(fmtMoney(l['amount']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
          ]),
        ),
    ]);
  }

  Future<pw.Document> _ticketDoc(Map<String, dynamic> t, List<Map<String,dynamic>> lines) async {
    final db = context.read<AppDatabase>();
    final cfg = await db.getAppConfig();
    final map = {for (var c in cfg) c['key'] as String: c['value'] as String};
    final company = map['company_name'] ?? 'NY Lottery POS';
    final footer = map['ticket_footer'] ?? '';
    final printerType = normalizePrinterType(map['printer_type']);
    final format = getTicketPageFormat(printerType);
    final doc = pw.Document();
    doc.addPage(pw.Page(pageFormat: format, build: (_) => buildTicketPdfWidget(t, lines, company, footer, printerType: printerType)));
    return doc;
  }

  Future<void> _previewPdf(BuildContext context, Map<String, dynamic> t, List<Map<String,dynamic>> lines) async {
    final db = context.read<AppDatabase>();
    final cfg = await db.getAppConfig();
    final map = {for (var c in cfg) c['key'] as String: c['value'] as String};
    final format = getTicketPageFormat(normalizePrinterType(map['printer_type']));
    final doc = await _ticketDoc(t, lines);
    final bytes = await doc.save();
    if(!mounted) return;
    await Navigator.push(this.context, MaterialPageRoute(builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Ticket preview'), backgroundColor: const Color(0xFF0B8A3E), foregroundColor: Colors.white),
      body: PdfPreview(
        build: (_) async => bytes,
        initialPageFormat: format,
        allowPrinting: false,
        allowSharing: true,
        canChangePageFormat: false,
        canChangeOrientation: false,
        pdfFileName: 'ticket_${t['id']}.pdf',
      ),
    )));
  }

  Future<void> _printPdf(BuildContext context, Map<String, dynamic> t, List<Map<String,dynamic>> lines) async {
    final db = context.read<AppDatabase>();
    final cfg = await db.getAppConfig();
    final map = {for (var c in cfg) c['key'] as String: c['value'] as String};
    final printerType = normalizePrinterType(map['printer_type']);
    final format = getTicketPageFormat(printerType);
    final doc = await _ticketDoc(t, lines);
    final company = map['company_name'] ?? 'NY Lottery POS';
    final footer = map['ticket_footer'] ?? '';
    final escPos = await buildTicketEscPos(ticket: t, lines: lines, company: company, footer: footer, printerType: printerType);
    final result = await printPdfBytes(db: db, pdfBytes: await doc.save(), format: format, jobName: 'Ticket ${t['id']}', bluetoothBytes: escPos);
    if(!mounted) return;
    if(result.ok){
      ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Printed on the default printer'), backgroundColor: Color(0xFF0B8A3E)));
    } else {
      ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text(result.error ?? 'Print failed'), backgroundColor: Colors.red));
    }
  }

  Future<void> _sharePdf(BuildContext context, Map<String, dynamic> t, List<Map<String,dynamic>> lines) async {
    final db = context.read<AppDatabase>();
    final cfg = await db.getAppConfig();
    final map = {for (var c in cfg) c['key'] as String: c['value'] as String};
    final company = map['company_name'] ?? 'NY Lottery POS';
    final footer = map['ticket_footer'] ?? '';
    final printerType = normalizePrinterType(map['printer_type']);
    final format = getTicketPageFormat(printerType);
    final doc = pw.Document();
    doc.addPage(pw.Page(pageFormat: format, build: (_) => buildTicketPdfWidget(t, lines, company, footer, printerType: printerType)));
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
                        const Text('Ticket Preview — prints on the default printer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const Divider(),
                        Container(
                          padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey, width: 0.5), borderRadius: BorderRadius.circular(8), color: Colors.white),
                            child: _loadingLines ? const Center(child: CircularProgressIndicator()) : Column(
                            children: [
                              const Text('INVOICE REPORT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black, letterSpacing: 1)),
                              const Divider(height: 12, color: Colors.black),
                              // رقم الفاتورة والتاريخ مباشرة تحت SALES REPORT
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
                              const Divider(height: 12, color: Colors.black),
                              const SizedBox(height: 4),
                              if(lines.isNotEmpty) Builder(builder: (ctx){
                                String classify(Map<String,dynamic> l){
                                  final pid = (l['periodId'] ?? '').toString().toUpperCase();
                                  if(pid.contains('MIDDAY') || pid.contains('MORNING') || pid.contains('MID_')) return 'MIDDAY';
                                  if(pid.contains('EVENING') || pid.contains('EVE') || pid.contains('NIGHT')) return 'EVENING';
                                  final dn = (l['drawName'] ?? '').toString().toUpperCase();
                                  if(dn.contains('MIDDAY') || dn.contains('MORNING')) return 'MIDDAY';
                                  if(dn.contains('EVENING')) return 'EVENING';
                                  final dt = (l['drawType'] ?? '').toString().toUpperCase();
                                  if(dt.contains('MIDDAY') || dt.contains('MORNING') || dt.contains('MID')) return 'MIDDAY';
                                  if(dt.contains('EVENING') || dt.contains('EVE')) return 'EVENING';
                                  return '';
                                }
                                final midLines = lines.where((l)=> classify(l)=='MIDDAY').toList();
                                final eveLines = lines.where((l)=> classify(l)=='EVENING').toList();
                                final otherLines = lines.where((l)=> classify(l)=='').toList();
                                final hasMid = midLines.isNotEmpty;
                                final hasEve = eveLines.isNotEmpty;
                                final hasOther = otherLines.isNotEmpty;
                                if(!hasMid && !hasEve){
                                  // fallback: لا يوجد تصنيف -> عرض بدون ترويسة مثل السابق
                                  return Column(children: [
                                    for(int i=0;i<lines.length;i++)
                                      Padding(
                                        padding: EdgeInsets.only(bottom: i==lines.length-1?0:4),
                                        child: Row(children: [
                                          Expanded(
                                            child: Text((lines[i]['numbers'] as String).replaceAll(',', ' '), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 3, fontFamily: 'Courier', color: Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(_displayBetUI(lines[i]['betType']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
                                          const SizedBox(width: 8),
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
                                }
                                // حالة Mid فقط أو Eve فقط أو Both أو مختلط
                                return Column(children: [
                                  if(hasMid) _printPeriodBlock('MIDDAY', midLines),
                                  if(hasMid && hasEve) ...[
                                    const SizedBox(height: 6),
                                    const Text('--------------------', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
                                    const SizedBox(height: 6),
                                  ],
                                  if(hasEve) _printPeriodBlock('EVENING', eveLines),
                                  if(hasOther) ...[
                                    if(hasMid || hasEve) ...[
                                      const SizedBox(height: 6),
                                      const Text('--------------------', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
                                      const SizedBox(height: 6),
                                    ],
                                    for(int i=0;i<otherLines.length;i++)
                                      Padding(
                                        padding: EdgeInsets.only(bottom: i==otherLines.length-1?0:4),
                                        child: Row(children: [
                                          Expanded(
                                            child: Text((otherLines[i]['numbers'] as String).replaceAll(',', ' '), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 3, fontFamily: 'Courier', color: Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(_displayBetUI(otherLines[i]['betType']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
                                          const SizedBox(width: 8),
                                          Text(fmtMoney(otherLines[i]['amount']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
                                        ]),
                                      ),
                                  ],
                                  const Divider(height: 12, color: Colors.black),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black)), Text(fmtMoney(t['total'] ?? t['amount']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black))]),
                                  if (t['status'] == 'winning' || t['status'] == 'paid')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(t['status'] == 'paid' ? 'PAID • Prize ${fmtMoney(t['prizeAmount'] ?? 0)}' : 'WINNER • Prize ${fmtMoney(t['prizeAmount'] ?? 0)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: green)),
                                    ),
                                ]);
                              }) else Builder(builder: (_){
                                final dn = (t['drawName'] ?? '').toString().toUpperCase();
                                String? header;
                                if(dn.contains('MIDDAY') || dn.contains('MORNING')) header='MIDDAY';
                                else if(dn.contains('EVENING')) header='EVENING';
                                return Column(
                                  children: [
                                    if(header!=null) ...[
                                      Text(header, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.black)),
                                      const SizedBox(height: 6),
                                    ],
                                    Text((t['numbers'] as String).replaceAll(',', '  '), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 5, fontFamily: 'Courier', color: Colors.black)),
                                    const SizedBox(height: 6),
                                    Text('${_displayBetUI(t['betType'])} • ${fmtMoney(t['amount'])}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
                                    if (t['status'] == 'winning' || t['status'] == 'paid')
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(t['status'] == 'paid' ? 'PAID • Prize ${fmtMoney(t['prizeAmount'] ?? 0)}' : 'WINNER • Prize ${fmtMoney(t['prizeAmount'] ?? 0)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: green)),
                                      ),
                                  ],
                                );
                              }),
                              const SizedBox(height: 10),
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
                            Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.preview, size: 16), label: const Text('Preview'), onPressed: () => _previewPdf(context, t, lines))),
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
                        Text(isMulti ? '${lines.length} plays on ONE ticket • SALE invoice • ${fmtMoney(t['total'])} total' : 'Thermal 58mm / 80mm • QR on ticket', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black), textAlign: TextAlign.center),
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
