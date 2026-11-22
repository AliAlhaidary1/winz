import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/responsive.dart';
import '../utils/format.dart';
import '../utils/ticket_pdf.dart';
import '../widgets/app_drawer.dart';
import '../widgets/draw_period_choice.dart';
import 'barcode_scanner_screen.dart';

class NumbersScreen extends StatefulWidget {
  const NumbersScreen({super.key});
  @override
  State<NumbersScreen> createState() => _NumbersScreenState();
}

class _NumbersScreenState extends State<NumbersScreen> {
  List<Map<String, dynamic>> _draws = [];
  String? _drawId;
  String _drawMode = 'Midday'; // Midday / Evening / Both
  String _betType = 'Straight';
  final _amountCtrl = TextEditingController(text: '0.50');
  String _digits = '';
  bool _isQuickPick = false;
  bool _loadingDraws = true;
  String _digitMode = '3D'; // 3D / 4D
  int get _expectedDigits => _digitMode == '4D' ? 4 : 3;
  final betTypes = ['Straight', 'Box', 'ST/BOX', 'Combo'];
  List<Map<String, dynamic>> _periods = [];
  Timer? _sellableTick;
  bool _prefillApplied = false;

  @override
  void initState() {
    super.initState();
    _load();
    _sellableTick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(_applySellableDrawMode);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ModalRoute.of() needs the inherited widget from build(), so this must
    // run in didChangeDependencies, not initState.
    if (!_prefillApplied) {
      _prefillApplied = true;
      _applyRoutePrefill();
    }
  }

