import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/database.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';
import '../utils/responsive.dart';
import '../utils/ticket_pdf.dart';
import '../services/thermal_printer_service.dart';
import '../theme/app_theme.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _cash = [];
  List<Map<String, dynamic>> _moves = [];
  bool _loading = true;
  DateTime? _from;
  DateTime? _to;
  String _preset = 'all';
  // By default match the other account screens (cash / balance / home), which
  // are scoped to the logged-in operator. Admin can switch to all operators.
  bool _scopeAll = false;

  // computed per period
  double _salesMidday = 0, _salesEvening = 0;
  double _prizeMidday = 0, _prizeEvening = 0;
  double _commMidday = 0, _commEvening = 0;
  double _commRate = 20.0;
  double _balanceLedger = 0; // from balance_movements (credit - debit)
  double _prizePaid = 0; // payout movements actually paid in this period

  String _fmtRate(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  void _applyPreset(String p) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _preset = p;
      if (p == 'today') {
        _from = today;
        _to = today;
      } else if (p == 'yesterday') {
        final y = today.subtract(const Duration(days: 1));
        _from = y;
        _to = y;
      } else if (p == 'week') {
        _from = today.subtract(const Duration(days: 6));
        _to = today;
      } else if (p == 'all') {
        _from = null;
        _to = null;
      }
    });
    _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final app = context.read<AppState>();
    final opId = app.currentUser?['id'] as String?;
    bool inScope(Map<String, dynamic> e) =>
        _scopeAll || opId == null || e['operatorId'] == opId;
    setState(() => _loading = true);
    final tAll = await db.getTickets();
    final cAll = await db.getCashLedger();
    final mAll = await db.getBalanceMovements();
    final allLines = await db.getAllTicketLines();
    List<Map<String, dynamic>> filterList(List<Map<String, dynamic>> list) {
      if (_from == null && _to == null) return list;
      return list.where((e) {
        final millis = e['createdAt'] ?? e['openedAt'] ?? 0;
        if (millis == 0) return true;
        final dt = DateTime.fromMillisecondsSinceEpoch(asInt(millis));
        final d = DateTime(dt.year, dt.month, dt.day);
        if (_from != null &&
            d.isBefore(DateTime(_from!.year, _from!.month, _from!.day)))
          return false;
        if (_to != null && d.isAfter(DateTime(_to!.year, _to!.month, _to!.day)))
          return false;
        return true;
      }).toList();
    }

    // Cancelled tickets are voided sales — exclude them entirely (paid tickets stay).
    final t = filterList(tAll)
        .where((e) => e['status'] != 'cancelled' && inScope(e))
        .toList();
    final c = filterList(cAll).where(inScope).toList();
    final m = filterList(mAll).where(inScope).toList();

    // Balance derived from the actual ledger rows in the same date range.
    double ledgerBalance = 0, prizePaid = 0;
    for (final mv in m) {
      final amt = asDouble(mv['amount']);
      if (mv['direction'] == 'credit' || mv['direction'] == 'in')
        ledgerBalance += amt;
      else
        ledgerBalance -= amt;
      if (mv['type'] == 'payout') prizePaid += amt;
    }

    String periodType(String? periodId, String? drawName, {String? fallback}) {
      final pid = periodId ?? '';
      final dn = drawName ?? '';
      if (pid.contains('MIDDAY')) return 'MIDDAY';
      if (pid.contains('EVENING')) return 'EVENING';
      if (dn.contains('Midday') || dn.contains('Morning')) return 'MIDDAY';
      if (dn.contains('Evening')) return 'EVENING';
      final fb = fallback ?? '';
      if (fb.contains('Midday') || fb.contains('Morning')) return 'MIDDAY';
      if (fb.contains('Evening')) return 'EVENING';
      return 'MIDDAY';
    }

    // Global customer rate — default 20% of full sales (editable)
    final rate = await db.getClientCommissionRate();
    double sMid = 0, sEve = 0;
    final filteredIds = t.map((e) => e['id'] as String).toSet();
    final ticketById = {for (final tk in t) tk['id'] as String: tk};
    for (final l in allLines) {
      final tid = l['ticketId'] as String;
      if (!filteredIds.contains(tid)) continue;
      // Cancelled / voided plays are not sales.
      if (l['periodStatus'] == 'cancelled' || l['winningStatus'] == 'void')
        continue;
      final type = periodType(
        l['periodId'] as String?,
        l['drawName'] as String?,
        fallback: (ticketById[tid] ?? {})['drawName'] as String?,
      );
      final amt = asDouble(l['amount']);
      if (type == 'MIDDAY')
        sMid += amt;
      else
        sEve += amt;
    }
    for (final tk in t) {
      final hasLine = allLines.any((l) => l['ticketId'] == tk['id']);
      if (!hasLine) {
        final amt = tk['total'] != null
            ? asDouble(tk['total'])
            : asDouble(tk['amount']);
        if (periodType(null, tk['drawName'] as String?) == 'MIDDAY')
          sMid += amt;
        else
          sEve += amt;
      }
    }
    final cMid = sMid * rate / 100;
    final cEve = sEve * rate / 100;

    // Prize per period: use the stored prizeAmount only — validateTicket mutates ticket state, so never call it from a report.
    double pMid = 0, pEve = 0;
    for (final tk in t.where(
      (e) => e['status'] == 'winning' || e['status'] == 'paid',
    )) {
      final prize = asDouble(tk['prizeAmount']);
      if (prize <= 0) continue;
      if (periodType(null, tk['drawName'] as String?) == 'MIDDAY')
        pMid += prize;
      else
        pEve += prize;
    }

    if (mounted)
      setState(() {
        _tickets = t;
        _cash = c;
        _moves = m;
        _salesMidday = sMid;
        _salesEvening = sEve;
        _prizeMidday = pMid;
        _prizeEvening = pEve;
        _commRate = rate;
        _commMidday = cMid;
        _commEvening = cEve;
        _balanceLedger = ledgerBalance;
        _prizePaid = prizePaid;
        _loading = false;
      });
  }

  Future<void> _editClientRate() async {
    final ctrl = TextEditingController(text: _fmtRate(_commRate));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(
          'Customer percent',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Calculated from full sales (Midday + Evening).',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Rate %',
                hintText: '20',
                suffixText: '%',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
    if (v == null || v < 0 || v > 100) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a valid rate between 0 and 100'),
            backgroundColor: Colors.red,
          ),
        );
      return;
    }
    if (!mounted) return;
    await context.read<AppDatabase>().setClientCommissionRate(v);
    await _load();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Customer rate saved: ${_fmtRate(v)}% of sales'),
          backgroundColor: AppTheme.green,
        ),
      );
  }

  Future<void> _printReport() async {
    final totalSales = _salesMidday + _salesEvening;
    final totalPrize = _prizeMidday + _prizeEvening;
    final totalComm = _commMidday + _commEvening;
    final balanceTotal = _balanceLedger;
    // مطلوب طباعة التقرير بنفس حجم الفواتير (58mm thermal Roll80) وليس A4
    final db = context.read<AppDatabase>();
    final cfg = await db.getAppConfig();
    final map = {for (var c in cfg) c['key'] as String: c['value'] as String};
    final printerType = normalizePrinterType(map['printer_type']);
    final s = ThermalStyle.fromType(printerType);
    final company = map['company_name'] ?? 'NY Lottery POS';
    pw.Widget buildBody(pw.Context ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          child: pw.Text(
            'INVOICE REPORT',
            style: pw.TextStyle(
              fontSize: s.kicker,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            _preset == 'all'
                ? 'All time'
                : 'From: ${_from != null ? dateOnlyFmt.format(_from!) : '--'}  To: ${_to != null ? dateOnlyFmt.format(_to!) : '--'}',
            style: pw.TextStyle(
              fontSize: s.tiny,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Divider(thickness: 0.6, color: PdfColors.black),
        _pdfSection(s, 'Sales', [
          'Midday = ${fmtMoney(_salesMidday)}',
          'Evening = ${fmtMoney(_salesEvening)}',
          'Total = ${fmtMoney(totalSales)}',
        ]),
        pw.SizedBox(height: s.gap),
        _pdfSection(s, 'Prize awarded', [
          'Midday = ${fmtMoney(_prizeMidday)}',
          'Evening = ${fmtMoney(_prizeEvening)}',
          'Total = ${fmtMoney(totalPrize)}',
        ]),
        pw.SizedBox(height: s.gap),
        _pdfSection(s, 'Customer ${_fmtRate(_commRate)}%', [
          'Midday = ${fmtMoney(_commMidday)}',
          'Evening = ${fmtMoney(_commEvening)}',
          'Total = ${fmtMoney(totalComm)}',
        ]),
        pw.SizedBox(height: s.gap),
        _pdfSection(s, 'The Balance (ledger)', [
          'Sales (info) = ${fmtMoney(totalSales)}',
          'Prize awarded (info) = ${fmtMoney(totalPrize)}',
          'Prize paid (ledger) = ${fmtMoney(_prizePaid)}',
          'Customer ${_fmtRate(_commRate)}% (info) = ${fmtMoney(totalComm)}',
          'Total = ${fmtMoney(balanceTotal)}',
        ], highlight: true),
        pw.SizedBox(height: s.gap),
        pw.Divider(thickness: 0.5, color: PdfColors.black),
        pw.Center(
          child: pw.Text(
            'Generated: ${fmtDate(DateTime.now().millisecondsSinceEpoch)}',
            style: pw.TextStyle(
              fontSize: s.tiny,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
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
    final format = getTicketPageFormat(printerType);
    final doc = pw.Document();
    doc.addPage(pw.Page(pageFormat: format, build: buildBody));
    final bytes = await doc.save();
    final escPos = await buildReportEscPos(
      printerType: printerType,
      company: company,
      rangeLabel: _preset == 'all'
          ? 'All time'
          : 'From: ${_from != null ? dateOnlyFmt.format(_from!) : '--'}  To: ${_to != null ? dateOnlyFmt.format(_to!) : '--'}',
      sections: [
        (
          title: 'Sales',
          rows: [
            'Midday = ${fmtMoney(_salesMidday)}',
            'Evening = ${fmtMoney(_salesEvening)}',
            'Total = ${fmtMoney(totalSales)}',
          ],
        ),
        (
          title: 'Prize awarded',
          rows: [
            'Midday = ${fmtMoney(_prizeMidday)}',
            'Evening = ${fmtMoney(_prizeEvening)}',
            'Total = ${fmtMoney(totalPrize)}',
          ],
        ),
        (
          title: 'Customer ${_fmtRate(_commRate)}%',
          rows: [
            'Midday = ${fmtMoney(_commMidday)}',
            'Evening = ${fmtMoney(_commEvening)}',
            'Total = ${fmtMoney(totalComm)}',
          ],
        ),
        (
          title: 'The Balance (ledger)',
          rows: [
            'Sales (info) = ${fmtMoney(totalSales)}',
            'Prize awarded (info) = ${fmtMoney(totalPrize)}',
            'Prize paid (ledger) = ${fmtMoney(_prizePaid)}',
            'Customer ${_fmtRate(_commRate)}% (info) = ${fmtMoney(totalComm)}',
            'Total = ${fmtMoney(balanceTotal)}',
          ],
        ),
      ],
      generated: 'Generated: ${fmtDate(DateTime.now().millisecondsSinceEpoch)}',
    );
    final result = await printPdfBytes(
      db: db,
      pdfBytes: bytes,
      format: format,
      jobName: 'Report',
      bluetoothBytes: escPos,
    );
    if (result.ok) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report printed on the default printer'),
            backgroundColor: Color(0xFF0B8A3E),
          ),
        );
      return;
    }
    if (!mounted) return;
    if ((map['default_printer_url'] ?? '').toString().trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Print failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text('Report preview — thermal ${s.mm80 ? '80mm' : '58mm'}'),
            backgroundColor: const Color(0xFF0B8A3E),
            foregroundColor: Colors.white,
          ),
          body: PdfPreview(
            build: (_) async => bytes,
            initialPageFormat: format,
            allowPrinting: false,
            allowSharing: true,
            canChangePageFormat: false,
            canChangeOrientation: false,
            pdfFileName: 'report.pdf',
          ),
        ),
      ),
    );
  }

  pw.Widget _pdfSection(
    ThermalStyle s,
    String title,
    List<String> rows, {
    bool highlight = false,
  }) {
    return pw.Container(
      padding: pw.EdgeInsets.all(s.pad),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: highlight ? PdfColors.green900 : PdfColors.grey400,
        ),
        borderRadius: pw.BorderRadius.circular(4),
        color: highlight ? PdfColors.green50 : PdfColors.white,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: s.section,
              fontWeight: pw.FontWeight.bold,
              color: highlight ? PdfColors.green900 : PdfColors.black,
            ),
          ),
          pw.Divider(thickness: 0.4, color: PdfColors.grey300),
          ...rows.map(
            (r) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 0.5),
              child: pw.Text(
                r,
                style: pw.TextStyle(
                  fontSize: s.meta,
                  fontWeight: highlight && r.startsWith('Total')
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalSales = _salesMidday + _salesEvening;
    final totalPrize = _prizeMidday + _prizeEvening;
    final totalComm = _commMidday + _commEvening;
    final balanceTotal = _balanceLedger;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Report'),
        backgroundColor: AppTheme.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.print, color: Colors.white),
            tooltip: 'Print',
            onPressed: _loading ? null : _printReport,
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: () {
              final txt =
                  'YeLottery Report\nSales Midday=${fmtMoney(_salesMidday)} Evening=${fmtMoney(_salesEvening)} Total=${fmtMoney(totalSales)}\nPrize awarded Midday=${fmtMoney(_prizeMidday)} Evening=${fmtMoney(_prizeEvening)} Total=${fmtMoney(totalPrize)}\nPrize paid (ledger)=${fmtMoney(_prizePaid)}\nCustomer ${_fmtRate(_commRate)}% Midday=${fmtMoney(_commMidday)} Evening=${fmtMoney(_commEvening)} Total=${fmtMoney(totalComm)}\nBalance (ledger) Sales(info)=${fmtMoney(totalSales)} Prize awarded(info)=${fmtMoney(totalPrize)} Prize paid=${fmtMoney(_prizePaid)} Customer(info)=${fmtMoney(totalComm)} Total=${fmtMoney(balanceTotal)}';
              Share.share(txt);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.green),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: Responsive.contentMaxWidth(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // filter
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(
                            Responsive.horizontalPadding(context),
                          ),
                          child: Column(
                            children: [
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final e in [
                                      {'l': 'All', 'v': 'all'},
                                      {'l': 'Today', 'v': 'today'},
                                      {'l': 'Yesterday', 'v': 'yesterday'},
                                      {'l': 'Week', 'v': 'week'},
                                      {'l': 'Custom', 'v': 'custom'},
                                    ])
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 6,
                                        ),
                                        child: ChoiceChip(
                                          label: Text(
                                            e['l']!,
                                            style: TextStyle(
                                              color: _preset == e['v']
                                                  ? Colors.white
                                                  : Colors.black87,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          selected: _preset == e['v'],
                                          selectedColor: AppTheme.green,
                                          backgroundColor: Colors.white,
                                          side: BorderSide(
                                            color: _preset == e['v']
                                                ? AppTheme.green
                                                : Colors.grey.shade300,
                                          ),
                                          onSelected: (_) => e['v'] == 'custom'
                                              ? setState(
                                                  () => _preset = 'custom',
                                                )
                                              : _applyPreset(e['v']!),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.person, size: 14),
                                  const SizedBox(width: 6),
                                  ChoiceChip(
                                    label: const Text(
                                      'My data',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    selected: !_scopeAll,
                                    onSelected: (_) {
                                      if (!_scopeAll) return;
                                      setState(() => _scopeAll = false);
                                      _load();
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                  ChoiceChip(
                                    label: const Text(
                                      'All operators',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    selected: _scopeAll,
                                    onSelected: (_) {
                                      if (_scopeAll) return;
                                      setState(() => _scopeAll = true);
                                      _load();
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _from == null
                                          ? 'From: --'
                                          : 'From: ${dateOnlyFmt.format(_from!)}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      _to == null
                                          ? 'To: --'
                                          : 'To: ${dateOnlyFmt.format(_to!)}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      final d = await showDatePicker(
                                        context: context,
                                        firstDate: DateTime(2024),
                                        lastDate: DateTime(2030),
                                        initialDate: DateTime.now(),
                                      );
                                      if (d != null)
                                        setState(() {
                                          _from = d;
                                          _preset = 'custom';
                                        });
                                      await _load();
                                    },
                                    child: const Text('From'),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      final d = await showDatePicker(
                                        context: context,
                                        firstDate: DateTime(2024),
                                        lastDate: DateTime(2030),
                                        initialDate: DateTime.now(),
                                      );
                                      if (d != null)
                                        setState(() {
                                          _to = d;
                                          _preset = 'custom';
                                        });
                                      await _load();
                                    },
                                    child: const Text('To'),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      setState(() {
                                        _from = null;
                                        _to = null;
                                        _preset = 'all';
                                      });
                                      _load();
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Sales
                      _reportCard(
                        title: 'Sales',
                        icon: Icons.point_of_sale,
                        color: AppTheme.green,
                        rows: [
                          _row(
                            'Midday',
                            fmtMoney(_salesMidday),
                            AppTheme.green,
                          ),
                          _row(
                            'Evening',
                            fmtMoney(_salesEvening),
                            AppTheme.blue,
                          ),
                          const Divider(height: 8),
                          _row(
                            'Total',
                            fmtMoney(totalSales),
                            Colors.black,
                            bold: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Prize awarded (from stored ticket.prizeAmount)
                      _reportCard(
                        title: 'Prize awarded',
                        icon: Icons.emoji_events,
                        color: AppTheme.orange,
                        rows: [
                          _row(
                            'Midday',
                            fmtMoney(_prizeMidday),
                            AppTheme.orange,
                          ),
                          _row(
                            'Evening',
                            fmtMoney(_prizeEvening),
                            AppTheme.orange,
                          ),
                          const Divider(height: 8),
                          _row(
                            'Total',
                            fmtMoney(totalPrize),
                            Colors.black,
                            bold: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Customer percent — 20% default of full sales, editable
                      _reportCard(
                        title: 'Customer ${_fmtRate(_commRate)}%',
                        icon: Icons.percent,
                        color: AppTheme.blue,
                        onEdit: _editClientRate,
                        rows: [
                          _row('Midday', fmtMoney(_commMidday), AppTheme.blue),
                          _row(
                            'Evening',
                            fmtMoney(_commEvening),
                            AppTheme.blue,
                          ),
                          const Divider(height: 8),
                          _row(
                            'Total',
                            fmtMoney(totalComm),
                            Colors.black,
                            bold: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Cash drawer (was missing — now visible so opening cash appears)
                      Builder(
                        builder: (_) {
                          final cashIn = _cash
                              .where((e) => e['direction'] == 'in')
                              .fold(0.0, (s, e) => s + asDouble(e['amount']));
                          final cashOut = _cash
                              .where((e) => e['direction'] == 'out')
                              .fold(0.0, (s, e) => s + asDouble(e['amount']));
                          final cashNet = cashIn - cashOut;
                          return _reportCard(
                            title: 'Cash Drawer',
                            icon: Icons.account_balance_wallet,
                            color: Colors.teal,
                            rows: [
                              _row(
                                'IN (sales + opening)',
                                fmtMoney(cashIn),
                                Colors.teal,
                              ),
                              _row(
                                'OUT (prizes + payouts)',
                                '- ${fmtMoney(cashOut)}',
                                AppTheme.red,
                              ),
                              const Divider(height: 8),
                              _row(
                                'NET Cash',
                                fmtMoney(cashNet),
                                Colors.black,
                                bold: true,
                              ),
                              if (_cash.any((e) => e['type'] == 'opening'))
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Includes opening cash: ${fmtMoney(_cash.where((e) => e['type'] == 'opening').fold(0.0, (s, e) => s + asDouble(e['amount'])))}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      // The Balance
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.green,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.green.withValues(alpha: 0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.account_balance_wallet,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'The Balance (ledger)',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _balanceRow(
                              'Sales (info)',
                              fmtMoney(totalSales),
                              Colors.white,
                            ),
                            const SizedBox(height: 4),
                            _balanceRow(
                              'Prize awarded (info)',
                              fmtMoney(totalPrize),
                              Colors.white,
                            ),
                            const SizedBox(height: 4),
                            _balanceRow(
                              'Prize paid (ledger)',
                              fmtMoney(_prizePaid),
                              Colors.white,
                            ),
                            const SizedBox(height: 4),
                            _balanceRow(
                              'Customer ${_fmtRate(_commRate)}% (info)',
                              fmtMoney(totalComm),
                              Colors.white,
                            ),
                            const Divider(color: Colors.white24, height: 12),
                            _balanceRow(
                              'Total (ledger)',
                              fmtMoney(balanceTotal),
                              Colors.white,
                              bold: true,
                              large: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // print button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.print, size: 18),
                          label: const Text(
                            'Print report',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _printReport,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.share, size: 16),
                          label: const Text(
                            'Share',
                            style: TextStyle(fontSize: 11),
                          ),
                          onPressed: () {
                            final txt =
                                'YeLottery Report\nSales Midday=${fmtMoney(_salesMidday)} Evening=${fmtMoney(_salesEvening)} Total=${fmtMoney(totalSales)}\nPrize awarded Midday=${fmtMoney(_prizeMidday)} Evening=${fmtMoney(_prizeEvening)} Total=${fmtMoney(totalPrize)}\nPrize paid (ledger)=${fmtMoney(_prizePaid)}\nCustomer ${_fmtRate(_commRate)}% Midday=${fmtMoney(_commMidday)} Evening=${fmtMoney(_commEvening)} Total=${fmtMoney(totalComm)}\nBalance (ledger) Sales(info)=${fmtMoney(totalSales)} Prize awarded(info)=${fmtMoney(totalPrize)} Prize paid=${fmtMoney(_prizePaid)} Customer(info)=${fmtMoney(totalComm)} Total=${fmtMoney(balanceTotal)}';
                            Share.share(txt);
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Report is split by period (Midday 14:30 / Evening 22:30). Commission (informational) = full sales × ${_fmtRate(_commRate)}% — not deducted from the ledger balance. Tap the edit icon to change the rate.',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _reportCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> rows,
    VoidCallback? onEdit,
  }) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: color,
                  ),
                ),
              ),
              if (onEdit != null)
                IconButton(
                  icon: Icon(Icons.edit, size: 16, color: color),
                  tooltip: 'Edit customer rate',
                  onPressed: onEdit,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
          const Divider(height: 12),
          ...rows,
        ],
      ),
    );
  }

  Widget _row(String label, String value, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textMuted,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 13 : 12,
              fontWeight: bold ? FontWeight.w900 : FontWeight.bold,
              color: bold ? Colors.black : color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceRow(
    String label,
    String value,
    Color color, {
    bool bold = false,
    bool large = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: large ? 13 : 11,
            color: Colors.white.withValues(alpha: bold ? 1 : 0.9),
            fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: large ? 16 : 12,
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
