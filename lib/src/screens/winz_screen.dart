import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/app_drawer.dart';
import '../utils/format.dart';
import '../utils/ticket_pdf.dart';
import '../widgets/draw_period_choice.dart';
import 'barcode_scanner_screen.dart';

class WinzScreen extends StatefulWidget {
  const WinzScreen({super.key});
  @override
  State<WinzScreen> createState() => _WinzScreenState();
}

class _WinzScreenState extends State<WinzScreen> {
  List<Map<String, dynamic>> _draws = [];
  String? _drawId;
  String _winzType = 'Straight';
  final _amountCtrl = TextEditingController(text: '0.50');
  String _digits = '';
  bool _loadingDraws = true;
  final types = ['Straight', 'Box', 'ST/BOX', 'Combo'];

  /// Single source of truth for every spelling of a Straight+Box ("All") bet.
  /// Used by the amount-due text, the cart breakdown and the charge logic so
  /// the displayed amount always matches what is actually charged.
  bool _isStBoxBet(String raw) {
    final n = raw
        .trim()
        .toLowerCase()
        .replaceAll('-', '/')
        .replaceAll('_', '/')
        .replaceAll(' ', '');
    if (n == 'all' || n == 'all/box' || n == 'all/straight') return true;
    if (n.contains('straight') && n.contains('box')) return true;
    return const {'st/box', 'stbox', 'str/box', 'strbox'}.contains(n);
  }

  void _cycleBet() {
    final i = types.indexOf(_winzType);
    final next = types[(i + 1) % types.length];
    setState(() => _winzType = next);
  }

