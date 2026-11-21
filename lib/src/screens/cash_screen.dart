import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../providers/app_state.dart';
import '../data/database.dart';
import '../utils/responsive.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

class CashScreen extends StatefulWidget {
  const CashScreen({super.key});
  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  List<Map<String, dynamic>> _ledger = [];
  List<Map<String, dynamic>> _ledgerAll = [];
  double _cash = 0;
  Map<String, dynamic>? _session;
  bool _loading = true;
  final _openCtrl = TextEditingController(text: '0');
  final _adjCtrl = TextEditingController();
  String _adjType = 'deposit';
  DateTime? _from;
  DateTime? _to;
  String _preset = 'all';

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
    _filter();
  }

  void _filter() {
    if (_from == null && _to == null) {
      setState(() => _ledger = List.from(_ledgerAll));
      return;
    }
    final filtered = _ledgerAll.where((e) {
      final dt = DateTime.fromMillisecondsSinceEpoch(e['createdAt'] as int);
      final d = DateTime(dt.year, dt.month, dt.day);
      if (_from != null &&
          d.isBefore(DateTime(_from!.year, _from!.month, _from!.day)))
        return false;
      if (_to != null && d.isAfter(DateTime(_to!.year, _to!.month, _to!.day)))
        return false;
      return true;
    }).toList();
    setState(() => _ledger = filtered);
  }

  String _fmtShort(DateTime? d) => d == null
      ? '--'
      : '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final app = context.read<AppState>();
    if (app.isSessionExpired && app.isLoggedIn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session expired — please login again')),
        );
        app.logout();
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        return;
      }
    }
    final opId = app.currentUser?['id'] as String?;
    final l = opId != null
        ? await db.getCashLedgerByOperator(opId)
        : await db.getCashLedger();
    final c = await app.computeCashBalance();
    final s = app.currentUser != null
        ? await db.getOpenCashSession(app.currentUser!['id'])
        : null;
    setState(() {
      _ledgerAll = l;
      _cash = c;
      _session = s;
      _loading = false;
    });
    _filter();
  }

  Future<void> _openSession() async {
    final amt = double.tryParse(_openCtrl.text.trim());
    if (amt == null || amt < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل مبلغ افتتاحي صحيح')));
      return;
    }
    await context.read<AppState>().openCashSession(amt);
    _openCtrl.clear();
    await _load();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم فتح الجلسة: ${fmtMoney(amt)}'),
          backgroundColor: AppTheme.green,
        ),
      );
  }

  Future<void> _closeSession() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'إغلاق الجلسة؟',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'رصيد الإغلاق: ${fmtMoney(_cash)}\nسيتم إغلاق جلسة الكاش الحالية.',
          style: const TextStyle(fontSize: 11),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppState>().closeCashSession();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم إغلاق الجلسة'),
        backgroundColor: AppTheme.green,
      ),
    );
    await _load();
  }

  Future<void> _adjust() async {
    final amt = double.tryParse(_adjCtrl.text.trim());
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('أدخل مبلغ صحيح')));
      return;
    }
    final db = context.read<AppDatabase>();
    final app = context.read<AppState>();
    final dir = (_adjType == 'deposit' || _adjType == 'adjustment_in')
        ? 'in'
        : 'out';
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = const Uuid().v4();
    await db.insertCashLedger({
      'id': id,
      'type': _adjType,
      'amount': amt,
      'direction': dir,
      'description': _adjType,
      'operatorId': app.currentUser!['id'],
      'createdAt': now,
      'ticketId': null,
    });
    await db.insertBalanceMovement({
      'id': '${id}_b',
      'type': _adjType,
      'amount': amt,
      'direction': dir == 'in' ? 'credit' : 'debit',
      'description': _adjType,
      'operatorId': app.currentUser!['id'],
      'createdAt': now,
      'ticketId': null,
    });
    _adjCtrl.clear();
    await _load();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_adjType} ${fmtMoney(amt)}'),
          backgroundColor: AppTheme.green,
        ),
      );
  }

  // helpers
  double _sumDir(String dir, {String? type}) {
    return _ledger
        .where(
          (e) => e['direction'] == dir && (type == null || e['type'] == type),
        )
        .fold(0.0, (s, e) => s + (e['amount'] as num).toDouble());
  }

  Color _typeColor(String type, String dir) {
    if (dir == 'in') return AppTheme.green;
    if (type == 'payout') return AppTheme.red;
    if (type == 'withdrawal') return AppTheme.orange;
    return AppTheme.red;
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'sale':
        return Icons.receipt_long;
      case 'payout':
        return Icons.emoji_events;
      case 'opening':
        return Icons.lock_open;
      case 'deposit':
        return Icons.add_circle;
      case 'withdrawal':
        return Icons.remove_circle;
      default:
        if (type.startsWith('adjust')) return Icons.tune;
        return Icons.payments;
    }
  }

  String _fmtDateShort(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.month}/${d.day} $hh:$mm';
  }

  @override
  void dispose() {
    _openCtrl.dispose();
    _adjCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return Scaffold(
        appBar: AppBar(title: const Text('Cash')),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.green),
        ),
      );
    final totalIn = _sumDir('in');
    final totalOut = _sumDir('out');
    final net = totalIn - totalOut;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Cash — الصندوق'),
        backgroundColor: AppTheme.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1 — Cash header compact
                Container(
                  decoration: AppTheme.softGreenDecoration(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Period Net — صافي الفترة',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  fmtMoney(net),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                if (_session != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      'افتتاح: ${fmtMoney((_session!['openingAmount'] as num).toDouble())} • ${fmtDate(_session!['openedAt'] as int)}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                if (_session == null)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Text(
                                      'لا توجد جلسة مفتوحة — افتح جلسة للبدء',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_session != null)
                            ElevatedButton(
                              onPressed: _closeSession,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppTheme.red,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'إغلاق',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else
                            SizedBox(
                              width: 140,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _openCtrl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: '0.00',
                                        hintStyle: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.6,
                                          ),
                                          fontSize: 11,
                                        ),
                                        filled: true,
                                        fillColor: Colors.white.withValues(
                                          alpha: 0.15,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                        isDense: true,
                                        prefixText: '\$',
                                        prefixStyle: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  ElevatedButton(
                                    onPressed: _openSession,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: AppTheme.green,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: const Text(
                                      'فتح',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 2 — 3 stats concise
                Row(
                  children: [
                    _miniStat(
                      'الداخل IN',
                      fmtMoney(totalIn),
                      Icons.arrow_downward,
                      AppTheme.green,
                      AppTheme.greenLight,
                    ),
                    const SizedBox(width: 8),
                    _miniStat(
                      'الخارج OUT',
                      fmtMoney(totalOut),
                      Icons.arrow_upward,
                      AppTheme.red,
                      const Color(0xFFFFEBEE),
                    ),
                    const SizedBox(width: 8),
                    _miniStat(
                      'الصافي NET',
                      fmtMoney(net),
                      net >= 0 ? Icons.trending_up : Icons.trending_down,
                      net >= 0 ? AppTheme.green : AppTheme.red,
                      net >= 0 ? AppTheme.greenLight : const Color(0xFFF3E5F5),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 3 — Adjustment concise
                Container(
                  decoration: AppTheme.cardDecoration(),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppTheme.bg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.tune,
                              size: 14,
                              color: AppTheme.green,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'حركة سريعة',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_ledger.length} / ${_ledgerAll.length}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            width: 130,
                            child: DropdownButtonFormField<String>(
                              value: _adjType,
                              isDense: true,
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textDark,
                                fontWeight: FontWeight.w600,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'deposit',
                                  child: Text(
                                    'إيداع Deposit',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'withdrawal',
                                  child: Text(
                                    'سحب Withdraw',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'adjustment_in',
                                  child: Text(
                                    'تسوية +',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'adjustment_out',
                                  child: Text(
                                    'تسوية -',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                              onChanged: (v) => setState(() => _adjType = v!),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _adjCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'المبلغ Amount',
                                prefixText: '\$',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 40,
                            child: ElevatedButton(
                              onPressed: _adjust,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                              ),
                              child: const Text(
                                'إضافة',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 4 — Filter chips concise
                Container(
                  decoration: AppTheme.cardDecoration(),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'الفترة',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'عرض ${_ledger.length} من ${_ledgerAll.length}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final e in [
                              {'l': 'الكل', 'v': 'all'},
                              {'l': 'اليوم', 'v': 'today'},
                              {'l': 'أمس', 'v': 'yesterday'},
                              {'l': 'أسبوع', 'v': 'week'},
                              {'l': 'مخصص', 'v': 'custom'},
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(
                                    e['l']!,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _preset == e['v']
                                          ? Colors.white
                                          : AppTheme.textDark,
                                    ),
                                  ),
                                  selected: _preset == e['v'],
                                  selectedColor: AppTheme.green,
                                  backgroundColor: Colors.white,
                                  side: BorderSide(
                                    color: _preset == e['v']
                                        ? AppTheme.green
                                        : AppTheme.cardBorder,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  onSelected: (_) => _preset == e['v']
                                      ? null
                                      : _applyPreset(e['v']!),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_preset == 'custom') ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(
                                  Icons.calendar_today,
                                  size: 12,
                                ),
                                label: Text(
                                  'من: ${_fmtShort(_from)}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    firstDate: DateTime(2024),
                                    lastDate: DateTime(2030),
                                    initialDate: _from ?? DateTime.now(),
                                  );
                                  if (d != null) {
                                    setState(() => _from = d);
                                    _filter();
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(
                                  Icons.calendar_today,
                                  size: 12,
                                ),
                                label: Text(
                                  'إلى: ${_fmtShort(_to)}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    firstDate: DateTime(2024),
                                    lastDate: DateTime(2030),
                                    initialDate: _to ?? DateTime.now(),
                                  );
                                  if (d != null) {
                                    setState(() => _to = d);
                                    _filter();
                                  }
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setState(() {
                                  _from = null;
                                  _to = null;
                                  _preset = 'all';
                                });
                                _filter();
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 5 — Transactions concise
                Container(
                  decoration: AppTheme.cardDecoration(),
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.list_alt,
                              size: 14,
                              color: AppTheme.green,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'الحركات — Transactions',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            if (_ledger.isEmpty)
                              const Text(
                                'لا يوجد',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.textMuted,
                                ),
                              )
                            else
                              Text(
                                '${_ledger.length} حركة',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 12),
                      if (_ledger.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.bg,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.inbox_outlined,
                                    color: AppTheme.textMuted,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'لا توجد حركات في هذه الفترة',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'المبيعات والمدفوعات ستظهر هنا',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ..._ledger.take(100).map((e) {
                          final dir = e['direction'] as String;
                          final type = e['type'] as String;
                          final amt = (e['amount'] as num).toDouble();
                          final col = _typeColor(type, dir);
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.cardBorder),
                              ),
                              child: ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 2,
                                ),
                                leading: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: col.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    _typeIcon(type),
                                    size: 16,
                                    color: col,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: col.withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        type.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                          color: col,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${dir == 'in' ? '+' : '-'} ${fmtMoney(amt)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                          color: col,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  '${e['description'] ?? type} • ${_fmtDateShort(e['createdAt'] as int)}${e['ticketId'] != null ? ' • #${e['ticketId']}' : ''}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.textMuted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Icon(
                                  dir == 'in'
                                      ? Icons.arrow_downward
                                      : Icons.arrow_upward,
                                  size: 14,
                                  color: col,
                                ),
                                onTap: e['ticketId'] != null
                                    ? () => Navigator.pushNamed(
                                        context,
                                        '/ticket_detail',
                                        arguments: {'id': e['ticketId']},
                                      )
                                    : null,
                              ),
                            ),
                          );
                        }),
                      if (_ledger.length > 100)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Center(
                            child: Text(
                              'عرض 100 من ${_ledger.length} — استخدم الفلترة',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniStat(
    String label,
    String value,
    IconData icon,
    Color color,
    Color bg,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 12, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
