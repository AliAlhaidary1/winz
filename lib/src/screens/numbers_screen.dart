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
  final betTypes = ['Straight', 'Box', 'ST/BOX', 'Combo'];
  List<Map<String, dynamic>> _periods = [];
  Timer? _sellableTick;

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
    // فلترة legacy draws: فقط المستقبلية + المفتوحة حسب draw_periods
    final openPeriods = await db.getOpenPeriods();
    final openIds = openPeriods.map((p) => p['id'] as String).toSet();
    // draws التي تتوافق مع فترة OPEN و drawTime في المستقبل (5 دقائق سماح)
    final List<Map<String, dynamic>> draws =
        allDraws.where((d) {
          if (d['status'] != 'open') return false;
          final dt = d['drawTime'] as int;
          if (dt <= nowMs - 5 * 60 * 1000) return false; // منتهية
          // تحقق من الفترة المقابلة
          final name = d['name'] as String;
          final isMidday = name.contains('Midday') || name.contains('Morning');
          final type = isMidday ? 'MIDDAY' : 'EVENING';
          final drawDt = DateTime.fromMillisecondsSinceEpoch(dt);
          final pid =
              '${drawDt.year}-${drawDt.month.toString().padLeft(2, '0')}-${drawDt.day.toString().padLeft(2, '0')}-$type';
          return openIds.contains(pid);
        }).toList()..sort(
          (a, b) => (a['drawTime'] as int).compareTo(b['drawTime'] as int),
        );
    final List<Map<String, dynamic>> finalDraws = draws;
    final periods = await db.getAllPeriods();
    if (!mounted) return;
    // السماح بالخلط: لا نحتاج لاشتقاق الفترة من السلة (معطّل)
    // final cart = context.read<AppState>().cart; // غير مستخدم الآن
    setState(() {
      _draws = finalDraws;
      if (_draws.isNotEmpty) {
        _drawId = _draws.first['id'] as String;
      } else {
        _drawId = null;
      }
      _periods = periods;
      _loadingDraws = false;
      // السماح بالخلط: لا نفرض تغيير الفترة حسب السلة عند وجود خلط يدوي
      // نحتفظ باختيار المستخدم الحالي، فقط نطبق قيود الإغلاق
      // if (modeFromCart != null) _drawMode = modeFromCart; // معطّل للسماح بـ Midday + Evening + Both بنفس الفاتورة
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
      final close = p['salesCloseTime'] as int;
      final rem = close - DateTime.now().millisecondsSinceEpoch;
      if (rem <= 0) return 'SALES CLOSED';
      final d = Duration(milliseconds: rem);
      return '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
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
      final open = e['salesOpenTime'] as int? ?? 0;
      final close = e['salesCloseTime'] as int? ?? 0;
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
          isExpanded: false,
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
            // السماح بالخلط في نفس الفاتورة: لا نعيد تحويل السلة القديمة
            // عند تغيير الفترة، تبقى العناصر السابقة كما هي (صباحي/مسائي/Both)
            // والعناصر الجديدة فقط ستُضاف بالفترة الجديدة — هذا يحقق طلب المستخدم
            // "العب صباحي ومسائي و Both بنفس اللعبة بنفس الفاتورة"
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
                    Text(
                      e.value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
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
      // المبلغ المدخل هو للتركيبة الواحدة — الإجمالي = amt × combos
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
        cartAmount = amt * comboCount; // الإجمالي المطلوب دفعه
      } else if (isAll) {
        cartAmount = amt * 2; // All = $1 Straight + $1 Box = $2 لكل سحب
      }
      if (_drawMode == 'Both') {
        // Both: amountPerDraw هو الإجمالي للسحب الواحد، الإجمالي للاثنين = amountPerDraw*2
        await context.read<AppState>().addBothToCart(
          gameId: 'g_numbers',
          gameName: 'Numbers',
          numbers: _digits.split(''),
          betType: _betType,
          amountPerDraw: cartAmount,
          isQuickPick: _isQuickPick,
        );
        final savedAmt = amt;
        final savedCombos = comboCount;
        final savedTotal = cartAmount;
        setState(() => _digits = '');
        _isQuickPick = false;
        if (!mounted) return;
        if (isCombo && savedCombos != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Added BOTH COMBO: \$${savedAmt.toStringAsFixed(2)}×$savedCombos = \$${savedTotal.toStringAsFixed(2)} per draw • total \$${(savedTotal * 2).toStringAsFixed(2)}',
              ),
              backgroundColor: AppTheme.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Added BOTH: ${cartAmount.toStringAsFixed(2)} Midday + ${cartAmount.toStringAsFixed(2)} Evening = \$${(cartAmount * 2).toStringAsFixed(2)}',
              ),
              backgroundColor: AppTheme.green,
            ),
          );
        }
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
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added to cart — now press SALE to print ticket'),
            backgroundColor: AppTheme.green,
          ),
        );
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
              border: Border.all(color: AppTheme.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 18,
                  color: AppTheme.green,
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
                      color: AppTheme.greenLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Cash',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.green,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                const Text(
                  'تغيير',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.green,
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: AppTheme.green,
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
                            color: AppTheme.green,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppTheme.greenLight,
                                child: Icon(
                                  isDefault
                                      ? Icons.person_outline
                                      : Icons.person,
                                  size: 16,
                                  color: AppTheme.green,
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
                        color: AppTheme.green,
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
                                  final added = res['added'] as int;
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
                                    color: AppTheme.green,
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
                                    color: AppTheme.green,
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
      showSaleToast(context, 'Cart empty — add numbers first', error: true);
      return;
    }
    try {
      final ticket = await app.commitSale();
      if (!mounted) return;
      showSaleToast(
        context,
        'SALE success — Ticket ${ticket['id']} • ${ticket['linesCount']} plays • ${fmtMoney(ticket['total'])}',
        color: AppTheme.green,
      );
      await _load();
      // إذا توجد طابعة افتراضية — اطبع مباشرة بدون انتقال للصفحة
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
              // CLEAR — يحذف الفاتورة/كل العناصر
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
                  child: ElevatedButton.icon(
                    onPressed: _doSale,
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: Text(
                      'SALE • ${fmtMoney(app.cartTotal)} (${cart.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.green,
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
                              const SizedBox(width: 6),
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
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isEve
                                          ? const Color(0xFFF3E5F5)
                                          : const Color(0xFFFFF8E1),
                                      borderRadius: BorderRadius.circular(6),
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
                              Flexible(
                                child: Text(
                                  subText,
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_digitMode == '3D' ? 3 : 4, (idx) {
              final has = idx < _digits.length;
              final char = has ? _digits[idx] : '';
              return Container(
                width: 48,
                height: 48,
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
                overflow: TextOverflow.visible,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKeypad() {
    final gridHeight = 4 * 56 + 3 * 8 + 8.0;
    return Container(
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
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: SizedBox(
              height: gridHeight,
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
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        side: BorderSide(
                          color: AppTheme.green.withValues(alpha: 0.4),
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
                          border: Border.all(color: AppTheme.cardBorder),
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
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
    final prize = (res['prize'] as num?)?.toDouble() ?? 0;
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
        content: SizedBox(
          width: 400,
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
                      final count = res['added'] as int;
                      final skipped = (res['skipped'] as List).cast<String>();
                      final trimmed = (res['trimmed'] as List).cast<String>();
                      final label = choice == 'BOTH'
                          ? 'Both (×2)'
                          : choice == 'MIDDAY'
                          ? 'Midday only'
                          : 'Evening only';
                      String extra = '';
                      if (skipped.isNotEmpty)
                        extra += ' — ${skipped.length} محذوف';
                      if (trimmed.isNotEmpty)
                        extra += ' — ${trimmed.length} مقلّل';
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

  @override
  Widget build(BuildContext context) {
    final isTablet =
        Responsive.isTablet(context) || Responsive.isDesktop(context);
    final isLand = Responsive.isLandscape(context);
    final useTwoPane =
        isTablet && isLand && MediaQuery.of(context).size.width >= 900;
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
          actions: [
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
            Consumer<AppState>(
              builder: (_, app, __) => app.isCartEmpty
                  ? const SizedBox()
                  : Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Center(
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
                              color: AppTheme.green,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
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
                            _buildCustomerSelector(context),
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
                      _buildCustomerSelector(context),
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
    final dt = DateTime.fromMillisecondsSinceEpoch(d['drawTime'] as int);
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