  Widget _appBarDrawField() {
    if (_loadingDraws)
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    if (_draws.isEmpty)
      return const Text(
        'No draws',
        style: TextStyle(color: Colors.white, fontSize: 13),
      );
    // قائمة منسدلة كبيرة وواضحة لكبار السن
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.orange.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _drawId,
          isExpanded: true,
          icon: const Icon(
            Icons.arrow_drop_down,
            size: 20,
            color: AppTheme.orange,
          ),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: AppTheme.orange,
          ),
          items: _draws
              .map(
                (d) => DropdownMenuItem(
                  value: d['id'] as String,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: AppTheme.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          d['name'].toString().contains('Evening')
                              ? Icons.nights_stay
                              : Icons.wb_sunny,
                          size: 14,
                          color: AppTheme.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Shrink the label when the cart badge leaves little
                      // room for the title inside the AppBar.
                      Flexible(
                        child: Text(
                          _drawLabel(d),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.orange,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _drawId = v),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    await db.seedDrawPeriods();
    await db.refreshPeriodStatuses();
    final all = await db.getDrawsByGame('g_winz');
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final openPeriods = await db.getOpenPeriods();
    final openIds = openPeriods.map((p) => p['id'] as String).toSet();
    final List<Map<String, dynamic>> draws =
        all.where((d) {
          if (d['status'] != 'open') return false;
          final dt = asInt(d['drawTime']);
          if (dt <= nowMs - 5 * 60 * 1000) return false;
          final name = d['name'] as String;
          final isMidday = name.contains('Midday') || name.contains('Morning');
          final type = isMidday ? 'MIDDAY' : 'EVENING';
          final drawDt = DateTime.fromMillisecondsSinceEpoch(dt);
          final pid =
              '${drawDt.year}-${drawDt.month.toString().padLeft(2, '0')}-${drawDt.day.toString().padLeft(2, '0')}-$type';
          return openIds.contains(pid);
        }).toList()..sort(
          (a, b) => (asInt(a['drawTime'])).compareTo(asInt(b['drawTime'])),
        );
    if (!mounted) return;
    setState(() => _draws = draws);
    setState(
      () => _drawId = _draws.isNotEmpty ? _draws.first['id'] as String : null,
    );
    setState(() => _loadingDraws = false);
  }

  void _press(String d) {
    if (_digits.length >= 4) return;
    setState(() => _digits += d);
  }

  void _clear() => setState(() => _digits = '');
  void _back() => setState(
    () => _digits = _digits.isNotEmpty
        ? _digits.substring(0, _digits.length - 1)
        : '',
  );
  void _quickPick() {
    final rnd = Random();
    String s = '';
    for (int i = 0; i < 4; i++) s += rnd.nextInt(10).toString();
    setState(() => _digits = s);
  }

  void _incAmount() {
    final cur = double.tryParse(_amountCtrl.text) ?? 0.5;
    final nxt = (cur + 0.5).clamp(0.5, 10.0);
    setState(() => _amountCtrl.text = nxt.toStringAsFixed(2));
  }

  void _decAmount() {
    final cur = double.tryParse(_amountCtrl.text) ?? 0.5;
    final nxt = (cur - 0.5).clamp(0.5, 10.0);
    setState(() => _amountCtrl.text = nxt.toStringAsFixed(2));
  }

  int _combo(List<String> d) {
    final f = <String, int>{};
    for (final x in d) {
      f[x] = (f[x] ?? 0) + 1;
    }
    int fact(int x) => x <= 1 ? 1 : x * fact(x - 1);
    var denom = 1;
    for (final c in f.values) {
      denom *= fact(c);
    }
    return fact(d.length) ~/ denom;
  }

  String _betInfoText() {
    final amt = double.tryParse(_amountCtrl.text);
    if (amt == null || _digits.length != 4) return '';
    final low = _winzType.toLowerCase();
    final isAll = _isStBoxBet(_winzType);
    if (low.contains('combo')) {
      final c = _combo(_digits.split(''));
      if (c <= 1) return 'Invalid Combo';
      final total = amt * c;
      return 'Amount due: \$${total.toStringAsFixed(2)}';
    }
    if (isAll) {
      return 'Amount due: \$${(amt * 2).toStringAsFixed(2)}';
    }
    return 'Amount due: \$${amt.toStringAsFixed(2)}';
  }

  Future<void> _addToCart() async {
    if (_drawId == null || _draws.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No open draw available — sales are closed'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_digits.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Win 4 needs exactly 4 digits (0-9)')),
      );
      return;
    }
    final amt = double.tryParse(_amountCtrl.text);
    if (amt == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invalid amount')));
      return;
    }
    final low = _winzType.toLowerCase();
    final isCombo = low.contains('combo');
    final isAll = _isStBoxBet(_winzType);
    final isBox = low == 'box';
    final allSame = _digits.split('').toSet().length == 1;
    if (allSame && (isBox || isAll || isCombo)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Repeated digits like $_digits are allowed in Straight only',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!isCombo && !isAll && !isBox) {
      if (amt < 0.5 || amt > 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Amount \$0.50 - \$10.00 for Straight 4'),
          ),
        );
        return;
      }
      if (((amt) * 100).round() % 50 != 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Amount must be \$0.50 steps')),
        );
        return;
      }
    } else if (isBox) {
      if (amt < 0.5 || amt > 50) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Amount \$0.50 - \$50.00 for Box (limit per number per period \$50)',
            ),
          ),
        );
        return;
      }
      if (((amt) * 100).round() % 50 != 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Amount must be \$0.50 steps')),
        );
        return;
      }
    }
    if (isCombo) {
      final c = _combo(_digits.split(''));
      if (c <= 1) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Combo not valid for $_digits')));
        return;
      }
      if (amt < 0.5 - 1e-9) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Combo min \$0.50 per combo')));
        return;
      }
      if (amt > 10 + 1e-9) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Combo max \$10 per combo')));
        return;
      }
      if (((amt) * 100).round() % 50 != 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Amount must be \$0.50 steps per combo')),
        );
        return;
      }
    }
    if (isAll) {
      if (amt < 0.5 - 1e-9) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('All min \$0.50')));
        return;
      }
      if (amt > 25 + 1e-9) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All max \$25.00 (total \$50)')),
        );
        return;
      }
      if (((amt) * 100).round() % 50 != 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Amount must be \$0.50 steps')));
        return;
      }
    }
    final draw = _draws.firstWhere((d) => d['id'] == _drawId, orElse: () => {});
    try {
      double cartAmount = amt;
      if (isCombo) {
        final c = _combo(_digits.split(''));
        cartAmount = amt * c;
      } else if (isAll) {
        cartAmount = amt * 2;
      }
      await context.read<AppState>().addToCart(
        gameId: 'g_winz',
        gameName: 'Win 4',
        drawId: _drawId,
        drawName: draw['name'] as String?,
        numbers: _digits.split(''),
        betType: _winzType,
        amount: cartAmount,
      );
      setState(() => _digits = '');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildCustomerSelector(BuildContext context) {
    return Consumer<AppState>(
      builder: (ctx, app, _) {
        final customer = app.currentCustomer;
        final name =
            (customer['name'] as String?) ?? AppState.defaultCustomerName;
        final isDefault = customer['id'] == AppState.defaultCustomerId;
        return InkWell(
          onTap: () => _showCustomerPicker(ctx),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.orange.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 18,
                  color: AppTheme.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'العميل / Customer',
                        style: TextStyle(
                          fontSize: 9,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Cash',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.orange,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                const Text(
                  'تغيير',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.orange,
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: AppTheme.orange,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCustomerPicker(BuildContext context) async {
    final app = context.read<AppState>();
    List<Map<String, dynamic>> customers;
    try {
      customers = await app.getCustomers();
    } catch (e) {
      if (!mounted) return;
      showSaleToast(
        context,
        e.toString().replaceAll('Exception: ', ''),
        error: true,
      );
      return;
    }
    if (!customers.any((c) => c['id'] == AppState.defaultCustomerId)) {
      customers = [
        {
          'id': AppState.defaultCustomerId,
          'name': AppState.defaultCustomerName,
          'phone': '',
        },
        ...customers,
      ];
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'اختر العميل / Select customer',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380, maxHeight: 380),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: customers.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) {
              final cust = customers[i];
              final id = cust['id'] as String;
              final name = (cust['name'] as String?) ?? '';
              final phone = (cust['phone'] as String?)?.trim() ?? '';
              final isCurrent = id == app.currentCustomer['id'];
              final isDefault = id == AppState.defaultCustomerId;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final nav = Navigator.of(c);
                          try {
                            if (isDefault) {
                              await app.useDefaultCustomer();
                            } else {
                              await app.selectCustomer(id);
                            }
                          } catch (e) {
                            nav.pop();
                            if (!mounted) return;
                            showSaleToast(
                              context,
                              e.toString().replaceAll('Exception: ', ''),
                              error: true,
                            );
                            return;
                          }
                          nav.pop();
                          if (!mounted) return;
                          showSaleToast(
                            context,
                            'العميل: $name',
                            color: AppTheme.orange,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppTheme.orange.withValues(
                                  alpha: 0.12,
                                ),
                                child: Icon(
                                  isDefault
                                      ? Icons.person_outline
                                      : Icons.person,
                                  size: 16,
                                  color: AppTheme.orange,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (phone.isNotEmpty)
                                      Text(
                                        phone,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (isCurrent)
                      const Icon(
                        Icons.check_circle,
                        color: AppTheme.orange,
                        size: 20,
                      )
                    else if (!isDefault)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SizedBox(
                            height: 26,
                            child: TextButton.icon(
                              onPressed: () async {
                                final nav = Navigator.of(c);
                                try {
                                  final res = await app.playCustomerUsual(id);
                                  final added = asInt(res['added']);
                                  final skipped = (res['skipped'] as List)
                                      .cast<String>();
                                  nav.pop();
                                  if (!mounted) return;
                                  final msg = skipped.isEmpty
                                      ? 'Play usual: $added added — tap SALE'
                                      : 'Play usual: $added added, ${skipped.length} skipped — tap SALE';
                                  showSaleToast(
                                    context,
                                    msg,
                                    color: AppTheme.orange,
                                  );
                                } catch (e) {
                                  nav.pop();
                                  if (!mounted) return;
                                  showSaleToast(
                                    context,
                                    e.toString().replaceAll('Exception: ', ''),
                                    error: true,
                                  );
                                }
                              },
                              icon: const Icon(
                                Icons.play_circle_outline,
                                size: 14,
                              ),
                              label: const Text(
                                'بها-play / Play usual',
                                style: TextStyle(fontSize: 9),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 26,
                            child: TextButton.icon(
                              onPressed: () async {
                                final nav = Navigator.of(c);
                                if (app.isCartEmpty) {
                                  nav.pop();
                                  if (!mounted) return;
                                  showSaleToast(
                                    context,
                                    'Cart empty — add plays first',
                                    error: true,
                                  );
                                  return;
                                }
                                try {
                                  final count = await app
                                      .saveCartAsCustomerPlays(id);
                                  nav.pop();
                                  if (!mounted) return;
                                  showSaleToast(
                                    context,
                                    'حفظ الروتين: $count play(s) saved',
                                    color: AppTheme.orange,
                                  );
                                } catch (e) {
                                  nav.pop();
                                  if (!mounted) return;
                                  showSaleToast(
                                    context,
                                    e.toString().replaceAll('Exception: ', ''),
                                    error: true,
                                  );
                                }
                              },
                              icon: const Icon(Icons.save_outlined, size: 14),
                              label: const Text(
                                'حفظ الروتين / Save routine',
                                style: TextStyle(fontSize: 9),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _doSale() async {
    final app = context.read<AppState>();
    if (app.isCartEmpty) {
      showSaleToast(context, 'Cart empty', error: true);
      return;
    }
    try {
      final ticket = await app.commitSale();
      if (!mounted) return;
      showSaleToast(
        context,
        'SALE Ticket ${ticket['id']} • ${fmtMoney(ticket['total'])}',
        color: AppTheme.orange,
      );
      await _load();
      final lines =
          (ticket['lines'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final printed = await tryDirectPrintTicket(context, ticket, lines);
      if (printed?.ok == true) {
        if (mounted)
          showSaleToast(
            context,
            'Printed on the default printer',
            color: const Color(0xFF0B8A3E),
          );
        return;
      }
      if (printed != null && mounted) {
        showSaleToast(context, printed.error ?? 'Print failed', error: true);
      }
      if (mounted) Navigator.pushNamed(context, '/print', arguments: ticket);
    } catch (e) {
      showSaleToast(
        context,
        e.toString().replaceAll('Exception: ', ''),
        error: true,
      );
    }
  }

  Future<String?> _askDrawChoiceForReplay() => showDrawPeriodChoice(context);

  Future<void> _handleReplayCode(String code) async {
    final app = context.read<AppState>();
    final res = await app.validateTicket(code.trim());
    if (!mounted) return;
    if (res['found'] == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ticket not found: $code'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final ticket = res['ticket'] as Map<String, dynamic>;
    final lines = res['lines'] as List<Map<String, dynamic>>?;
    final st = (ticket['status'] as String? ?? '').toLowerCase();
    final blockedForResale = st == 'paid' || st == 'cancelled';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Ticket ${ticket['id']} • ${ticket['serialNumber']}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (blockedForResale)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  st == 'paid' ? 'PAID — no re-sale' : 'CANCELLED — no re-sale',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Status: ${ticket['status']} • Total: ${fmtMoney(ticket['total'] ?? ticket['amount'])}',
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 8),
              if (blockedForResale)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    'This ticket is ${st.toUpperCase()}. Copying would create a NEW sale and is not allowed.',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
              if (lines != null && lines.isNotEmpty)
                for (int i = 0; i < lines.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Text('${i + 1}.', style: const TextStyle(fontSize: 10)),
                        const SizedBox(width: 6),
                        Text(
                          (lines[i]['numbers'] as String).replaceAll(',', ' '),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          lines[i]['betType'],
                          style: const TextStyle(fontSize: 9),
                        ),
                        const Spacer(),
                        Text(
                          fmtMoney(lines[i]['amount']),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
              else
                Text(
                  'Numbers: ${(ticket['numbers'] as String).replaceAll(',', ' ')} • ${ticket['betType']}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'When copying you will choose Midday, Evening, or both.',
                  style: TextStyle(fontSize: 9, color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy, size: 14),
            label: const Text(
              'Copy — choose period',
              style: TextStyle(fontSize: 11),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: blockedForResale
                ? null
                : () async {
                    Navigator.pop(ctx);
                    final choice = await _askDrawChoiceForReplay();
                    if (choice == null) return;
                    try {
                      // validateTicket already resolved formatted payloads (e.g.
                      // "Ticket:000123") to the real ticket — replay must use that id.
                      final tid = ticket['id'] as String;
                      final res = await app.replayTicketToCartWithChoice(
                        tid,
                        choice,
                      );
                      if (!mounted) return;
                      final count = asInt(res['added']);
                      final skipped = (res['skipped'] as List).cast<String>();
                      final trimmed = (res['trimmed'] as List).cast<String>();
                      final label = choice == 'BOTH'
                          ? 'Both (×2)'
                          : choice == 'MIDDAY'
                          ? 'Midday'
                          : 'Evening';
                      String extra = '';
                      if (skipped.isNotEmpty)
                        extra += ' — ${skipped.length} محذوف';
                      if (trimmed.isNotEmpty)
                        extra += ' — ${trimmed.length} مقلّل';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Copied $count play(s) → $label — tap SALE$extra',
                          ),
                          backgroundColor: AppTheme.orange,
                          duration: Duration(seconds: extra.isNotEmpty ? 5 : 3),
                        ),
                      );
                      if (skipped.isNotEmpty || trimmed.isNotEmpty) {
                        showDialog(
                          context: context,
                          builder: (c) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            title: const Text(
                              'تم النسخ مع تعديلات',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            content: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'تم نسخ $count → $label',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  if (skipped.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      '⚠️ محذوف (Sold Out):',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                    ),
                                    ...skipped.map(
                                      (s) => Text(
                                        '• $s',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ],
                                  if (trimmed.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      '✂️ مقلّل للحد المتبقي:',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                    ),
                                    ...trimmed.map(
                                      (s) => Text(
                                        '• $s',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c),
                                child: const Text('حسناً'),
                              ),
                            ],
                          ),
                        );
                      }
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            e.toString().replaceAll('Exception: ', ''),
                          ),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  },
          ),
        ],
      ),
    );
  }

  Future<void> _scanAndReplay() async {
    try {
      final code = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
      );
      if (code == null || code.isEmpty) return;
      await _handleReplayCode(code.trim());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _copyByTicketNumber() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Search by Ticket Number',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter Ticket ID or Serial — e.g. 000001',
              style: TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Ticket ID / Serial',
                isDense: true,
                prefixIcon: Icon(Icons.confirmation_number, size: 18),
              ),
              onSubmitted: (v) => Navigator.pop(c, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    await _handleReplayCode(code.trim());
  }

  Widget _buildControlBar() {
    IconData _typeIcon() {
      if (_winzType == 'Straight') return Icons.straighten;
      if (_winzType == 'Box') return Icons.inventory_2_outlined;
      if (_winzType.toLowerCase().contains('combo')) return Icons.shuffle;
      if (_winzType == 'All') return Icons.layers_outlined;
      return Icons.shuffle;
    }

    final typeField = InkWell(
      onTap: _cycleBet,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        width: 135,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        alignment: Alignment.center,
        child: Row(
          children: [
            Icon(_typeIcon(), size: 14, color: AppTheme.orange),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _winzType,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.swap_horiz, size: 14, color: AppTheme.textMuted),
          ],
        ),
      ),
    );

    final amountStepper = Container(
      height: 40,
      width: 135,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _decAmount,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              bottomLeft: Radius.circular(8),
            ),
            child: Container(
              width: 32,
              alignment: Alignment.center,
              child: const Icon(Icons.remove, size: 16),
            ),
          ),
          Container(width: 1, color: Colors.grey.shade300),
          Expanded(
            child: TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                prefixText: '\$',
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          Container(width: 1, color: Colors.grey.shade300),
          InkWell(
            onTap: _incAmount,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
            child: Container(
              width: 32,
              alignment: Alignment.center,
              child: const Icon(Icons.add, size: 16),
            ),
          ),
        ],
      ),
    );

    final digitsLabel = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.orange.withValues(alpha: 0.3)),
      ),
      alignment: Alignment.center,
      child: const Text(
        '4 Digits',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppTheme.orange,
        ),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          digitsLabel,
          const SizedBox(width: 8),
          typeField,
          const SizedBox(width: 8),
          amountStepper,
        ],
      ),
    );
  }

  Future<void> _clearCartConfirm() async {
    final app = context.read<AppState>();
    if (app.isCartEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Clear Cart',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        content: Text(
          'Delete all items (${app.cartCount} plays • ${fmtMoney(app.cartTotal)})?',
          style: const TextStyle(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok == true) {
      app.clearCart();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cart cleared'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Widget _cartSection() {
    return Consumer<AppState>(
      builder: (_, app, __) {
        if (app.isCartEmpty) return const SizedBox.shrink();
        return Container(
          color: const Color(0xFFFFF3E0),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _clearCartConfirm,
                  icon: const Icon(
                    Icons.clear_all,
                    size: 18,
                    color: Colors.red,
                  ),
                  label: const Text(
                    'CLEAR',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.red,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _doSale,
                    icon: const Icon(Icons.receipt_long),
                    label: Text(
                      'SALE • ${fmtMoney(app.cartTotal)} (${app.cartCount})',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isTablet = w >= 600;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        toolbarHeight: 60,
        title: _appBarDrawField(),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, size: 18),
            tooltip: 'Scan barcode',
            onPressed: _scanAndReplay,
          ),
          IconButton(
            icon: const Icon(Icons.search, size: 18),
            tooltip: 'Search by ticket number',
            onPressed: _copyByTicketNumber,
          ),
          Consumer<AppState>(
            builder: (_, app, __) => app.isCartEmpty
                ? const SizedBox()
                : Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Center(
                      // Cap the badge so a large cart total cannot squeeze
                      // the AppBar title dropdown into an overflow.
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${app.cartCount} • ${fmtMoney(app.cartTotal)}',
                            style: const TextStyle(
                              color: AppTheme.orange,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 18),
            onPressed: () => _logout(),
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/winz'),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isTablet ? 760 : double.infinity,
          ),
          child: Column(
            children: [
              Expanded(
                child: Consumer<AppState>(
                  builder: (ctx, app, __) {
                    final cart = app.cart;
                    if (cart.isEmpty) return _empty();
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      itemCount: cart.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (c, i) {
                        final item = cart[i];
                        String sub = fmtMoney(item.amount);
                        final low = item.betType.toLowerCase();
                        if (low.contains('combo')) {
                          final cc = _combo(item.numbers);
                          final per = cc > 0 ? item.amount / cc : item.amount;
                          sub =
                              '${cc}×\$${per.toStringAsFixed(2)}=${fmtMoney(item.amount)}';
                        } else if (_isStBoxBet(item.betType)) {
                          final ps = item.amount / 2;
                          sub =
                              '\$${ps.toStringAsFixed(2)}+${ps.toStringAsFixed(2)}=${fmtMoney(item.amount)}';
                        }
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.orange.withValues(alpha: 0.14),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppTheme.orange,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.orange.withValues(
                                                alpha: 0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              item.betType,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.orange,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              sub,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.bg,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              '${i + 1}/${cart.length}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: AppTheme.textMuted,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        item.numbers.join('   '),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${item.drawName ?? '-'} • ${item.gameName} • ${fmtMoney(item.amount)}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.textMuted,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                InkWell(
                                  onTap: () => app.removeFromCart(item.id),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.red.shade200,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline,
                                      size: 16,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              _cartSection(),
              _buildCustomerSelector(context),
              Builder(
                builder: (ctx) {
                  final info = _betInfoText();
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (idx) {
                            final has = idx < _digits.length;
                            final ch = has ? _digits[idx] : '';
                            return Container(
                              width: 48,
                              height: 48,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: has ? AppTheme.orange : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: has
                                      ? AppTheme.orange
                                      : AppTheme.cardBorder,
                                  width: has ? 2 : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: has
                                  ? Text(
                                      ch,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      '—',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.black26,
                                      ),
                                    ),
                            );
                          }),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '4 digits (0-9)',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_loadingDraws)
                          const LinearProgressIndicator(color: AppTheme.orange)
                        else
                          _buildControlBar(),
                        if (info.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _winzType.toLowerCase().contains('combo')
                                  ? const Color(0xFFF3E0)
                                  : const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.orange.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              info,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.orange,
                              ),
                              textAlign: TextAlign.center,
                              softWrap: true,
                              maxLines: 2,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.8,
                        children: [
                          for (int i = 1; i <= 9; i++)
                            _keyBtn('$i', onTap: () => _press('$i')),
                          _keyBtn(
                            'C',
                            onTap: _clear,
                            bg: const Color(0xFFFFF1F1),
                            fg: Colors.red,
                            border: const Color(0xFFFFC9C9),
                          ),
                          _keyBtn('0', onTap: () => _press('0')),
                          _keyBtn(
                            '',
                            onTap: _back,
                            icon: Icons.backspace_outlined,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: SizedBox(
                        height: 4 * 56 + 3 * 8 + 8,
                        child: Column(
                          children: [
                            SizedBox(
                              height: 56,
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _quickPick,
                                icon: const Icon(Icons.auto_awesome, size: 16),
                                label: const Text(
                                  'Quick Pick',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  side: BorderSide(
                                    color: AppTheme.orange.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: InkWell(
                                onTap: _addToCart,
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppTheme.blue,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_shopping_cart,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'ADD',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        'to cart',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _drawLabel(Map<String, dynamic> d) {
    final name = d['name'] as String;
    String p = 'Draw';
    if (name.contains('Morning') || name.contains('Midday'))
      p = 'Morning';
    else if (name.contains('Evening'))
      p = 'Evening';
    else if (name.contains('Night'))
      p = 'Night';
    final dt = DateTime.fromMillisecondsSinceEpoch(asInt(d['drawTime']));
    final t =
        '${dt.hour > 12 ? dt.hour - 12 : dt.hour}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
    return '$p • $t';
  }

  Widget _empty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.orange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.emoji_events_outlined,
              color: AppTheme.orange,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No Win 4 plays yet',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const Text(
            'Enter 4 digits → ADD → SALE',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
    ),
  );

  Widget _keyBtn(
    String l, {
    VoidCallback? onTap,
    Color? bg,
    Color? fg,
    Color? border,
    IconData? icon,
  }) {
    return Material(
      color: bg ?? Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border ?? AppTheme.cardBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          child: icon != null
              ? Icon(icon, size: 18, color: Colors.black54)
              : Text(
                  l,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: fg ?? AppTheme.textDark,
                  ),
                ),
        ),
      ),
    );
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout'),
        content: const Text('End session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () {
              context.read<AppState>().logout();
              Navigator.pop(c);
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (_) => false,
              );
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
