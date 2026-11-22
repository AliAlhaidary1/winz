import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/responsive.dart';
import '../widgets/app_drawer.dart';
import '../utils/format.dart';
import '../utils/ticket_pdf.dart';

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key});
  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  List<Map<String, dynamic>> _draws = [];
  String? _drawId;
  String _betType = 'Straight';
  final _amountCtrl = TextEditingController(text: '0.50');
  String _digits = '';
  bool _loadingDraws = true;
  final betTypes = [
    'Straight',
    'Box',
    'Combo',
    'Straight/Box',
    'Front Pair',
    'Back Pair',
  ];
  String _gameFilter = 'Numbers';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    await db.seedDrawPeriods();
    await db.refreshPeriodStatuses();
    final all = await db.getDrawsByGame('g_numbers');
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final openPeriods = await db.getOpenPeriods();
    final openIds = openPeriods.map((p) => p['id'] as String).toSet();
    // Only draws backed by an open, sellable period may be played.
    final draws =
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
    setState(() {
      _draws = draws;
      _drawId = draws.isNotEmpty ? draws.first['id'] as String : null;
      _loadingDraws = false;
    });
  }

  void _pressDigit(String d) {
    if (_digits.length >= 4) return;
    setState(() => _digits += d);
  }

  void _back() => setState(
    () => _digits = _digits.isNotEmpty
        ? _digits.substring(0, _digits.length - 1)
        : '',
  );
  void _clear() => setState(() => _digits = '');
  void _quickPick() {
    final rnd = Random();
    final len = _gameFilter == '4D' ? 4 : 3;
    String s = '';
    for (int i = 0; i < len; i++) s += rnd.nextInt(10).toString();
    setState(() => _digits = s);
  }

  void _cycleBetType() {
    final idx = betTypes.indexOf(_betType);
    setState(() => _betType = betTypes[(idx + 1) % betTypes.length]);
  }

  void _cycleDigitMode() {
    setState(() => _gameFilter = _gameFilter == '4D' ? 'Numbers' : '4D');
  }

  /// Same normalization as numbers_screen / app_state, so every spelling of a
  /// Straight+Box ("All") bet is priced and charged identically.
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

  /// Multinomial n! / prod(c_i!) — identical to numbers_screen._comboCount.
  int _comboCount(List<String> d) {
    final n = d.length;
    final f = <String, int>{};
    for (final x in d) {
      f[x] = (f[x] ?? 0) + 1;
    }
    int fact(int x) => x <= 1 ? 1 : x * fact(x - 1);
    var denom = 1;
    for (final c in f.values) {
      denom *= fact(c);
    }
    return fact(n) ~/ denom;
  }

  /// Total actually charged for the current selection (one draw).
  double _amountDue() {
    final amt = double.tryParse(_amountCtrl.text) ?? 0;
    final low = _betType.toLowerCase();
    if (low.contains('combo')) {
      final combos = _comboCount(_digits.split(''));
      return combos > 1 ? amt * combos : amt;
    }
    if (_isStBoxBet(_betType)) return amt * 2;
    return amt;
  }

  String _betInfoText() {
    final amt = double.tryParse(_amountCtrl.text);
    if (amt == null || _digits.isEmpty) return '';
    final digits = _digits.split('');
    final low = _betType.toLowerCase();
    if (low.contains('combo')) {
      final combos = _comboCount(digits);
      if (combos <= 1) return 'Invalid Combo — needs distinct permutations';
      return 'Amount due: \$${(amt * combos).toStringAsFixed(2)} ($combos × \$${amt.toStringAsFixed(2)} per combo)';
    }
    if (_isStBoxBet(_betType)) {
      return 'Amount due: \$${(amt * 2).toStringAsFixed(2)} (\$${amt.toStringAsFixed(2)} Straight + \$${amt.toStringAsFixed(2)} Box)';
    }
    return 'Amount due: \$${amt.toStringAsFixed(2)}';
  }

  Widget _appBarDrawField() {
    const green = Color(0xFF0B8A3E);
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
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _drawId,
          isDense: true,
          // Shrink with the available AppBar space when the cart badge shows.
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, size: 18, color: green),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: green,
          ),
          items: _draws
              .map(
                (d) => DropdownMenuItem(
                  value: d['id'] as String,
                  // A Flexible must sit inside a Flex — DropdownMenuItem just
                  // Aligns its child, so wrap it in a Row to avoid a runtime
                  // ParentDataWidget error while keeping the ellipsis.
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _drawLabel(d),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: green,
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

  void _incAmount() {
    final cur = double.tryParse(_amountCtrl.text) ?? 0.5;
    setState(
      () => _amountCtrl.text = (cur + 0.5).clamp(0.5, 10.0).toStringAsFixed(2),
    );
  }

  void _decAmount() {
    final cur = double.tryParse(_amountCtrl.text) ?? 0.5;
    setState(
      () => _amountCtrl.text = (cur - 0.5).clamp(0.5, 10.0).toStringAsFixed(2),
    );
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
    if (_digits.length != 3 && _digits.length != 4) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter 3 or 4 digits')));
      return;
    }
    final amt = double.tryParse(_amountCtrl.text);
    if (amt == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invalid amount')));
      return;
    }
    final is3D = _digits.length == 3;
    final digits = _digits.split('');
    final low = _betType.toLowerCase();
    final isCombo = low.contains('combo');
    final isStBox = _isStBoxBet(_betType);
    final isBox = low == 'box';
    if (digits.toSet().length == 1 && (isBox || isStBox || isCombo)) {
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
    if (isCombo) {
      final combos = _comboCount(digits);
      if (combos <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Combo not valid for $_digits — need distinct permutations',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (amt < 0.5 - 1e-9 || amt > 10 + 1e-9) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Amount \$0.50 - \$10.00 per combo')),
        );
        return;
      }
      if (((amt) * 100).round() % 50 != 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Amount must be \$0.50 steps per combo'),
          ),
        );
        return;
      }
    } else if (isStBox) {
      final maxInput = is3D ? 50.0 : 25.0;
      if (amt < 0.5 - 1e-9 || amt > maxInput + 1e-9) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Amount \$0.50 - \$${maxInput.toStringAsFixed(2)} for Straight/Box',
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
    } else {
      final maxAmt = isBox ? 50.0 : (is3D ? 100.0 : 10.0);
      if (amt < 0.5 || amt > maxAmt) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Amount \$0.50 - \$${maxAmt.toStringAsFixed(2)}'),
          ),
        );
        return;
      }
    }
    final cartAmount = _amountDue();
    final draw = _draws.firstWhere((d) => d['id'] == _drawId, orElse: () => {});
    try {
      await context.read<AppState>().addToCart(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: _drawId,
        drawName: draw['name'] as String?,
        numbers: digits,
        betType: _betType,
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
        color: AppTheme.green,
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

  Widget _drawer() => const AppDrawer(currentRoute: '/play');

  Widget _keyBtn(
    String l, {
    VoidCallback? onTap,
    Color? color,
    IconData? icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, size: 20)
            : Text(
                l,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  String _drawLabel(Map<String, dynamic> d) {
    final name = d['name'] as String;
    final periodRaw = name.split(' - ').first.replaceAll('Numbers ', '').trim();
    final datePart = name.split(' - ').length > 1 ? name.split(' - ').last : '';
    String period = periodRaw;
    if (periodRaw.toLowerCase().contains('morning') ||
        periodRaw.toLowerCase().contains('midday'))
      period = 'Morning';
    else if (periodRaw.toLowerCase().contains('evening'))
      period = 'Evening';
    else if (periodRaw.toLowerCase().contains('night'))
      period = 'Night';
    return '$period • $datePart';
  }

  Widget _amountStepper() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _decAmount,
            child: Container(
              width: 36,
              alignment: Alignment.center,
              child: const Icon(Icons.remove, size: 18),
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
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
            child: Container(
              width: 36,
              alignment: Alignment.center,
              child: const Icon(Icons.add, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlBar() {
    final digitsField = InkWell(
      onTap: _cycleDigitMode,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        width: 90,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
          color: _gameFilter == 'Numbers'
              ? const Color(0xFFE6F4EA)
              : Colors.white,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.pin,
              size: 14,
              color: _gameFilter == 'Numbers'
                  ? const Color(0xFF0B8A3E)
                  : Colors.black54,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                _gameFilter == 'Numbers' ? '3 Digits' : '4 Digits',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _gameFilter == 'Numbers'
                      ? const Color(0xFF0B8A3E)
                      : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
    final typeField = InkWell(
      onTap: _cycleBetType,
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
            const Icon(Icons.style, size: 14, color: Color(0xFF0B8A3E)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _betType,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          digitsField,
          const SizedBox(width: 8),
          typeField,
          const SizedBox(width: 8),
          SizedBox(width: 135, child: _amountStepper()),
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
          color: const Color(0xFFF0F7F0),
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
                  child: ElevatedButton(
                    onPressed: _doSale,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0B8A3E),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'SALE  ${fmtMoney(app.cartTotal)} (${app.cartCount})',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
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
    const green = Color(0xFF0B8A3E);
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool compactAppBar = screenWidth < 480;
    return Scaffold(
      appBar: AppBar(
        title: _appBarDrawField(),
        centerTitle: true,
        leadingWidth: compactAppBar ? 48 : 56,
        backgroundColor: green,
        foregroundColor: Colors.white,
        actions: [
          Consumer<AppState>(
            builder: (_, app, __) => app.isCartEmpty
                ? const SizedBox()
                : Padding(
                    padding: EdgeInsets.only(right: compactAppBar ? 2 : 8),
                    child: Center(
                      // Cap the badge so a large cart total cannot squeeze
                      // the AppBar title dropdown into an overflow.
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: compactAppBar ? 72 : 100,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${app.cartCount} • ${fmtMoney(app.cartTotal)}',
                            style: const TextStyle(
                              color: green,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => _showLogout(context),
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/play'),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: TextField(
                  readOnly: true,
                  controller: TextEditingController(
                    text: _digits.isEmpty ? '' : _digits,
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    hintText: _gameFilter == '4D' ? '----' : '---',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    isDense: true,
                    suffixIcon: _digits.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: _clear,
                          )
                        : null,
                  ),
                ),
              ),
              Container(
                color: Colors.grey.shade50,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  children: [
                    _loadingDraws
                        ? const LinearProgressIndicator()
                        : _controlBar(),
                    if (_betInfoText().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF0B8A3E)
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          _betInfoText(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0B8A3E),
                          ),
                          textAlign: TextAlign.center,
                          softWrap: true,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: Consumer<AppState>(
                  builder: (ctx, app, __) {
                    final cart = app.cart;
                    if (cart.isEmpty)
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6F4EA),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.shopping_cart_outlined,
                                  color: Color(0xFF0B8A3E),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Cart empty — add numbers then SALE',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const Text(
                                'Only current plays shown',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    return ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: cart.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (c, i) {
                        final it = cart[i];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.shade50,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF0B8A3E),
                              ),
                            ),
                          ),
                          title: Text(
                            '${it.numbers.join(' ')} • ${it.betType} • ${fmtMoney(it.amount)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${it.drawName ?? ''} • ${it.gameName}',
                            style: const TextStyle(fontSize: 10),
                          ),
                          trailing: InkWell(
                            onTap: () => app.removeFromCart(it.id),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.delete_outline,
                                size: 16,
                                color: Colors.red,
                              ),
                            ),
                          ),
                          onTap: () {},
                        );
                      },
                    );
                  },
                ),
              ),
              _cartSection(),
              _keypad(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keypadGrid({double aspect = 1.7}) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: aspect,
      children: [
        for (int i = 1; i <= 9; i++)
          _keyBtn('$i', onTap: () => _pressDigit('$i')),
        _keyBtn('C', onTap: _clear, color: Colors.red.shade50),
        _keyBtn('0', onTap: () => _pressDigit('0')),
        _keyBtn(
          '',
          onTap: _back,
          icon: Icons.backspace_outlined,
          color: Colors.grey.shade100,
        ),
      ],
    );
  }

  Widget _quickPickButton() {
    const green = Color(0xFF0B8A3E);
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _quickPick,
        icon: const Icon(Icons.auto_awesome, size: 16),
        label: const Text(
          'Quick Pick',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          side: BorderSide(color: green.withValues(alpha: 0.4)),
        ),
      ),
    );
  }

  Widget _addToCartButton() {
    return InkWell(
      onTap: _addToCart,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_shopping_cart, color: Colors.white, size: 28),
            Text(
              'ADD',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'to cart',
              style: TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  /// Single-line ADD for the stacked (narrow phone) keypad layout.
  Widget _addToCartButtonCompact() {
    return InkWell(
      onTap: _addToCart,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_shopping_cart, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'ADD TO CART',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _keypad() {
    const actionColumnHeight = 4 * 56 + 3 * 8 + 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Under this width the 1-flex action column is too narrow for the
        // "Quick Pick" button label, so stack the actions below the grid.
        final bool stackActions = constraints.maxWidth < 360;
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Center(
            child: ConstrainedBox(
              // Cap the keypad on wide screens: an unconstrained 3-column
              // grid would grow taller than the viewport.
              constraints: const BoxConstraints(maxWidth: 560),
              child: stackActions
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Shorter keys keep the keypad inside a short phone
                        // viewport even when the cart section is visible.
                        _keypadGrid(aspect: 2.2),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _quickPickButton()),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 56,
                                child: _addToCartButtonCompact(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _keypadGrid()),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: actionColumnHeight,
                            child: Column(
                              children: [
                                _quickPickButton(),
                                const SizedBox(height: 8),
                                Expanded(child: _addToCartButton()),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  void _showLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('End session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
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