  /// Apply the optional prefill payload passed by callers via
  /// `Navigator.pushNamed(context, '/numbers', arguments: {...})`.
  /// No user feedback is shown — this only seeds the input controls.
  void _applyRoutePrefill() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! Map) return;

    final numbers = args['numbers'];
    if (numbers != null) {
      final cleaned = numbers.toString().replaceAll(RegExp(r'[,\s]'), '');
      final cap = cleaned.length >= 4 ? 4 : 3;
      _digits = cleaned.length > cap ? cleaned.substring(0, cap) : cleaned;
      _digitMode = _digits.length == 4 ? '4D' : '3D';
    }

    final betType = args['betType'];
    if (betType is String && betTypes.contains(betType)) {
      _betType = betType;
    }

    final amount = args['amount'];
    if (amount != null) {
      _amountCtrl.text = asDouble(amount).toStringAsFixed(2);
    }

    final drawType = args['drawType'];
    if (drawType is String) {
      _drawMode = drawType == 'EVENING' ? 'Evening' : 'Midday';
    }
  }

  @override
  void dispose() {
    _sellableTick?.cancel();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    await db.seedDrawPeriods();
    await db.refreshPeriodStatuses();
    final allDraws = await db.getDrawsByGame('g_numbers');
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Filtered legacy draws: only upcoming + open per draw_periods
    final openPeriods = await db.getOpenPeriods();
    final openIds = openPeriods.map((p) => p['id'] as String).toSet();
    // draws matching an OPEN period with drawTime in the future (5-minute allowance)
    final List<Map<String, dynamic>> draws =
        allDraws.where((d) {
          if (d['status'] != 'open') return false;
          final dt = asInt(d['drawTime']);
          if (dt <= nowMs - 5 * 60 * 1000) return false; // expired
          // check the matching period
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
    final List<Map<String, dynamic>> finalDraws = draws;
    final periods = await db.getAllPeriods();
    if (!mounted) return;
    // Allow mixing: no need to derive the period from the cart (disabled)
    // final cart = context.read<AppState>().cart; // not used now
    setState(() {
      _draws = finalDraws;
      if (_draws.isNotEmpty) {
        _drawId = _draws.first['id'] as String;
      } else {
        _drawId = null;
      }
      _periods = periods;
      _loadingDraws = false;
      // Allow mixing: don't force a period change based on the cart when a manual mix exists
      // keep the user's current choice; only apply closing constraints
      // if (modeFromCart != null) _drawMode = modeFromCart; // disabled to allow Midday + Evening + Both in the same invoice
      _applySellableDrawMode();
    });
  }

  void _syncDrawModeToPeriods() {
    if (_drawMode == 'Both') return;
    final wantEvening = _drawMode == 'Evening';
    for (final d in _draws) {
      final n = (d['name'] as String).toLowerCase();
      final isEvening = n.contains('evening');
      final isMidday = n.contains('midday') || n.contains('morning');
      if (wantEvening && isEvening) {
        _drawId = d['id'] as String;
        return;
      }
      if (!wantEvening && isMidday) {
        _drawId = d['id'] as String;
        return;
      }
    }
  }

  String _countdownText(String label) {
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final pid = '$dateStr-${label.toUpperCase()}';
      final p = _periods.where((e) => e['id'] == pid).firstOrNull;
      if (p == null) return '';
      if (p['status'] != 'OPEN') return 'SALES CLOSED';
      final close = asInt(p['salesCloseTime']);
      final rem = close - DateTime.now().millisecondsSinceEpoch;
      if (rem <= 0) return 'SALES CLOSED';
      final d = Duration(milliseconds: rem);
      return '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  void _pressDigit(String d) {
    // Never allow more digits than the selected 3D/4D mode expects.
    if (_digits.length >= _expectedDigits) return;
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
    final len = _digitMode == '3D' ? 3 : 4;
    String s = '';
    for (int i = 0; i < len; i++) s += rnd.nextInt(10).toString();
    setState(() => _digits = s);
    _isQuickPick = true;
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

  /// Single source of truth for every spelling of a Straight+Box ("All") bet.
  /// Shared by the amount-due text, the cart breakdown and the charge logic so
  /// the displayed amount always matches what is charged.
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

  void _incAmount() {
    final cur = double.tryParse(_amountCtrl.text) ?? 0.5;
    final step = 0.5;
    final min = 0.5;
    final nxt = (cur + step).clamp(min, 10.0);
    setState(() => _amountCtrl.text = nxt.toStringAsFixed(2));
  }

  void _decAmount() {
    final cur = double.tryParse(_amountCtrl.text) ?? 0.5;
    final step = 0.5;
    final min = 0.5;
    final nxt = (cur - step).clamp(min, 10.0);
    setState(() => _amountCtrl.text = nxt.toStringAsFixed(2));
  }

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

  /// UI-only mirror of the validation performed in _addToCart / AppState.
  /// It exists solely to gate the ADD button so invalid entries produce no
  /// snackbar at all. The real validation math stays unchanged on commit.
  bool get _canAdd {
    final expected = _expectedDigits;
    if (_digits.length != expected) return false;
    final amt = double.tryParse(_amountCtrl.text);
    if (amt == null) return false;
    final low = _betType.toLowerCase();
    final isCombo = low.contains('combo');
    final isAll = _isStBoxBet(_betType);
    final isBox = low == 'box';
    final allSame = _digits.split('').toSet().length == 1;
    if (allSame && (isBox || isAll || isCombo)) return false;
    final bool stepped = ((amt) * 100).round() % 50 == 0;
    if (!isCombo && !isAll && !isBox) {
      final maxStraight = expected == 3 ? 100.0 : 10.0;
      return amt >= 0.5 && amt <= maxStraight;
    } else if (isBox) {
      return amt >= 0.5 && amt <= 50 && stepped;
    }
    if (isCombo) {
      if (_comboCount(_digits.split('')) <= 1) return false;
      return amt >= 0.5 - 1e-9 && amt <= 10 + 1e-9 && stepped;
    }
    // ST/BOX (All): input limit keeps the doubled total within its cap.
    final maxAllInput = expected == 3 ? 50.0 : 25.0;
    return amt >= 0.5 - 1e-9 && amt <= maxAllInput + 1e-9 && stepped;
  }

  String _betInfoText() {
    final amt = double.tryParse(_amountCtrl.text);
    if (amt == null) return '';
    final low = _betType.toLowerCase();
    final isBoth = _drawMode == 'Both';
    final isAll = _isStBoxBet(_betType);
    if (low.contains('combo') && _digits.length >= 3) {
      final combos = _comboCount(_digits.split(''));
      if (combos <= 1)
        return 'Invalid Combo — 100% repeating digits (e.g. 111)';
      final total = amt * combos;
      if (isBoth) return 'Amount Due: \$${(total * 2).toStringAsFixed(2)}';
      return 'Amount Due: \$${total.toStringAsFixed(2)}';
    }
    if (isAll) {
      final total = amt * 2;
      if (isBoth) return 'Amount Due: \$${(total * 2).toStringAsFixed(2)}';
      return 'Amount Due: \$${total.toStringAsFixed(2)}';
    }
    if (isBoth) return 'Amount Due: \$${(amt * 2).toStringAsFixed(2)}';
    return 'Amount Due: \$${amt.toStringAsFixed(2)}';
  }

  void _cycleBetType() {
    final idx = betTypes.indexOf(_betType);
    final next = betTypes[(idx + 1) % betTypes.length];
    setState(() => _betType = next);
  }

  void _cycleDigitMode() {
    setState(() {
      _digitMode = _digitMode == '3D' ? '4D' : '3D';
      if (_digitMode == '3D' && _digits.length > 3)
        _digits = _digits.substring(0, 3);
    });
  }

  String _clampDrawMode(
    String mode, {
    required bool morningOpen,
    required bool eveningOpen,
  }) {
    if (mode == 'Both' && !(morningOpen && eveningOpen)) {
      if (eveningOpen) return 'Evening';
      if (morningOpen) return 'Midday';
    }
    if (mode == 'Midday' && !morningOpen && eveningOpen) return 'Evening';
    if (mode == 'Evening' && !eveningOpen && morningOpen) return 'Midday';
    return mode;
  }

  void _applySellableDrawMode() {
    _drawMode = _clampDrawMode(
      _drawMode,
      morningOpen: _isTypeSellable('MIDDAY'),
      eveningOpen: _isTypeSellable('EVENING'),
    );
    _syncDrawModeToPeriods();
  }

  bool _isTypeSellable(String type) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    bool hasRes(Map e) {
      bool n(dynamic v) => v != null && v.toString().trim().isNotEmpty;
      return n(e['result']) || n(e['result3']) || n(e['result4']);
    }

    return _periods.any((e) {
      final dt = (e['drawType'] as String? ?? '').toUpperCase();
      if (dt != type) return false;
      final st = (e['status'] as String? ?? '').toUpperCase();
      if (st == 'CANCELLED' || st == 'POSTPONED' || st == 'SUSPENDED')
        return false;
      if (hasRes(e)) return false;
      final open = asInt(e['salesOpenTime']);
      final close = asInt(e['salesCloseTime']);
      return nowMs >= open && nowMs < close;
    });
  }

  Widget _appBarDrawField() {
    if (_loadingDraws)
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    final morningOpen = _isTypeSellable('MIDDAY');
    final eveningOpen = _isTypeSellable('EVENING');
    final bothOpen = morningOpen && eveningOpen;
    if (!morningOpen && !eveningOpen) {
      return const Text(
        'Sales closed',
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    final effective = _clampDrawMode(
      _drawMode,
      morningOpen: morningOpen,
      eveningOpen: eveningOpen,
    );
    return SizedBox(
      height: 42,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effective,
          isDense: true,
          // Let the title shrink when the cart badge appears in the AppBar
          // actions; otherwise its intrinsic width overflows the toolbar.
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: Colors.white,
          ),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
          dropdownColor: Colors.white,
          underline: const SizedBox(),
          onChanged: (v) async {
            if (v == null) return;
            if (v == 'Midday' && !morningOpen) return;
            if (v == 'Evening' && !eveningOpen) return;
            if (v == 'Both' && !bothOpen) return;
            setState(() {
              _drawMode = v;
              _syncDrawModeToPeriods();
            });
            // Allow mixing in the same invoice: do not convert the existing cart
            // when changing the period, existing items remain as-is (Morning/Evening/Both)
            // and new items are added with the new period — this fulfills the user's request
            // "play Morning and Evening and Both in the same game in the same invoice"
          },
          selectedItemBuilder: (ctx) {
            final labels = <String, String>{
              if (morningOpen) 'Midday': 'Morning',
              if (eveningOpen) 'Evening': 'Evening',
              if (bothOpen) 'Both': 'Both',
            };
            return [
              for (final e in labels.entries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      e.key == 'Midday'
                          ? Icons.wb_sunny
                          : e.key == 'Evening'
                          ? Icons.nights_stay
                          : Icons.copy_all,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        e.value,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
            ];
          },
          items: [
            if (morningOpen)
              DropdownMenuItem(
                value: 'Midday',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wb_sunny, size: 16, color: AppTheme.green),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'Morning',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (eveningOpen)
              DropdownMenuItem(
                value: 'Evening',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.nights_stay, size: 16, color: AppTheme.green),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'Evening',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (bothOpen)
              DropdownMenuItem(
                value: 'Both',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy_all, size: 16, color: AppTheme.green),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'Both',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ADD to cart (before SALE, removable) — supports Both (Spec §13-14)
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
    final morningOpen = _isTypeSellable('MIDDAY');
    final eveningOpen = _isTypeSellable('EVENING');
    if (_drawMode == 'Both' && !(morningOpen && eveningOpen)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Both is not available — a period is closed. Play the open period only.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      setState(_applySellableDrawMode);
      return;
    }
    if (_drawMode == 'Midday' && !morningOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Morning is closed — Evening only'),
          backgroundColor: Colors.red,
        ),
      );
      setState(_applySellableDrawMode);
      return;
    }
    if (_drawMode == 'Evening' && !eveningOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Evening is closed'),
          backgroundColor: Colors.red,
        ),
      );
      setState(_applySellableDrawMode);
      return;
    }
    if (_digits.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter numbers first')));
      return;
    }
    final need = _digitMode == '3D' ? 3 : 4;
    if (_digits.length != need) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter exactly $need digits for $_digitMode mode',
          ),
        ),
      );
      return;
    }
    final amt = double.tryParse(_amountCtrl.text);
    if (amt == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invalid amount')));
      return;
    }
    final low = _betType.toLowerCase();
    final isCombo = low.contains('combo');
    final isAll = _isStBoxBet(_betType);
    final isBox = low == 'box';
    final allSame = _digits.split('').toSet().length == 1;
    if (allSame && (isBox || isAll || isCombo)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Repeated digits like $_digits are allowed in Straight only — choose Straight or change the number',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!isCombo && !isAll && !isBox) {
      final is3D = _digitMode == '3D';
      final maxStraight = is3D ? 100.0 : 10.0;
      if (amt < 0.5 || amt > maxStraight) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Amount \$0.50 - \$${maxStraight.toStringAsFixed(2)} for Straight ${is3D ? 3 : 4}D',
            ),
          ),
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
      final combos = _comboCount(_digits.split(''));
      if (combos <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Combo not valid for $_digits — requires distinct permutations',
            ),
          ),
        );
        return;
      }
      // the entered amount is per single combo — total = amt × combos
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
      final is3D = _digitMode == '3D';
      final maxAllInput = is3D ? 50.0 : 25.0; // total = amt*2 => 50 limit
      if (amt < 0.5 - 1e-9) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('All min \$0.50')));
        return;
      }
      if (amt > maxAllInput + 1e-9) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'All max \$${maxAllInput.toStringAsFixed(2)} (total \$${(maxAllInput * 2).toStringAsFixed(2)})',
            ),
          ),
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
    try {
      double cartAmount = amt;
      int? comboCount;
      if (isCombo) {
        comboCount = _comboCount(_digits.split(''));
        cartAmount = amt * comboCount; // total amount due
      } else if (isAll) {
        cartAmount = amt * 2; // All = $1 Straight + $1 Box = $2 per draw
      }
      if (_drawMode == 'Both') {
        // Both: amountPerDraw is the total for one draw, total for both = amountPerDraw*2
        await context.read<AppState>().addBothToCart(
          gameId: 'g_numbers',
          gameName: 'Numbers',
          numbers: _digits.split(''),
          betType: _betType,
          amountPerDraw: cartAmount,
          isQuickPick: _isQuickPick,
        );
        setState(() => _digits = '');
        _isQuickPick = false;
      } else {
        final draw = _draws.firstWhere(
          (d) => d['id'] == _drawId,
          orElse: () => {},
        );
        await context.read<AppState>().addToCart(
          gameId: 'g_numbers',
          gameName: 'Numbers',
          drawId: _drawId,
          drawName: draw['name'] as String?,
          drawType: _drawMode == 'Evening' ? 'EVENING' : 'MIDDAY',
          numbers: _digits.split(''),
          betType: _betType,
          amount: cartAmount,
          isQuickPick: _isQuickPick,
        );
        setState(() => _digits = '');
        _isQuickPick = false;
      }
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
      showSaleToast(context, 'Cart empty â€” add numbers first', error: true);
      return;
    }
    try {
      final ticket = await app.commitSale();
      if (!mounted) return;
      showSaleToast(
        context,
        'SALE success â€” Ticket ${ticket['id']} â€¢ ${ticket['linesCount']} plays â€¢ ${fmtMoney(ticket['total'])}',
        color: AppTheme.green,
      );
      await _load();
      // if there is a default printer — print directly without navigating to a page
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

  Widget _buildCartSection() {
    return Consumer<AppState>(
      builder: (ctx, app, _) {
        final cart = app.cart;
        if (cart.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          color: const Color(0xFFF0F7F0),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              // CLEAR — deletes the invoice/all items
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
                      fontSize: 13,
                      color: Colors.red,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: Colors.white,
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
                      backgroundColor: AppTheme.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'SALE • ${fmtMoney(app.cartTotal)} (${cart.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
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

  Widget _buildCurrentPlays() {
    return Consumer<AppState>(
      builder: (ctx, app, _) {
        final cart = app.cart;
        if (cart.isEmpty) return _empty();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          itemCount: cart.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (c, i) {
            final item = cart[i];
            final numText = item.numbers.join('   ');
            String subText = fmtMoney(item.amount);
            final low = item.betType.toLowerCase();
            if (low.contains('combo')) {
              final combos = _comboCount(item.numbers);
              final per = combos > 0 ? item.amount / combos : item.amount;
              subText =
                  '${combos}×\$${per.toStringAsFixed(2)} = ${fmtMoney(item.amount)}';
            } else if (_isStBoxBet(item.betType)) {
              final perSide = item.amount / 2;
              subText =
                  '\$${perSide.toStringAsFixed(2)}+${perSide.toStringAsFixed(2)}=${fmtMoney(item.amount)}';
            }
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.green.withValues(alpha: 0.14),
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
                        color: AppTheme.green,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Wrap lets the chips flow onto a second line on
                              // narrow phones instead of overflowing the row.
                              Expanded(
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.greenLight,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        item.betType,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.green,
                                        ),
                                      ),
                                    ),
                                    Builder(
                                      builder: (_) {
                                        final p =
                                            (item.drawType ??
                                                    item.periodId ??
                                                    item.drawName ??
                                                    '')
                                                .toString()
                                                .toUpperCase();
                                        final isEve =
                                            p.contains('EVENING') ||
                                            p.contains('EVE');
                                        final isMid =
                                            p.contains('MIDDAY') ||
                                            p.contains('MORNING') ||
                                            p.contains('MID');
                                        final label = isEve
                                            ? 'EVENING'
                                            : isMid
                                            ? 'MIDDAY'
                                            : '';
                                        if (label.isEmpty)
                                          return const SizedBox.shrink();
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isEve
                                                ? const Color(0xFFF3E5F5)
                                                : const Color(0xFFFFF8E1),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: isEve
                                                  ? Colors.purple.shade200
                                                  : Colors.orange.shade200,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                isEve
                                                    ? Icons.nights_stay
                                                    : Icons.wb_sunny,
                                                size: 10,
                                                color: isEve
                                                    ? Colors.purple
                                                    : Colors.orange.shade700,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                label,
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.w900,
                                                  color: isEve
                                                      ? Colors.purple.shade700
                                                      : Colors.orange.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 170,
                                      ),
                                      child: Text(
                                        subText,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.bg,
                                  borderRadius: BorderRadius.circular(20),
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
                            numText,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.event,
                                size: 12,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${item.drawName ?? '-'} • ${item.gameName} • ${fmtMoney(item.amount)}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.textMuted,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => app.removeFromCart(item.id),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
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
    );
  }

  Widget _buildControlBar() {
    final digitsField = InkWell(
      onTap: _cycleDigitMode,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        width: 90,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
          color: _digitMode == '3D' ? AppTheme.greenLight : Colors.white,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.pin,
              size: 14,
              color: _digitMode == '3D' ? AppTheme.green : AppTheme.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              _digitMode,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _digitMode == '3D' ? AppTheme.green : AppTheme.textDark,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.swap_horiz, size: 14, color: AppTheme.textMuted),
          ],
        ),
      ),
    );

    IconData _typeIcon() {
      if (_betType == 'Straight') return Icons.straighten;
      if (_betType == 'Box') return Icons.inventory_2_outlined;
      if (_betType.toLowerCase().contains('combo')) return Icons.shuffle;
      if (_betType == 'All' || _betType == 'Straight/Box')
        return Icons.layers_outlined;
      return Icons.shuffle;
    }

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
            Icon(_typeIcon(), size: 14, color: AppTheme.green),
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          digitsField,
          const SizedBox(width: 8),
          typeField,
          const SizedBox(width: 8),
          amountStepper,
        ],
      ),
    );
  }

  Widget _buildInputPanel() {
    final info = _betInfoText();
    // Save vertical space on short/narrow phones so the cart section and
    // keypad still fit without a vertical overflow.
    final bool compact = MediaQuery.of(context).size.width < 400;
    final double digitBox = compact ? 42 : 48;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(12, compact ? 6 : 10, 12, compact ? 6 : 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_digitMode == '3D' ? 3 : 4, (idx) {
              final has = idx < _digits.length;
              final char = has ? _digits[idx] : '';
              return Container(
                width: digitBox,
                height: digitBox,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: has ? AppTheme.green : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: has ? AppTheme.green : AppTheme.cardBorder,
                    width: has ? 2 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: has
                    ? Text(
                        char,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        '—',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade400,
                        ),
                      ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Text(
            _digits.isEmpty
                ? '${_digitMode == '3D' ? '3' : '4'} digits (0-9)'
                : '${_digits.length}/${_digitMode == '3D' ? '3' : '4'}',
            style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 10),
          if (_loadingDraws)
            const LinearProgressIndicator(color: AppTheme.green)
          else
            _buildControlBar(),
          if (info.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _betType.toLowerCase().contains('combo')
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _betType.toLowerCase().contains('combo')
                      ? AppTheme.green.withValues(alpha: 0.3)
                      : AppTheme.blue.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                info,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _betType.toLowerCase().contains('combo')
                      ? AppTheme.green
                      : AppTheme.blue,
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
    );
  }

  Widget _keypadGrid({double aspect = 1.8}) {
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
        _keyBtn(
          'C',
          onTap: _clear,
          bg: const Color(0xFFFFF1F1),
          fg: Colors.red,
          border: const Color(0xFFFFC9C9),
        ),
        _keyBtn('0', onTap: () => _pressDigit('0')),
        _keyBtn('', onTap: _back, icon: Icons.backspace_outlined),
      ],
    );
  }

  Widget _quickPickButton() {
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
          side: BorderSide(color: AppTheme.green.withValues(alpha: 0.4)),
        ),
      ),
    );
  }

  Widget _addToCartButton() {
    final enabled = _canAdd;
    return InkWell(
      onTap: enabled ? _addToCart : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: enabled ? AppTheme.blue : Colors.grey.shade400,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_shopping_cart, color: Colors.white, size: 28),
            SizedBox(height: 4),
            Text(
              'ADD',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'to cart',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 10,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Single-line ADD button used when the keypad actions are stacked under the
  /// grid on narrow phones — a full-height button would overflow the column.
  Widget _addToCartButtonCompact() {
    final enabled = _canAdd;
    return InkWell(
      onTap: enabled ? _addToCart : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: enabled ? AppTheme.blue : Colors.grey.shade400,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.cardBorder),
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

  Widget _buildKeypad() {
    const gridHeight = 4 * 56 + 3 * 8 + 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this width the 1-flex action column (< ~84dp) cannot fit the
        // "Quick Pick" label, so stack the actions under a full-width keypad.
        final bool stackActions = constraints.maxWidth < 360;
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.all(8),
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
                        height: gridHeight,
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
        );
      },
    );
  }

  Future<String?> _askDrawChoiceForReplay() => showDrawPeriodChoice(context);

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
              'Enter Ticket ID or Serial — e.g. 000001 or 00000001',
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
    // delegate to same flow as scan but with manual code
    await _handleReplayCode(code.trim());
  }

  Future<void> _handleReplayCode(String code) async {
    final app = context.read<AppState>();
    final res = await app.validateTicket(code.trim());
    if (!mounted) return;
    if (res['found'] == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ticket not found: $code — try the barcode or serial number',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final ticket = res['ticket'] as Map<String, dynamic>;
    final lines = res['lines'] as List<Map<String, dynamic>>?;
    final lineDetails = res['lineDetails'] as List?;
    final isWinning = res['isWinning'] == true;
    final prize = asDouble(res['prize']);
    final pending = res['pending'] == true;
    final st = (ticket['status'] as String? ?? '').toLowerCase();
    final blockedForResale = st == 'paid' || st == 'cancelled';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(
              isWinning ? Icons.emoji_events : Icons.confirmation_number,
              color: isWinning ? AppTheme.green : Colors.black54,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ticket ${ticket['id']}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (st == 'paid')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'PAID — no re-sale',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            if (st == 'cancelled')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'CANCELLED — no re-sale',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            if (!blockedForResale && isWinning)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Winner',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
            if (pending)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Pending', style: TextStyle(fontSize: 9)),
              ),
          ],
        ),
        content: ConstrainedBox(
          // A fixed 400dp dialog overflows 320-411dp phones; let it shrink to
          // the available width while capping it on larger screens.
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Serial: ${ticket['serialNumber']} - ${fmtDate(ticket['createdAt'])}',
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
                Text(
                  'Status: ${ticket['status']} - Total: ${fmtMoney(ticket['total'] ?? ticket['amount'])}',
                  style: const TextStyle(fontSize: 11),
                ),
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
                if (isWinning)
                  Text(
                    'Prize: ${fmtMoney(prize)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.green,
                    ),
                  ),
                const Divider(height: 12),
                if (lines != null && lines.isNotEmpty) ...[
                  const Text(
                    'All numbers in this ticket:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  for (int i = 0; i < lines.length; i++)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            (lineDetails != null &&
                                lineDetails[i]['isWinning'] == true)
                            ? Colors.green.shade50
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              (lineDetails != null &&
                                  lineDetails[i]['isWinning'] == true)
                              ? Colors.green
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${i + 1}.',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            (lines[i]['numbers'] as String).replaceAll(
                              ',',
                              ' ',
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              _dispBet(lines[i]['betType']),
                              style: const TextStyle(fontSize: 9),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            fmtMoney(lines[i]['amount']),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (lineDetails != null)
                            Icon(
                              lineDetails[i]['isWinning'] == true
                                  ? Icons.check_circle
                                  : lineDetails[i]['pending'] == true
                                  ? Icons.hourglass_empty
                                  : Icons.cancel,
                              size: 16,
                              color: lineDetails[i]['isWinning'] == true
                                  ? Colors.green
                                  : lineDetails[i]['pending'] == true
                                  ? Colors.orange
                                  : Colors.red,
                            ),
                        ],
                      ),
                    ),
                ] else ...[
                  Text(
                    'Number: ${(ticket['numbers'] as String).replaceAll(',', ' ')} - ${_dispBet(ticket['betType'])}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF7FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'When copying you will choose Midday (14:30), Evening (22:30), or both.',
                    style: TextStyle(fontSize: 9, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text(
              'Copy — choose period',
              style: TextStyle(fontSize: 11),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.green,
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
                          ? 'Midday only'
                          : 'Evening only';
                      String extra = '';
                      if (skipped.isNotEmpty)
                        extra += ' — ${skipped.length} deleted';
                      if (trimmed.isNotEmpty)
                        extra += ' — ${trimmed.length} trimmed';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Copied $count play(s) → $label — tap SALE to print$extra',
                          ),
                          backgroundColor: AppTheme.green,
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
                              'Copied with adjustments',
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
                                    'Copied $count → $label',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  if (skipped.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      '⚠️ Deleted (Sold Out):',
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
                                      '✂️ Trimmed to remaining:',
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
                                child: const Text('OK'),
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

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final isTablet =
        Responsive.isTablet(context) || Responsive.isDesktop(context);
    final isLand = Responsive.isLandscape(context);
    final useTwoPane = isTablet && isLand && screenWidth >= 900;
    // On narrow phones the title dropdown cannot sit beside three action
    // icons and the cart badge. Collapse the two utility icons into a single
    // overflow menu and cap the badge so the toolbar never overflows.
    final bool compactAppBar = screenWidth < 480;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (Navigator.canPop(context)) {
          Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
        } else {
          Navigator.pushReplacementNamed(context, '/home');
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: _appBarDrawField(),
          centerTitle: true,
          leadingWidth: compactAppBar ? 48 : 56,
          actions: [
            // Compact phones: one menu instead of two separate utility icons.
            if (compactAppBar)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                tooltip: 'More actions',
                onSelected: (value) {
                  if (value == 'scan') {
                    _scanAndReplay();
                  } else if (value == 'search') {
                    _copyByTicketNumber();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem<String>(
                    value: 'scan',
                    child: Text('Scan barcode', style: TextStyle(fontSize: 13)),
                  ),
                  PopupMenuItem<String>(
                    value: 'search',
                    child: Text(
                      'Search ticket',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            if (!compactAppBar) ...[
              IconButton(
                icon: const Icon(Icons.qr_code_scanner, size: 20),
                tooltip: 'Scan barcode',
                onPressed: _scanAndReplay,
              ),
              IconButton(
                icon: const Icon(Icons.search, size: 20),
                tooltip: 'Search by ticket number',
                onPressed: _copyByTicketNumber,
              ),
            ],
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
                                color: AppTheme.green,
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
              icon: const Icon(Icons.logout, size: 18),
              onPressed: () => _logout(),
            ),
          ],
        ),
        drawer: const AppDrawer(currentRoute: '/numbers'),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: useTwoPane
                ? Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Column(
                          children: [
                            Expanded(child: _buildCurrentPlays()),
                            _buildCartSection(),
                          ],
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: AppTheme.cardBorder,
                      ),
                      Expanded(
                        flex: 4,
                        child: Column(
                          children: [
                            _buildInputPanel(),
                            _buildKeypad(),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: _buildCurrentPlays()),
                      _buildCartSection(),
                      _buildInputPanel(),
                      _buildKeypad(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  String _drawLabel(Map<String, dynamic> d) {
    final name = d['name'] as String;
    String period = 'Draw';
    if (name.contains('Morning'))
      period = 'Morning';
    else if (name.contains('Midday'))
      period = 'Morning';
    else if (name.contains('Evening'))
      period = 'Evening';
    else if (name.contains('Night'))
      period = 'Night';
    final dt = DateTime.fromMillisecondsSinceEpoch(asInt(d['drawTime']));
    final time =
        '${dt.hour > 12 ? dt.hour - 12 : dt.hour}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
    return '$period • $time';
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.greenLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                color: AppTheme.green,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No tickets yet',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Enter digits → ADD to cart → SALE to print one ticket',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Consumer<AppState>(
              builder: (_, app, __) => app.isCartEmpty
                  ? const SizedBox()
                  : Text(
                      'Cart: ${app.cartCount} plays • ${fmtMoney(app.cartTotal)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawer() => const AppDrawer(currentRoute: '/numbers');

  Widget _keyBtn(
    String label, {
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
                  label,
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
