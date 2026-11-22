import 'package:flutter/material.dart';

import '../utils/responsive.dart';

import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';
import '../widgets/draw_period_choice.dart';

class TicketDetailScreen extends StatefulWidget {
  final Map<String, dynamic> ticket;
  const TicketDetailScreen({this.ticket = const {}, super.key});
  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  Map<String, dynamic>? _ticket;
  List<Map<String, dynamic>> _lines = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
    _refresh();
  }

  Future<void> _refresh() async {
    if (_ticket == null || _ticket!['id'] == null) {
      setState(() => _loading = false);
      return;
    }
    final db = context.read<AppDatabase>();
    final fresh = await db.getTicketById(_ticket!['id']);
    final lines = await db.getTicketLines(_ticket!['id']);
    if (mounted)
      setState(() {
        _ticket = fresh ?? _ticket;
        _lines = lines;
        _loading = false;
      });
  }

  String _dispBet(String raw) {
    final n = raw
        .trim()
        .toLowerCase()
        .replaceAll('-', '/')
        .replaceAll('_', '/')
        .replaceAll(' ', '');
    if (n == 'all' ||
        n == 'all/box' ||
        n == 'all/straight' ||
        n == 'straightbox' ||
        n == 'str/box' ||
        n == 'strbox' ||
        n == 'st/box' ||
        n == 'stbox' ||
        (n.contains('straight') && n.contains('box')))
      return 'ST/BOX';
    return raw;
  }

  String _period(String? name) {
    if (name == null) return '-';
    if (name.contains('Morning') || name.contains('Midday')) return 'Morning';
    if (name.contains('Evening')) return 'Evening';
    if (name.contains('Night')) return 'Night';
    return 'Standard';
  }

  Future<void> _share() async {
    final t = _ticket!;
    String numbersPart;
    if (_lines.isNotEmpty)
      numbersPart = _lines
          .map(
            (l) =>
                '${l['numbers'].toString().replaceAll(',', ' ')}(${l['betType']}) ${fmtMoney(l['amount'])}',
          )
          .join(' | ');
    else
      numbersPart = t['numbers'].toString().replaceAll(',', ' ');
    final txt =
        'NY Lottery Ticket\nID:${t['id']}\nSerial:${t['serialNumber']}\nGame:${t['gameName']} ${t['betType']}\nPlays:${_lines.isNotEmpty ? _lines.length : 1}\nNumbers:$numbersPart\nDraw:${t['drawName']} (${_period(t['drawName'])})\nTotal:${fmtMoney(t['total'] ?? t['amount'])}\nDate:${fmtDate(t['createdAt'])}\nOperator:${t['operatorName']}\nStatus:${t['status']}${t['prizeAmount'] != null ? ' Prize:${fmtMoney(t['prizeAmount'])}' : ''}\nBarcode:${t['barcode']}';
    await Share.share(txt);
  }

  Future<void> _cancel() async {
    if (_ticket!['status'] != 'active') return;
    final isMulti = _lines.length > 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(isMulti ? 'إلغاء الفاتورة كاملة؟' : 'إلغاء التذكرة؟'),
        content: Text(
          isMulti
              ? 'هذه الفاتورة فيها ${_lines.length} ألعاب. هل تريد إلغاء كل الألعاب المتبقية؟\nيمكنك أيضاً إلغاء لعبة واحدة فقط بالضغط على زر الحذف بجانب كل رقم.'
              : 'هل تريد إلغاء هذه التذكرة واسترداد المبلغ؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إبقاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              isMulti
                  ? 'إلغاء الكل (${_lines.where((e) => (e['periodStatus'] as String?) != 'cancelled').length} Plays)'
                  : 'إلغاء التذكرة',
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final refund = await context.read<AppState>().cancelWholeTicket(
        _ticket!['id'] as String,
      );
      await _refresh();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إلغاء الفاتورة — استرداد ${fmtMoney(refund)}'),
            backgroundColor: Colors.orange,
          ),
        );
    } catch (e) {
      // Do not force-cancel: surface the rejection and leave the ticket untouched.
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Future<void> _cancelLine(Map<String, dynamic> line) async {
    final isVoided =
        (line['periodStatus'] as String?) == 'cancelled' ||
        (line['winningStatus'] as String?) == 'void';
    if (isVoided) return;
    if (_ticket!['status'] != 'active') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only active tickets can be voided'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final numbers = (line['numbers'] as String).replaceAll(',', ' ');
    final bet = line['betType'] as String;
    final amt = fmtMoney(line['amount']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'إلغاء هذا الرقم؟',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الرقم: $numbers',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('النوع: $bet  •  المبلغ: $amt'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'سيتم إلغاء هذا السطر فقط، وسيُسترد المبلغ للعميل، وتبقى بقية الألعاب في الفاتورة. لا يمكن الإلغاء بعد إغلاق السحب أو نشر النتيجة.',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('إلغاء الرقم'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final refund = await context.read<AppState>().cancelTicketLine(
        ticketId: _ticket!['id'] as String,
        lineId: line['id'] as String,
      );
      await _refresh();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إلغاء $numbers — استرداد ${fmtMoney(refund)}'),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Future<String?> _askDrawChoice() =>
      showDrawPeriodChoice(context, arabic: true);

  Future<void> _replay() async {
    final id = _ticket!['id'] as String;
    final choice = await _askDrawChoice();
    if (choice == null) return;
    try {
      final res = await context.read<AppState>().replayTicketToCartWithChoice(
        id,
        choice,
      );
      if (!mounted) return;
      final count = asInt(res['added']);
      final skipped = (res['skipped'] as List).cast<String>();
      final trimmed = (res['trimmed'] as List).cast<String>();
      final label = choice == 'BOTH'
          ? 'كلا السحبين (مضاعف)'
          : choice == 'MIDDAY'
          ? 'الصباحي فقط'
          : 'المسائي فقط';
      String hint = '';
      if (skipped.isNotEmpty)
        hint += '\n\n⚠️ محذوف (وصل للحد):\n${skipped.join('\n')}';
      if (trimmed.isNotEmpty)
        hint += '\n\n✂️ تم تقليله للحد المتبقي:\n${trimmed.join('\n')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم النسخ $count لعبة → $label — اذهب لـ SALE لطباعة التذكرة الجديدة${skipped.isNotEmpty ? ' — ${skipped.length} محذوف' : ''}${trimmed.isNotEmpty ? ' — ${trimmed.length} مقلّل' : ''}',
          ),
          backgroundColor: const Color(0xFF0B8A3E),
          duration: Duration(
            seconds: skipped.isNotEmpty || trimmed.isNotEmpty ? 5 : 3,
          ),
        ),
      );
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text(
            'تم النسخ — Re-play',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Text(
              '$count لعبة نُسخت إلى السلة ($label).$hint\n\nهل تريد الانتقال لشاشة البيع؟',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('البقاء'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(c);
                Navigator.pushNamed(context, '/numbers');
              },
              child: const Text('Numbers (3D/4D)'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _ticket ?? widget.ticket;
    if (t.isEmpty)
      return Scaffold(
        appBar: AppBar(title: const Text('Ticket Detail')),
        body: const Center(child: Text('No ticket')),
      );
    final isWinning = t['status'] == 'winning';
    final isPaid = t['status'] == 'paid';
    final isCancelled = t['status'] == 'cancelled';
    final isActive = t['status'] == 'active';
    const green = Color(0xFF0B8A3E);
    final customerRaw = t['customerName'];
    final customerName =
        (customerRaw is String && customerRaw.trim().isNotEmpty)
        ? customerRaw.trim()
        : 'Cash Customer';
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        backgroundColor: green,
        foregroundColor: Colors.white,
        title: const Text('Ticket Detail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: green))
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: Responsive.contentMaxWidth(context),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(
                    Responsive.horizontalPadding(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isPaid
                                          ? Colors.green.shade50
                                          : isWinning
                                          ? Colors.orange.shade50
                                          : isCancelled
                                          ? Colors.red.shade50
                                          : Colors.blueGrey.shade50,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      t['status'].toString().toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isPaid
                                            ? Colors.green.shade700
                                            : isWinning
                                            ? Colors.orange.shade700
                                            : isCancelled
                                            ? Colors.red
                                            : Colors.black54,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (t['isQuickPick'] == 1)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade50,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        'QUICK PICK',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.indigo,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  if (_lines.length > 1)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: green.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        '${_lines.length} PLAYS',
                                        style: const TextStyle(
                                          fontSize: 9,
                                          color: green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'NY LOTTERY POS',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                              Text(
                                '${t['gameName']} • ${_dispBet(t['betType'])} ${_lines.length > 1 ? '• ${_lines.length} plays' : ''}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${t['drawName'] ?? '-'}  •  Period: ${_period(t['drawName'])}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                ),
                              ),
                              const Divider(height: 16),
                              if (_lines.isNotEmpty && _lines.length > 1)
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.black87,
                                      width: 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      for (int i = 0; i < _lines.length; i++)
                                        Builder(
                                          builder: (ctx) {
                                            final l = _lines[i];
                                            final isVoid =
                                                (l['periodStatus']
                                                        as String?) ==
                                                    'cancelled' ||
                                                (l['winningStatus']
                                                        as String?) ==
                                                    'void';
                                            return Container(
                                              margin: EdgeInsets.only(
                                                bottom: i == _lines.length - 1
                                                    ? 0
                                                    : 6,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: isVoid
                                                      ? Colors.red.shade300
                                                      : Colors.grey.shade400,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                color: isVoid
                                                    ? Colors.red.shade50
                                                    : (i % 2 == 0
                                                          ? Colors.white
                                                          : Colors
                                                                .grey
                                                                .shade50),
                                              ),
                                              child: Row(
                                                children: [
                                                  Text(
                                                    '${i + 1}.',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: isVoid
                                                          ? Colors.red
                                                          : Colors.black54,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    (l['numbers'] as String)
                                                        .replaceAll(',', ' '),
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      letterSpacing: 2,
                                                      decoration: isVoid
                                                          ? TextDecoration
                                                                .lineThrough
                                                          : null,
                                                      color: isVoid
                                                          ? Colors.red.shade700
                                                          : Colors.black,
                                                    ),
                                                  ),
                                                  if (isVoid)
                                                    Container(
                                                      margin:
                                                          const EdgeInsets.only(
                                                            left: 6,
                                                          ),
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                      ),
                                                      child: const Text(
                                                        'ملغي',
                                                        style: TextStyle(
                                                          fontSize: 8,
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  const Spacer(),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      border: Border.all(
                                                        color: Colors
                                                            .grey
                                                            .shade300,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      _dispBet(l['betType']),
                                                      style: const TextStyle(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    fmtMoney(l['amount']),
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      decoration: isVoid
                                                          ? TextDecoration
                                                                .lineThrough
                                                          : null,
                                                      color: isVoid
                                                          ? Colors.red
                                                          : Colors.black,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  if (!isVoid && isActive)
                                                    InkWell(
                                                      onTap: () =>
                                                          _cancelLine(l),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              4,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors
                                                              .red
                                                              .shade50,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                6,
                                                              ),
                                                          border: Border.all(
                                                            color: Colors
                                                                .red
                                                                .shade200,
                                                          ),
                                                        ),
                                                        child: const Icon(
                                                          Icons.close,
                                                          size: 14,
                                                          color: Colors.red,
                                                        ),
                                                      ),
                                                    )
                                                  else if (isVoid)
                                                    const Icon(
                                                      Icons.block,
                                                      size: 14,
                                                      color: Colors.red,
                                                    ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      const Divider(height: 12),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'TOTAL',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                fmtMoney(
                                                  t['total'] ?? t['amount'],
                                                ),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: green,
                                                ),
                                              ),
                                              if (_lines.any(
                                                (e) =>
                                                    (e['periodStatus']
                                                        as String?) ==
                                                    'cancelled',
                                              ))
                                                Text(
                                                  'بعد الإلغاء — الأصلي كان ${fmtMoney(_lines.fold<double>(0, (s, e) => s + asDouble(e['amount'])))}',
                                                  style: const TextStyle(
                                                    fontSize: 9,
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Builder(
                                  builder: (ctx) {
                                    final singleLine = _lines.isNotEmpty
                                        ? _lines.first
                                        : null;
                                    final isSingleVoid =
                                        singleLine != null &&
                                        ((singleLine['periodStatus']
                                                    as String?) ==
                                                'cancelled' ||
                                            (singleLine['winningStatus']
                                                    as String?) ==
                                                'void');
                                    return Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: isSingleVoid
                                                ? Colors.red
                                                : Colors.black87,
                                            width: 1.2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          color: isSingleVoid
                                              ? Colors.red.shade50
                                              : Colors.white,
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              (t['numbers'] as String)
                                                  .replaceAll(',', '  '),
                                              style: TextStyle(
                                                fontSize: 26,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 4,
                                                decoration: isSingleVoid
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                                color: isSingleVoid
                                                    ? Colors.red
                                                    : Colors.black,
                                              ),
                                            ),
                                            if (isSingleVoid)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                  top: 6,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.red,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'ملغي — Voided',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${_dispBet(t['betType'])} • ${fmtMoney(t['amount'])}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isSingleVoid
                                                    ? Colors.red
                                                    : Colors.black54,
                                                decoration: isSingleVoid
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                              ),
                                            ),
                                            if (isWinning || isPaid)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 6,
                                                ),
                                                child: Text(
                                                  isPaid
                                                      ? 'PAID • ${fmtMoney(t['prizeAmount'] ?? 0)}'
                                                      : 'WINNER • ${fmtMoney(t['prizeAmount'] ?? 0)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: isPaid
                                                        ? Colors.green.shade700
                                                        : Colors
                                                              .orange
                                                              .shade700,
                                                  ),
                                                ),
                                              ),
                                            if (isActive &&
                                                !isSingleVoid &&
                                                singleLine != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 8,
                                                ),
                                                child: OutlinedButton.icon(
                                                  icon: const Icon(
                                                    Icons.close,
                                                    size: 14,
                                                    color: Colors.red,
                                                  ),
                                                  label: const Text(
                                                    'إلغاء هذا الرقم',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                        side: BorderSide(
                                                          color: Colors
                                                              .red
                                                              .shade300,
                                                        ),
                                                      ),
                                                  onPressed: () =>
                                                      _cancelLine(singleLine),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              const SizedBox(height: 12),
                              _row('Ticket ID', t['id']),
                              _row('Serial', t['serialNumber'] ?? '-'),
                              _row('Game', t['gameName']),
                              _row('Bet Type', _dispBet(t['betType'])),
                              _row(
                                'Plays',
                                _lines.isNotEmpty ? '${_lines.length}' : '1',
                              ),
                              _row(
                                'Numbers',
                                _lines.isNotEmpty && _lines.length > 1
                                    ? _lines
                                          .map(
                                            (l) => (l['numbers'] as String)
                                                .replaceAll(',', ''),
                                          )
                                          .join(' | ')
                                    : (t['numbers'] as String).replaceAll(
                                        ',',
                                        ', ',
                                      ),
                              ),
                              _row(
                                'Total',
                                fmtMoney(t['total'] ?? t['amount']),
                              ),
                              _row('Draw', t['drawName'] ?? '-'),
                              _row('Date', fmtDate(t['createdAt'])),
                              _row('Operator', t['operatorName']),
                              _row('Customer / العميل', customerName),
                              _row('Barcode', t['barcode'] ?? t['id']),
                              if (t['prizeAmount'] != null)
                                _row(
                                  'Prize',
                                  fmtMoney(t['prizeAmount']),
                                  bold: true,
                                  color: green,
                                ),
                              if (t['paidBy'] != null)
                                _row('Paid By', t['paidBy']),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              QrImageView(
                                data: t['barcode'] ?? t['id'],
                                size: 140,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                t['barcode'] ?? t['id'],
                                style: const TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Show QR at validation counter — scan to validate',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isWinning)
                        Card(
                          color: Colors.green.shade50,
                          child: Padding(
                            padding: EdgeInsets.all(
                              Responsive.horizontalPadding(context),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.emoji_events, color: green),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Winning ticket — go to Winning Tickets to collect ${fmtMoney(t['prizeAmount'] ?? 0)}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (isActive)
                        Card(
                          color: Colors.blue.shade50,
                          child: Padding(
                            padding: EdgeInsets.all(
                              Responsive.horizontalPadding(context),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Active ticket — will be evaluated after draw. You can cancel before cutoff (5 min before draw).',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      // Action buttons row 1
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.print, size: 16),
                              label: const Text('Print'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: green,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pushNamed(
                                context,
                                '/print',
                                arguments: t,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.share, size: 16),
                              label: const Text('Share'),
                              onPressed: _share,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Replay full ticket
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.copy, size: 16),
                          label: Text(
                            'Copy & Re-play  (${_lines.isNotEmpty ? _lines.length : 1} plays)',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _replay,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.verified, size: 16),
                              label: const Text('Validate'),
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/winning'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: Icon(
                                Icons.cancel,
                                size: 16,
                                color: isActive ? Colors.red : Colors.grey,
                              ),
                              label: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: isActive ? Colors.red : Colors.grey,
                                ),
                              ),
                              onPressed: isActive ? _cancel : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _row(String k, dynamic v, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              k,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          Expanded(
            child: Text(
              v.toString(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: color ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
