import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../data/database.dart';
import '../services/backup_service.dart';

class CartItem {
  final String id; // local uuid for cart manipulation
  final String gameId;
  final String gameName;
  final String? drawId;
  final String? drawName;
  final String? periodId; // e.g., 2026-09-01-MIDDAY
  final String? drawType; // MIDDAY / EVENING / BOTH? For BOTH we split into two items
  final List<String> numbers;
  final String betType;
  final double amount; // amount per draw participation
  final bool isQuickPick;
  CartItem({
    required this.id,
    required this.gameId,
    required this.gameName,
    this.drawId,
    this.drawName,
    this.periodId,
    this.drawType,
    required this.numbers,
    required this.betType,
    required this.amount,
    required this.isQuickPick,
  });
  CartItem copyWith({
    String? drawId,
    String? drawName,
    String? periodId,
    String? drawType,
  }) => CartItem(
    id: id,
    gameId: gameId,
    gameName: gameName,
    drawId: drawId ?? this.drawId,
    drawName: drawName ?? this.drawName,
    periodId: periodId ?? this.periodId,
    drawType: drawType ?? this.drawType,
    numbers: numbers,
    betType: betType,
    amount: amount,
    isQuickPick: isQuickPick,
  );
  Map<String, dynamic> toMap() => {
    'id': id,
    'gameId': gameId,
    'gameName': gameName,
    'drawId': drawId,
    'drawName': drawName,
    'periodId': periodId,
    'drawType': drawType,
    'numbers': numbers.join(','),
    'betType': betType,
    'amount': amount,
    'isQuickPick': isQuickPick ? 1 : 0,
  };
}

class AppState extends ChangeNotifier {
  final AppDatabase db;
  AppState(this.db) {
    //     /Close    (00:00-14:15 / 00:00-22:20)
    Future.delayed(const Duration(seconds: 5), () async {
      try { await db.seedDrawPeriods(); await db.refreshPeriodStatuses(); } catch (_) {}
      // auto backup on startup (after DB ready)
      try {
        final bs = BackupService(db);
        await bs.performAutoBackupIfDue();
      } catch (_) {}
    });
    // periodic refresh while app is alive
    Stream.periodic(const Duration(minutes: 1)).listen((_) async {
      try { await db.refreshPeriodStatuses(); await db.seedDrawPeriods(); } catch (_) {}
    });
    // periodic auto-backup check every 15 minutes
    Stream.periodic(const Duration(minutes: 15)).listen((_) async {
      try {
        final bs = BackupService(db);
        await bs.performAutoBackupIfDue();
      } catch (_) {}
    });
  }

  /// Manual backup triggered from UI — returns backup file path
  Future<String> triggerManualBackup() async {
    final bs = BackupService(db);
    return await bs.performBackup(reason: 'manual');
  }

  /// Get backup config for UI
  Future<Map<String, dynamic>> getBackupConfig() async {
    final bs = BackupService(db);
    return await bs.getBackupConfig();
  }

  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  // session expiry: 8 hours
  DateTime? _loginAt;
  bool get isSessionExpired {
    if (_loginAt == null) return true;
    return DateTime.now().difference(_loginAt!).inHours >= 8;
  }

  Future<bool> login(String username, String password) async {
    final acc = await db.findAccount(username.trim(), password);
    if (acc == null) return false;
    if (acc['status'] != 'active') return false;
    _currentUser = acc;
    _loginAt = DateTime.now();
    notifyListeners();
    return true;
  }

  void logout() {
    _currentUser = null;
    _loginAt = null;
    _cart.clear();
    notifyListeners();
  }

  // ============ CART (  SALE) ============
  final List<CartItem> _cart = [];
  List<CartItem> get cart => List.unmodifiable(_cart);
  int get cartCount => _cart.length;
  double get cartTotal => _cart.fold(0, (s, e) => s + e.amount);
  bool get isCartEmpty => _cart.isEmpty;

  // Helpers for bet-type normalization
  String _normBet(String s) => s.trim().toLowerCase().replaceAll('-', '/').replaceAll('_', '/').replaceAll(' ', '');
  bool _isComboBet(String norm) => norm.contains('combo');
  bool _isStraightBoxBet(String norm) =>
      norm == 'all' ||
      norm == 'all/box' ||
      norm == 'all/straight' ||
      (norm.contains('straight') && norm.contains('box')) ||
      norm == 'straightbox' ||
      norm == 'straight/box' ||
      norm == 'str/box' ||
      norm == 'strbox' ||
      norm == 'st/box' ||
      norm == 'stbox';

  String _periodIdForDate(DateTime date, String drawType) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d-${drawType.toUpperCase()}';
  }

  String _normalizeDrawType(String? raw) {
    final s = (raw ?? '').trim().toUpperCase();
    if (s.isEmpty) return s;
    // Evening first so "EVENING" is never classified as Midday.
    if (s == 'EVENING' || s.contains('EVENING') || s.contains('EVE') || s.contains('مساء') || s.contains('مسائ')) return 'EVENING';
    if (s == 'MORNING' || s == 'MIDDAY' || s.contains('MIDDAY') || s.contains('MORNING') || s.contains('MID') || s.contains('صباح')) return 'MIDDAY';
    return s;
  }

  String _drawTypeFromName(String? name) {
    final n = (name ?? '').toLowerCase();
    if (n.contains('evening') || n.contains('مساء') || n.contains('مسائ')) return 'EVENING';
    if (n.contains('midday') || n.contains('morning') || n.contains('صباح')) return 'MIDDAY';
    return '';
  }

  String _drawTypeFromDraw(Map<String, dynamic> d) {
    final fromName = _drawTypeFromName(d['name'] as String?);
    if (fromName == 'MIDDAY' || fromName == 'EVENING') return fromName;
    final id = (d['id'] as String? ?? '').toLowerCase();
    if (id.contains('evening')) return 'EVENING';
    if (id.contains('midday') || id.contains('morning')) return 'MIDDAY';
    final dt = DateTime.fromMillisecondsSinceEpoch(d['drawTime'] as int);
    return dt.hour >= 18 ? 'EVENING' : 'MIDDAY';
  }

  String _drawTypeFromPeriodId(String? periodId) {
    if (periodId == null) return '';
    final u = periodId.replaceAll('/', '-').trim().toUpperCase();
    if (u.endsWith('EVENING')) return 'EVENING';
    if (u.endsWith('MIDDAY') || u.endsWith('MORNING')) return 'MIDDAY';
    return '';
  }

  String _drawTypeLabel(String drawType) => _normalizeDrawType(drawType) == 'EVENING' ? 'مسائي' : 'صباحي';

  bool _periodHasResult(Map<String, dynamic> p) {
    bool nonempty(dynamic v) => v != null && v.toString().trim().isNotEmpty;
    return nonempty(p['result']) || nonempty(p['result3']) || nonempty(p['result4']);
  }

  bool _periodBlocked(Map<String, dynamic> p) {
    final s = ((p['status'] as String?) ?? '').toUpperCase();
    return s == 'CANCELLED' || s == 'POSTPONED' || s == 'SUSPENDED';
  }

  Future<(String? drawId, String drawName)> _drawMetaForPeriod(String gameId, Map<String, dynamic> period) async {
    final periodId = period['id'] as String;
    final periodDrawType = _normalizeDrawType(period['drawType'] as String?);
    final date = period['drawDate'] as String? ?? '';
    final fallbackName = '${periodDrawType == 'EVENING' ? 'Evening' : 'Midday'} $date';
    final draws = await db.getDrawsByGame(gameId);
    for (final d in draws) {
      if (_drawTypeFromDraw(d) != periodDrawType) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(d['drawTime'] as int);
      if (_periodIdForDate(dt, periodDrawType) == periodId) {
        return (d['id'] as String, d['name'] as String);
      }
    }
    return (null, fallbackName);
  }

  bool _periodInSalesWindow(Map<String, dynamic> p) {
    if (_periodBlocked(p) || _periodHasResult(p)) return false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final salesOpen = p['salesOpenTime'] as int? ?? 0;
    final salesClose = p['salesCloseTime'] as int? ?? 0;
    return nowMs >= salesOpen && nowMs < salesClose;
  }

  /// Only a period whose sales window is open now — never a closed period or tomorrow's fallback.
  Future<Map<String, dynamic>> _resolveNextSellablePeriod(String drawType) async {
    final normalized = _normalizeDrawType(drawType);
    if (normalized != 'MIDDAY' && normalized != 'EVENING') {
      throw Exception('فترة غير معروفة: $drawType');
    }
    await db.seedDrawPeriods();
    final now = DateTime.now();
    for (int i = 0; i < 3; i++) {
      final d = DateTime(now.year, now.month, now.day).add(Duration(days: i));
      await db.ensurePeriodExists(_periodIdForDate(d, normalized));
    }
    await db.refreshPeriodStatuses();
    final ofType = (await db.getAllPeriods()).where((p) {
      return _normalizeDrawType(p['drawType'] as String?) == normalized;
    }).toList()
      ..sort((a, b) => (a['drawTime'] as int).compareTo(b['drawTime'] as int));

    for (final p in ofType) {
      if (_periodInSalesWindow(p)) return p;
    }
    throw Exception('السحب ${_drawTypeLabel(normalized)} مغلق أو انتهى — لا يمكن اللعب');
  }

  Future<bool> isDrawTypeSellableNow(String drawType) async {
    try {
      await _resolveNextSellablePeriod(drawType);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _validatePeriodOpen(String periodId) async {
    // Normalize (fixes slash/case like 2026/08/31 middy)
    periodId = periodId.replaceAll('/', '-').trim().toUpperCase();
    await db.seedDrawPeriods();
    await db.refreshPeriodStatuses();
    var p = await db.getPeriodById(periodId);
    if (p == null) {
      await db.ensurePeriodExists(periodId);
      p = await db.getPeriodById(periodId);
    }
    if (p == null) {
      p = await db.getPeriodById(periodId.toLowerCase());
    }
    if (p == null) {
      await db.ensurePeriodExists(periodId.toUpperCase());
      p = await db.getPeriodById(periodId.toUpperCase());
    }
    if (p == null) throw Exception('Period $periodId not found — schedule not generated');
    if (_periodBlocked(p)) {
      throw Exception('الفترة $periodId ملغاة أو موقوفة');
    }
    if (_periodHasResult(p)) {
      throw Exception('تم نشر نتيجة $periodId — انسخها لفترة تالية (صباحي أو مسائي)');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final salesOpen = p['salesOpenTime'] as int;
    final salesClose = p['salesCloseTime'] as int;
    final drawTime = (p['drawTime'] as int?) ?? salesClose;
    if (now < salesOpen) {
      throw Exception('السحب $periodId لم يُفتح بعد');
    }
    if (now >= salesClose || now >= drawTime) {
      throw Exception('السحب $periodId مغلق أو انتهى — لا يمكن اللعب');
    }
    final status = p['status'] as String;
    if (status != 'OPEN' && now >= salesOpen && now < salesClose) {
      try { await db.updatePeriodStatus(periodId, 'OPEN'); } catch (_) {}
    }
  }

  // ===== Per-number per-period limit (risk control) =====
  // Canonical per bet group: Box/Combo/StrBox use sorted digits (any permutation = same)
  // Straight uses exact order.
  String _betGroup(String norm) {
    if (_isComboBet(norm)) return 'combo';
    if (_isStraightBoxBet(norm)) return 'strbox';
    if (norm == 'box') return 'box';
    return 'straight';
  }

  String _canonicalKey(List<String> digits, String group) {
    if (group == 'box' || group == 'combo' || group == 'strbox') {
      final sorted = List<String>.from(digits)..sort();
      return sorted.join();
    }
    return digits.join();
  }

  Future<double> _getLimitFor(String group, int nDigits) async {
    // Config keys: limit_straight_3, limit_straight_4, limit_box_3, limit_box_4, etc.
    // Defaults per user request: Straight3 = 100, Straight4 = 10, Box4 = 50, Box3 = 50
    double fallback;
    if (group == 'straight' && nDigits == 3) fallback = 100;
    else if (group == 'straight' && nDigits == 4) fallback = 10;
    else if (group == 'box' && nDigits == 3) fallback = 50;
    else if (group == 'box' && nDigits == 4) fallback = 50;
    else if (group == 'combo' && nDigits == 3) fallback = 100;
    else if (group == 'combo' && nDigits == 4) fallback = 10;
    else if (group == 'strbox' && nDigits == 3) fallback = 50;
    else if (group == 'strbox' && nDigits == 4) fallback = 50;
    else fallback = 10;
    try {
      final key = 'limit_${group}_${nDigits}';
      final rows = await db.customSelect("SELECT value FROM app_config WHERE key = ? LIMIT 1",
          variables: [Variable.withString(key)]).get();
      if (rows.isNotEmpty) {
        final v = double.tryParse(rows.first.data['value'] as String? ?? '');
        if (v != null) return v;
      }
      // legacy generic keys
      final altKey = group == 'straight' ? 'limit_straight' : group == 'box' ? 'limit_box' : null;
      if (altKey != null) {
        final rows2 = await db.customSelect("SELECT value FROM app_config WHERE key = ? LIMIT 1",
            variables: [Variable.withString(altKey)]).get();
        if (rows2.isNotEmpty) {
          final v = double.tryParse(rows2.first.data['value'] as String? ?? '');
          if (v != null) return v;
        }
      }
    } catch (_) {}
    return fallback;
  }

  // Sum already sold + current cart for same (periodId, gameId, group, canonical)
  Future<void> _enforcePerPeriodNumberLimit({
    required String periodId,
    required String gameId,
    required List<String> numbers,
    required String betType,
    required double amount,
  }) async {
    final norm = _normBet(betType);
    final group = _betGroup(norm);
    final n = numbers.length;
    final limit = await _getLimitFor(group, n);
    if (limit <= 0) return; // 0 = no limit
    final canonical = _canonicalKey(numbers, group);
    final pidNorm = periodId.replaceAll('/', '-').trim().toUpperCase();
    double existingSum = 0;
    double cartSum = 0;
    try {
      final lines = await db.getTicketLinesByPeriod(pidNorm);
      for (final l in lines) {
        // Skip cancelled tickets
        final ps = l['periodStatus'] as String?;
        if (ps == 'cancelled') continue;
        // filter by gameId
        if ((l['gameId'] as String) != gameId) continue;
        final lBet = (l['betType'] as String?) ?? 'Straight';
        final lNorm = _normBet(lBet);
        final lGroup = _betGroup(lNorm);
        if (lGroup != group) continue;
        final lNums = (l['numbers'] as String).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        if (lNums.length != n) continue;
        final lCanon = _canonicalKey(lNums, lGroup);
        if (lCanon != canonical) continue;
        existingSum += (l['amount'] as num).toDouble();
      }
    } catch (_) {}
    // Also check tickets table for legacy lines without periodId? Fallback: legacy via drawId->periodId mapping not needed for new periodId
    for (final c in _cart) {
      if (c.periodId == null) continue;
      final cPid = c.periodId!.replaceAll('/', '-').trim().toUpperCase();
      if (cPid != pidNorm) continue;
      if (c.gameId != gameId) continue;
      final cNorm = _normBet(c.betType);
      final cGroup = _betGroup(cNorm);
      if (cGroup != group) continue;
      if (c.numbers.length != n) continue;
      final cCanon = _canonicalKey(c.numbers, cGroup);
      if (cCanon != canonical) continue;
      cartSum += c.amount;
    }
    // FIX Combo 24-way: amount المدخل هو الإجمالي = perCombo * combos (مثلاً 1×24=24)
    // حد المخاطر الأساسي هو per-combo (10 للـ 4 أرقام) فيجب مقارنة wagerPerCombo أو total مقابل combos×limit
    double effectiveLimit = limit;
    int? combosForLimit;
    if (group == 'combo') {
      combosForLimit = _comboCount(numbers);
      if (combosForLimit > 1) effectiveLimit = limit * combosForLimit;
    }
    final total = existingSum + cartSum + amount;
    if (total > effectiveLimit + 1e-9) {
      final remaining = (effectiveLimit - existingSum - cartSum).clamp(0, effectiveLimit);
      final isBoxGroup = group == 'box' || group == 'combo' || group == 'strbox';
      final example = isBoxGroup ? ' (حتى لو تشقلبت الأرقام مثل 1123 = 2113)' : '';
      final digitLabel = n == 3 ? '3' : '4';
      final groupLabel = group == 'straight' ? 'Straight $digitLabel' : group == 'box' ? 'Box $digitLabel' : group == 'combo' ? 'Combo $digitLabel' : 'ST/BOX $digitLabel';
      final limitDetail = group == 'combo' && combosForLimit != null && combosForLimit > 1
          ? '\$$limit × $combosForLimit = \$$effectiveLimit إجمالي (\$${limit.toStringAsFixed(2)} لكل تركيبة)'
          : '\$$effectiveLimit';
      // للتوضيح: اعرض أيضاً per-combo إذا كان combo
      String perComboInfo = '';
      if (group == 'combo' && combosForLimit != null && combosForLimit > 1) {
        final perCombo = amount / combosForLimit;
        perComboInfo = ' — المطلوب: \$${amount.toStringAsFixed(2)} إجمالي = \$${perCombo.toStringAsFixed(2)} لكل تركيبة × $combosForLimit';
      } else {
        perComboInfo = ' — المطلوب: \$${amount.toStringAsFixed(2)}';
      }
      throw Exception(
          'الرقم ${numbers.join()} ($groupLabel$example) وصل للحد الأقصى $limitDetail في فترة $pidNorm — '
          'المباع حالياً: \$${existingSum.toStringAsFixed(2)} + السلة: \$${cartSum.toStringAsFixed(2)} — '
          'المتبقي المسموح: \$${remaining.toStringAsFixed(2)}$perComboInfo — الإجمالي سيصبح \$${total.toStringAsFixed(2)} > \$$effectiveLimit');
    }
  }

  // Validate logic shared
  void _validateCartItem({
    required String gameId,
    required List<String> numbers,
    required String betType,
    required double amount,
    String? drawId,
  }) {
    for (final d in numbers) {
      if (!RegExp(r'^[0-9]$').hasMatch(d)) throw Exception('Digits must be 0-9');
    }
    if (gameId == 'g_numbers') {
      if (numbers.length != 3 && numbers.length != 4) throw Exception('Numbers requires 3 or 4 digits');
    } else if (gameId == 'g_winz') {
      if (numbers.length != 4) throw Exception('Win 4 requires exactly 4 digits');
    }
    final btNorm = _normBet(betType);
    final isCombo = _isComboBet(btNorm);
    final isStrBox = _isStraightBoxBet(btNorm);
    final isBox = btNorm == 'box';
    // الأرقام المتطابقة (مثل 111 أو 2222) ممنوعة في Box / ST/BOX / Combo — مسموحة فقط في Straight
    final allSame = numbers.isNotEmpty && numbers.toSet().length == 1;
    if (allSame && (isBox || isStrBox || isCombo)) {
      throw Exception('الأرقام المتطابقة مثل ${numbers.join()} مسموحة فقط في Straight — غير مسموحة في Box / ST/BOX / Combo');
    }
    if (isCombo) {
      final combos = _comboCount(numbers);
      if (combos <= 1) throw Exception('Combo not valid for repeating digits like ${numbers.join()} — need distinct permutations');
      //       —     
      // : 123 (6 combos) + \$6.00 => \$1.00   \$1.00 + \$1.00 => Prize = wagerPerCombo * multiplier
      if (amount < 0.5 - 1e-9) throw Exception('Combo min \$0.50');
      if (amount > combos * 10 + 1e-9) throw Exception('Combo max \$${(combos * 10).toStringAsFixed(2)} ($combos × \$10)');
      if ((amount * 100).round() % 50 != 0) {
        throw Exception('Amount must be \$0.50 steps — e.g. \$0.50, \$1.00, \$1.50');
      }
    } else if (isStrBox) {
      // Straight/Box (All) —      (Straight + Box)
      //    $0.50  => $0.25     (Both) = amountPerDraw × 2
      // Per-number limit for StrBox is 50 (same as Box), so allow input up to 25 (=> total 50) but keep 10 for backward compat? Allow 50 total => input 25 max
      final maxInput = numbers.length == 3 ? 50 : 25; // total 50
      // Keep legacy 10 for small, but allow up to 25 for 4-digit StrBox to reach 50 total
      if (amount < 0.5 - 1e-9) throw Exception('Straight/Box (All) min \$0.50');
      if (amount > maxInput + 1e-9) throw Exception('Amount \$0.50 - \$$maxInput for Straight/Box (All)');
      if ((amount * 100).round() % 50 != 0) {
        throw Exception('Amount must be \$0.50 steps — e.g. \$0.50, \$1.00, \$1.50');
      }
    } else if (isBox) {
      // Box صريح — حد الفترة 50$ لكل رقم (حتى مع التقليب)
      const maxBox = 50.0;
      if (amount < 0.5 || amount > maxBox) throw Exception('Amount \$0.50 - \$${maxBox.toStringAsFixed(2)} for Box (limit per number per period \$$maxBox)');
      if ((amount * 100).round() % 50 != 0) throw Exception('Amount must be \$0.50 steps');
    } else {
      // Straight: limit per period per exact number = 100 for 3 digits, 10 for 4 digits
      final maxStraight = numbers.length == 3 ? 100.0 : 10.0;
      if (amount < 0.5 || amount > maxStraight) throw Exception('Amount \$0.50 - \$${maxStraight.toStringAsFixed(2)} for Straight ${numbers.length}D (limit \$$maxStraight)');
      if ((amount * 100).round() % 50 != 0) throw Exception('Amount must be \$0.50 steps');
    }
    if (drawId != null) {
      // draw open check is done at add time asynchronously; here sync part only
    }
  }

  Future<void> addToCart({
    required String gameId,
    required String gameName,
    String? drawId,
    String? drawName,
    String? periodId,
    String? drawType,
    required List<String> numbers,
    required String betType,
    required double amount,
    bool isQuickPick = false,
  }) async {
    if (_currentUser == null) throw Exception('Not logged in');
    _ensureNotExpired();
    _validateCartItem(gameId: gameId, numbers: numbers, betType: betType, amount: amount, drawId: drawId);
    String? resolvedPeriodId = periodId;
    String? resolvedDrawType = drawType != null ? _normalizeDrawType(drawType) : drawType;
    String? resolvedDrawId = drawId;
    String? resolvedDrawName = drawName;
    // Explicit Midday/Evening choice wins — never keep a closed source period
    if (resolvedDrawType == 'MIDDAY' || resolvedDrawType == 'EVENING') {
      final target = await _resolveNextSellablePeriod(resolvedDrawType!);
      resolvedPeriodId = target['id'] as String;
      resolvedDrawType = _normalizeDrawType(target['drawType'] as String?);
      final meta = await _drawMetaForPeriod(gameId, target);
      // Never keep a Midday drawId/name when the chosen period is Evening (or vice versa).
      resolvedDrawId = meta.$1;
      resolvedDrawName = meta.$2;
    } else if (resolvedPeriodId == null && drawId != null) {
      final draw = await db.getDrawById(drawId);
      if (draw != null) {
        final name = draw['name'] as String;
        String inferredPeriod = name.contains('Midday') || name.contains('Morning') ? 'MIDDAY' : name.contains('Evening') ? 'EVENING' : 'MIDDAY';
        resolvedDrawType = inferredPeriod;
        final dt = DateTime.fromMillisecondsSinceEpoch(draw['drawTime'] as int);
        resolvedPeriodId = _periodIdForDate(dt, inferredPeriod);
      }
    }
    if (resolvedPeriodId != null) {
      await _validatePeriodOpen(resolvedPeriodId);
      await _enforcePerPeriodNumberLimit(
        periodId: resolvedPeriodId,
        gameId: gameId,
        numbers: numbers,
        betType: betType,
        amount: amount,
      );
    }
    if (resolvedDrawId != null) {
      final draw = await db.getDrawById(resolvedDrawId);
      if (draw != null) {
        if (draw['status'] == 'closed' && resolvedPeriodId == null) throw Exception('Draw is closed — sales blocked');
        final drawTime = draw['drawTime'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now >= drawTime - 5 * 60 * 1000 && resolvedPeriodId == null) {
          final win = draw['winningNumbers'] as String?;
          if (win == null || win.toString().isEmpty) throw Exception('Sales closed — draw cutoff (5 min before)');
        }
      }
    }
    final item = CartItem(
      id: const Uuid().v4(),
      gameId: gameId,
      gameName: gameName,
      drawId: resolvedDrawId,
      drawName: resolvedDrawName,
      periodId: resolvedPeriodId,
      drawType: resolvedDrawType,
      numbers: List.from(numbers),
      betType: betType,
      amount: amount,
      isQuickPick: isQuickPick,
    );
    _cart.add(item);
    notifyListeners();
  }

  /// Both Draws: Creates two participations for the next two OPEN periods sequentially
  ///       →   Today +  
  Future<void> addBothToCart({
    required String gameId,
    required String gameName,
    required List<String> numbers,
    required String betType,
    required double amountPerDraw,
    bool isQuickPick = false,
    DateTime? forDate,
  }) async {
    if (_currentUser == null) throw Exception('Not logged in');
    _ensureNotExpired();
    _validateCartItem(gameId: gameId, numbers: numbers, betType: betType, amount: amountPerDraw);
    Map<String, dynamic>? midday;
    Map<String, dynamic>? evening;
    try { midday = await _resolveNextSellablePeriod('MIDDAY'); } catch (_) {}
    try { evening = await _resolveNextSellablePeriod('EVENING'); } catch (_) {}
    if (midday == null && evening == null) {
      throw Exception('لا توجد فترة مفتوحة للبيع الآن');
    }
    if (midday == null) {
      throw Exception('الصباحي مغلق أو انتهى — Both غير متاح. العب المسائي فقط');
    }
    if (evening == null) {
      throw Exception('المسائي مغلق أو انتهى — Both غير متاح. العب الصباحي فقط');
    }
    final targetPeriods = [midday, evening]
      ..sort((a, b) => (a['drawTime'] as int).compareTo(b['drawTime'] as int));
    final firstId = targetPeriods[0]['id'] as String;
    final secondId = targetPeriods[1]['id'] as String;
    await _validatePeriodOpen(firstId);
    await _validatePeriodOpen(secondId);
    // Enforce per-number limits for both periods separately (Box = sorted canonical)
    await _enforcePerPeriodNumberLimit(
      periodId: firstId,
      gameId: gameId,
      numbers: numbers,
      betType: betType,
      amount: amountPerDraw,
    );
    // For second, include first cart addition in cartSum simulation: temporarily add first to cart for check
    // To avoid double counting order, we check second against existing+cart (without first) + amount, then if first passes second will also pass with first included.
    // Do second check with awareness that first will be in cart: compute remaining after first.
    await _enforcePerPeriodNumberLimit(
      periodId: secondId,
      gameId: gameId,
      numbers: numbers,
      betType: betType,
      amount: amountPerDraw,
    );
    // Resolve drawIds for each (for backward compat legacy draws)
    String? firstDrawId;
    String? secondDrawId;
    String? firstDrawName;
    String? secondDrawName;
    final draws = await db.getDrawsByGame(gameId);
    for (final d in draws) {
      final dt = DateTime.fromMillisecondsSinceEpoch(d['drawTime'] as int);
      // Match by period id date+type
      for(final tp in targetPeriods){
        final tpDate = tp['drawDate'] as String;
        final tpType = tp['drawType'] as String;
        final dtStr = '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
        final isMatch = dtStr == tpDate && _drawTypeFromDraw(d) == _normalizeDrawType(tpType);
        if(isMatch){
          if(tp == targetPeriods[0]){ firstDrawId = d['id'] as String; firstDrawName = d['name'] as String; }
          if(tp == targetPeriods[1]){ secondDrawId = d['id'] as String; secondDrawName = d['name'] as String; }
        }
      }
    }
    // Create two independent cart items for the next two OPEN periods
    final firstPeriod = targetPeriods[0];
    final secondPeriod = targetPeriods[1];
    final firstItem = CartItem(
      id: const Uuid().v4(),
      gameId: gameId,
      gameName: gameName,
      drawId: firstDrawId,
      drawName: firstDrawName ?? '${firstPeriod['drawType']} ${firstPeriod['drawDate']}',
      periodId: firstId,
      drawType: firstPeriod['drawType'] as String,
      numbers: List.from(numbers),
      betType: betType,
      amount: amountPerDraw,
      isQuickPick: isQuickPick,
    );
    final secondItem = CartItem(
      id: const Uuid().v4(),
      gameId: gameId,
      gameName: gameName,
      drawId: secondDrawId,
      drawName: secondDrawName ?? '${secondPeriod['drawType']} ${secondPeriod['drawDate']}',
      periodId: secondId,
      drawType: secondPeriod['drawType'] as String,
      numbers: List.from(numbers),
      betType: betType,
      amount: amountPerDraw,
      isQuickPick: isQuickPick,
    );
    _cart.add(firstItem);
    _cart.add(secondItem);
    notifyListeners();
  }

  void removeFromCart(String cartId) {
    _cart.removeWhere((e) => e.id == cartId);
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    notifyListeners();
  }

  // Commit SALE -> one ticket (invoice) containing all cart lines
  Future<Map<String, dynamic>> commitSale() async {
    if (_currentUser == null) throw Exception('Not logged in');
    _ensureNotExpired();
    if (_cart.isEmpty) throw Exception('Cart is empty — add numbers first');
    // final validation for all draws still open — period-aware + legacy
    for (final item in _cart) {
      if (item.periodId != null) {
        await _validatePeriodOpen(item.periodId!);
      }
      if (item.drawId != null) {
        final draw = await db.getDrawById(item.drawId!);
        if (draw != null && draw['status'] == 'closed') throw Exception('Draw ${item.drawName} is closed');
        if (draw != null) {
          final drawTime = draw['drawTime'] as int;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now >= drawTime - 5 * 60 * 1000) {
            final win = draw['winningNumbers'] as String?;
            if (win == null || win.toString().isEmpty) throw Exception('Sales closed — cutoff for ${item.drawName}');
          }
        }
      }
    }
    // Final per-number per-period aggregate check (existing + whole cart)
    // Aggregate cart by (periodId, gameId, group, canonical)
    final Map<String, double> cartAgg = {};
    final Map<String, Map<String, dynamic>> aggMeta = {};
    for (final item in _cart) {
      if (item.periodId == null) continue;
      final norm = _normBet(item.betType);
      final group = _betGroup(norm);
      final canon = _canonicalKey(item.numbers, group);
      final pidNorm = item.periodId!.replaceAll('/', '-').trim().toUpperCase();
      final key = '$pidNorm|${item.gameId}|$group|$canon|${item.numbers.length}';
      cartAgg[key] = (cartAgg[key] ?? 0) + item.amount;
      aggMeta[key] = {'periodId': pidNorm, 'gameId': item.gameId, 'group': group, 'canon': canon, 'n': item.numbers.length, 'sampleNumbers': item.numbers, 'betType': item.betType};
    }
    for (final entry in cartAgg.entries) {
      final meta = aggMeta[entry.key]!;
      final periodId = meta['periodId'] as String;
      final gameId = meta['gameId'] as String;
      final group = meta['group'] as String;
      final canon = meta['canon'] as String;
      final n = meta['n'] as int;
      final sampleNumbers = meta['sampleNumbers'] as List<String>;
      final betType = meta['betType'] as String;
      final limit = await _getLimitFor(group, n);
      if (limit <= 0) continue;
      double existingSum = 0;
      try {
        final lines = await db.getTicketLinesByPeriod(periodId);
        for (final l in lines) {
          if ((l['periodStatus'] as String?) == 'cancelled') continue;
          if ((l['gameId'] as String) != gameId) continue;
          final lBet = (l['betType'] as String?) ?? 'Straight';
          final lNorm = _normBet(lBet);
          final lGroup = _betGroup(lNorm);
          if (lGroup != group) continue;
          final lNums = (l['numbers'] as String).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          if (lNums.length != n) continue;
          final lCanon = _canonicalKey(lNums, lGroup);
          if (lCanon != canon) continue;
          existingSum += (l['amount'] as num).toDouble();
        }
      } catch (_) {}
      // Combo fix: effectiveLimit = baseLimit * combos
      double effectiveLimit = limit;
      int? combosForLimit;
      if (group == 'combo') {
        combosForLimit = _comboCount(sampleNumbers);
        if (combosForLimit > 1) effectiveLimit = limit * combosForLimit;
      }
      final cartTotalForKey = entry.value;
      final total = existingSum + cartTotalForKey;
      if (total > effectiveLimit + 1e-9) {
        final remaining = (effectiveLimit - existingSum).clamp(0, effectiveLimit);
        final isBoxGroup = group == 'box' || group == 'combo' || group == 'strbox';
        final example = isBoxGroup ? ' (حتى لو تشقلبت الأرقام مثل 1123 = 2113)' : '';
        final digitLabel = n == 3 ? '3' : '4';
        final groupLabel = group == 'straight' ? 'Straight $digitLabel' : group == 'box' ? 'Box $digitLabel' : group == 'combo' ? 'Combo $digitLabel' : 'ST/BOX $digitLabel';
        final limitDetail = group == 'combo' && combosForLimit != null && combosForLimit > 1
            ? '\$$limit × $combosForLimit = \$$effectiveLimit إجمالي'
            : '\$$effectiveLimit';
        throw Exception(
            'الرقم ${sampleNumbers.join()} ($groupLabel$example) سيتجاوز الحد في فترة $periodId — '
            'المباع سابقاً: \$${existingSum.toStringAsFixed(2)} + سلة الشراء لهذا الرقم: \$${cartTotalForKey.toStringAsFixed(2)} = \$${total.toStringAsFixed(2)} > حد $limitDetail — '
            'المتبقي المسموح: \$${remaining.toStringAsFixed(2)}');
      }
    }
    final id = await db.nextTicketId();
    final serial = await db.nextSerialNumber();
    final barcode = id;
    final now = DateTime.now().millisecondsSinceEpoch;
    final total = cartTotal;
    // Header aggregation
    final distinctGames = _cart.map((e) => e.gameId).toSet();
    final distinctDraws = _cart.map((e) => e.drawId).toSet();
    final headerGameId = distinctGames.length == 1 ? _cart.first.gameId : 'multi';
    final headerGameName = distinctGames.length == 1 ? _cart.first.gameName : 'Mixed';
    // For header draw, if all same draw use it, otherwise first
    final headerDrawId = distinctDraws.length == 1 ? _cart.first.drawId : _cart.first.drawId;
    final headerDrawName = distinctDraws.length == 1 ? _cart.first.drawName : (_cart.first.drawName != null ? '${_cart.first.drawName} +${_cart.length-1}' : null);
    final headerBetType = _cart.length == 1 ? _cart.first.betType : 'Multi';
    // numbers for header: if multi, store as "123 Straight | 456 Box ..."
    final headerNumbers = _cart.map((e) => '${e.numbers.join()}(${e.betType})').join(' | ');
    // Keep numbers column for legacy display but we store summary; lines hold true data
    // For compatibility truncate if too long
    final headerNumbersCol = headerNumbers.length > 400 ? '${_cart.first.numbers.join(',')} +${_cart.length-1} more' : _cart.map((e)=> e.numbers.join(',')).join(';');

    final ticket = {
      'id': id,
      'serialNumber': serial,
      'gameId': headerGameId,
      'gameName': headerGameName,
      'drawId': headerDrawId,
      'drawName': headerDrawName,
      'numbers': headerNumbersCol,
      'betType': headerBetType,
      'amount': total,
      'total': total,
      'operatorId': _currentUser!['id'],
      'operatorName': _currentUser!['username'],
      'createdAt': now,
      'status': 'active',
      'barcode': barcode,
      'prizeAmount': null,
      'paidAt': null,
      'paidBy': null,
      'isQuickPick': _cart.any((e)=> e.isQuickPick) ? 1 : 0,
    };

    final lines = _cart.map((e) => {
      'id': const Uuid().v4(),
      'ticketId': id,
      'gameId': e.gameId,
      'gameName': e.gameName,
      'drawId': e.drawId,
      'drawName': e.drawName,
      'periodId': e.periodId,
      'periodStatus': 'active',
      'winningStatus': null,
      'prizeAmount': null,
      'numbers': e.numbers.join(','),
      'betType': e.betType,
      'amount': e.amount,
      'isQuickPick': e.isQuickPick ? 1 : 0,
    }).toList();

    await db.insertTicketWithLines(ticket, lines);

    // financial: single entry for whole sale
    await db.insertCashLedger({
      'id': const Uuid().v4(),
      'type': 'sale',
      'amount': total,
      'direction': 'in',
      'description': 'Sale $id — ${_cart.length} plays — $headerNumbers',
      'operatorId': _currentUser!['id'],
      'createdAt': now,
      'ticketId': id,
    });
    await db.insertBalanceMovement({
      'id': const Uuid().v4(),
      'type': 'sale',
      'amount': total,
      'direction': 'credit',
      'description': 'Sale $id',
      'operatorId': _currentUser!['id'],
      'createdAt': now,
      'ticketId': id,
    });

    _cart.clear();
    notifyListeners();
    // return ticket with lines for immediate print
    final result = Map<String, dynamic>.from(ticket);
    result['lines'] = lines;
    result['linesCount'] = lines.length;
    return result;
  }

  // Replay: copy whole ticket into cart for new sale
  Future<int> replayTicketToCart(String ticketId) async {
    return replayTicketToCartWithChoice(ticketId, 'AUTO');
  }

  /// Replay with explicit draw choice: MIDDAY (صباحي), EVENING (مسائي), BOTH (الاثنين), AUTO (auto-detect open)
  Future<int> replayTicketToCartWithChoice(String ticketId, String drawChoice) async {
    ticketId = ticketId.trim();
    drawChoice = drawChoice.trim().toUpperCase();
    final lines = await db.getTicketLines(ticketId);
    List<Map<String,dynamic>> source;
    if (lines.isEmpty) {
      final t = await db.getTicketById(ticketId) ?? await db.getTicketByBarcode(ticketId);
      if (t == null) throw Exception('Ticket not found: $ticketId');
      source = [t];
    } else {
      source = lines;
    }
    // BOTH: replicate each line for both draws
    if(drawChoice == 'BOTH'){
      int added = 0;
      for(final l in source){
        final numbers = (l['numbers'] as String).split(',').map((e)=> e.trim()).where((e)=> e.isNotEmpty).toList();
        final betType = l['betType'] as String;
        final amountPerDraw = (l['amount'] as num).toDouble();
        await addBothToCart(
          gameId: l['gameId'] as String,
          gameName: l['gameName'] as String,
          numbers: numbers,
          betType: betType,
          amountPerDraw: amountPerDraw,
          isQuickPick: (l['isQuickPick'] ?? 0) == 1,
        );
        added += 2;
      }
      return added;
    }
    // MIDDAY or EVENING — always a fresh target period, never the source ticket's closed period
    if(drawChoice == 'MIDDAY' || drawChoice == 'EVENING' || drawChoice == 'MORNING'){
      final targetPeriod = await _resolveNextSellablePeriod(drawChoice);
      final periodId = targetPeriod['id'] as String;
      final periodDrawType = _normalizeDrawType(targetPeriod['drawType'] as String?);
      await _validatePeriodOpen(periodId);
      int added = 0;
      for(final l in source){
        final numbers = (l['numbers'] as String).split(',').map((e)=> e.trim()).where((e)=> e.isNotEmpty).toList();
        final betType = l['betType'] as String;
        final amount = (l['amount'] as num).toDouble();
        _validateCartItem(gameId: l['gameId'] as String, numbers: numbers, betType: betType, amount: amount);
        await _enforcePerPeriodNumberLimit(
          periodId: periodId,
          gameId: l['gameId'] as String,
          numbers: numbers,
          betType: betType,
          amount: amount,
        );
        final meta = await _drawMetaForPeriod(l['gameId'] as String, targetPeriod);
        final item = CartItem(
          id: const Uuid().v4(),
          gameId: l['gameId'] as String,
          gameName: l['gameName'] as String,
          drawId: meta.$1,
          drawName: meta.$2,
          periodId: periodId,
          drawType: periodDrawType,
          numbers: numbers,
          betType: betType,
          amount: amount,
          isQuickPick: (l['isQuickPick'] ?? 0) == 1,
        );
        _cart.add(item);
        added++;
      }
      notifyListeners();
      return added;
    }
    // AUTO: keep the same draw type as the source ticket, but move it to the next sellable period
    int added = 0;
    for (final l in source) {
      final numbersRaw = (l['numbers'] as String).split(',').map((e)=> e.trim()).where((e)=> e.isNotEmpty).toList();
      String inferred = _normalizeDrawType(l['drawType'] as String?);
      if (inferred != 'MIDDAY' && inferred != 'EVENING') {
        inferred = _drawTypeFromPeriodId(l['periodId'] as String?);
      }
      if (inferred != 'MIDDAY' && inferred != 'EVENING') {
        final name = (l['drawName'] as String?) ?? '';
        if (name.contains('Evening') || name.contains('مسائ')) inferred = 'EVENING';
        else if (name.contains('Midday') || name.contains('Morning') || name.contains('صباح')) inferred = 'MIDDAY';
      }
      if (inferred != 'MIDDAY' && inferred != 'EVENING') {
        inferred = 'MIDDAY';
      }
      final target = await _resolveNextSellablePeriod(inferred);
      final periodId = target['id'] as String;
      final drawType = _normalizeDrawType(target['drawType'] as String?);
      final meta = await _drawMetaForPeriod(l['gameId'] as String, target);
      _validateCartItem(gameId: l['gameId'], numbers: numbersRaw, betType: l['betType'], amount: (l['amount'] as num).toDouble());
      await _validatePeriodOpen(periodId);
      await _enforcePerPeriodNumberLimit(
        periodId: periodId,
        gameId: l['gameId'] as String,
        numbers: numbersRaw,
        betType: l['betType'] as String,
        amount: (l['amount'] as num).toDouble(),
      );
      final item = CartItem(
        id: const Uuid().v4(),
        gameId: l['gameId'],
        gameName: l['gameName'],
        drawId: meta.$1,
        drawName: meta.$2,
        periodId: periodId,
        drawType: drawType,
        numbers: numbersRaw,
        betType: l['betType'],
        amount: (l['amount'] as num).toDouble(),
        isQuickPick: (l['isQuickPick'] ?? 0) == 1,
      );
      _cart.add(item);
      added++;
    }
    notifyListeners();
    return added;
  }

  /// Move every cart line to the next sellable Midday or Evening period.
  Future<void> remapCartToDrawType(String drawType) async {
    final normalized = _normalizeDrawType(drawType);
    if (normalized != 'MIDDAY' && normalized != 'EVENING') return;
    if (_cart.isEmpty) return;
    final target = await _resolveNextSellablePeriod(normalized);
    final periodId = target['id'] as String;
    await _validatePeriodOpen(periodId);
    final old = List<CartItem>.from(_cart);
    _cart.clear();
    try {
      for (final e in old) {
        await _enforcePerPeriodNumberLimit(
          periodId: periodId,
          gameId: e.gameId,
          numbers: e.numbers,
          betType: e.betType,
          amount: e.amount,
        );
        final meta = await _drawMetaForPeriod(e.gameId, target);
        _cart.add(CartItem(
          id: e.id,
          gameId: e.gameId,
          gameName: e.gameName,
          drawId: meta.$1,
          drawName: meta.$2,
          periodId: periodId,
          drawType: normalized,
          numbers: e.numbers,
          betType: e.betType,
          amount: e.amount,
          isQuickPick: e.isQuickPick,
        ));
      }
    } catch (err) {
      _cart
        ..clear()
        ..addAll(old);
      rethrow;
    }
    notifyListeners();
  }

  // Cash computed
  double _openingCash = 0;
  double get openingCash => _openingCash;

  Future<void> loadOpeningCash() async {
    if (_currentUser == null) return;
    final sess = await db.getOpenCashSession(_currentUser!['id']);
    if (sess != null) {
      _openingCash = (sess['openingAmount'] as num).toDouble();
    } else {
      _openingCash = 0;
    }
    notifyListeners();
  }

  Future<void> openCashSession(double amount) async {
    if (_currentUser == null) return;
    final existing = await db.getOpenCashSession(_currentUser!['id']);
    if (existing != null) return;
    final id = const Uuid().v4();
    await db.insertCashSession({
      'id': id,
      'operatorId': _currentUser!['id'],
      'openingAmount': amount,
      'closingAmount': null,
      'openedAt': DateTime.now().millisecondsSinceEpoch,
      'closedAt': null,
      'status': 'open',
    });
    await db.insertCashLedger({
      'id': const Uuid().v4(),
      'type': 'opening',
      'amount': amount,
      'direction': 'in',
      'description': 'Opening cash',
      'operatorId': _currentUser!['id'],
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'ticketId': null,
    });
    _openingCash = amount;
    notifyListeners();
  }

  Future<double> closeCashSession() async {
    if (_currentUser == null) return 0;
    final sess = await db.getOpenCashSession(_currentUser!['id']);
    if (sess == null) return 0;
    final cashNow = await computeCashBalance();
    await db.closeCashSession(sess['id'], cashNow, DateTime.now().millisecondsSinceEpoch);
    _openingCash = 0;
    notifyListeners();
    return cashNow;
  }

  Future<double> computeCashBalance({String? operatorId}) async {
    final op = operatorId ?? _currentUser?['id'] as String?;
    final inSum = await db.sumCash('in', operatorId: op);
    final outSum = await db.sumCash('out', operatorId: op);
    return inSum - outSum;
  }

  Future<double> computeGeneralBalance({String? operatorId}) async {
    final op = operatorId ?? _currentUser?['id'] as String?;
    final rows = op != null ? await db.getBalanceMovementsByOperator(op) : await db.getBalanceMovements();
    if (op != null && rows.isEmpty) {}
    double bal = 0;
    for (final r in rows) {
      final amt = (r['amount'] as num).toDouble();
      if (r['direction'] == 'credit' || r['direction'] == 'in') {
        bal += amt;
      } else {
        bal -= amt;
      }
    }
    if (op != null && rows.isEmpty) {
      final global = await db.getBalanceMovements();
      double gbal = 0;
      for (final r in global) {
        if (r['operatorId'] != op) continue;
        final amt = (r['amount'] as num).toDouble();
        if (r['direction'] == 'credit' || r['direction'] == 'in') gbal += amt; else gbal -= amt;
      }
      return gbal;
    }
    return bal;
  }

  Future<double> computeCashBalanceGlobal() async {
    final inSum = await db.sumCash('in');
    final outSum = await db.sumCash('out');
    return inSum - outSum;
  }

  Future<double> computeGeneralBalanceGlobal() async {
    final rows = await db.getBalanceMovements();
    double bal = 0;
    for (final r in rows) {
      final amt = (r['amount'] as num).toDouble();
      if (r['direction'] == 'credit' || r['direction'] == 'in') bal += amt; else bal -= amt;
    }
    return bal;
  }

  void _ensureNotExpired() {
    if (isSessionExpired) throw Exception('Session expired — please login again');
  }

  bool get isAdmin => _currentUser?['role'] == 'admin';

  // Legacy single ticket creation — kept for backward compat but SALE path uses cart
  Future<Map<String, dynamic>> createTicket({
    required String gameId,
    required String gameName,
    String? drawId,
    String? drawName,
    required List<String> numbers,
    required String betType,
    required double amount,
    required bool isQuickPick,
  }) async {
    // Redirect to cart+commit for single item if someone still calls it directly
    // But keep old behavior for old screens if needed: immediate insert as single-line ticket
    if (_currentUser == null) throw Exception('Not logged in');
    _ensureNotExpired();
    if (drawId != null) {
      final draw = await db.getDrawById(drawId);
      if (draw != null) {
        if (draw['status'] == 'closed') throw Exception('Draw is closed — sales blocked');
        final drawTime = draw['drawTime'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now > drawTime - 5 * 60 * 1000 && now < drawTime + 60 * 60 * 1000) {
          final win = draw['winningNumbers'] as String?;
          if (win == null || win.isEmpty) {
            if (now >= drawTime - 5 * 60 * 1000) throw Exception('Sales closed — draw cutoff (5 min before)');
          }
        }
        for (final d in numbers) {
          if (!RegExp(r'^[0-9]$').hasMatch(d)) throw Exception('Digits must be 0-9');
        }
        if (gameId == 'g_numbers') {
          if (numbers.length != 3 && numbers.length != 4) throw Exception('Numbers requires 3 or 4 digits');
        } else if (gameId == 'g_winz') {
          if (numbers.length != 4) throw Exception('Win 4 requires exactly 4 digits');
        }
        final btNorm = _normBet(betType);
        final allSame = numbers.isNotEmpty && numbers.toSet().length == 1;
        final isBoxNorm = btNorm == 'box';
        if (allSame && (isBoxNorm || _isStraightBoxBet(btNorm) || _isComboBet(btNorm))) {
          throw Exception('الأرقام المتطابقة مثل ${numbers.join()} مسموحة فقط في Straight — غير مسموحة في Box / ST/BOX / Combo');
        }
        if (_isComboBet(btNorm)) {
          final combos = _comboCount(numbers);
          if (combos <= 1) throw Exception('Combo not valid for repeating digits like ${numbers.join()}');
          if (amount < 0.5 - 1e-9) throw Exception('Combo min \$0.50');
          if (amount > combos * 10 + 1e-9) throw Exception('Combo max \$${(combos * 10).toStringAsFixed(2)}');
          if ((amount * 100).round() % 50 != 0) {
            throw Exception('Amount must be \$0.50 steps — e.g. \$0.50, \$1.00, \$1.50');
          }
        } else if (_isStraightBoxBet(btNorm)) {
          if (amount < 0.5 - 1e-9) throw Exception('Straight/Box (All) min \$0.50');
          final maxSB = numbers.length == 3 ? 50 : 25;
          if (amount > maxSB + 1e-9) throw Exception('Amount \$0.50 - \$$maxSB for Straight/Box');
          if ((amount * 100).round() % 50 != 0) throw Exception('Amount must be \$0.50 steps');
        } else if (isBoxNorm) {
          if (amount < 0.5 || amount > 50) throw Exception('Amount \$0.50 - \$50.00 for Box');
          if ((amount * 100).round() % 50 != 0) throw Exception('Amount must be \$0.50 steps');
        } else {
          final maxStraight = numbers.length == 3 ? 100.0 : 10.0;
          if (amount < 0.5 || amount > maxStraight) throw Exception('Amount \$0.50 - \$$maxStraight for Straight');
          if ((amount * 100).round() % 50 != 0) throw Exception('Amount must be \$0.50 steps');
        }
      }
    }
    final id = await db.nextTicketId();
    final serial = await db.nextSerialNumber();
    final total = amount;
    final barcode = id;
    final now = DateTime.now().millisecondsSinceEpoch;
    final ticket = {
      'id': id,
      'serialNumber': serial,
      'gameId': gameId,
      'gameName': gameName,
      'drawId': drawId,
      'drawName': drawName,
      'numbers': numbers.join(','),
      'betType': betType,
      'amount': amount,
      'total': total,
      'operatorId': _currentUser!['id'],
      'operatorName': _currentUser!['username'],
      'createdAt': now,
      'status': 'active',
      'barcode': barcode,
      'prizeAmount': null,
      'paidAt': null,
      'paidBy': null,
      'isQuickPick': isQuickPick ? 1 : 0,
    };
    await db.insertTicket(ticket);
    // also insert line for consistency
    await db.insertTicketLine({
      'id': const Uuid().v4(),
      'ticketId': id,
      'gameId': gameId,
      'gameName': gameName,
      'drawId': drawId,
      'drawName': drawName,
      'numbers': numbers.join(','),
      'betType': betType,
      'amount': amount,
      'isQuickPick': isQuickPick ? 1 : 0,
    });
    final cashId = const Uuid().v4();
    await db.insertCashLedger({
      'id': cashId,
      'type': 'sale',
      'amount': total,
      'direction': 'in',
      'description': '$gameName - $betType - ${numbers.join(",")}',
      'operatorId': _currentUser!['id'],
      'createdAt': now,
      'ticketId': id,
    });
    await db.insertBalanceMovement({
      'id': const Uuid().v4(),
      'type': 'sale',
      'amount': total,
      'direction': 'credit',
      'description': 'Sale $id',
      'operatorId': _currentUser!['id'],
      'createdAt': now,
      'ticketId': id,
    });
    notifyListeners();
    return ticket;
  }

  Future<bool> payWinningTicket(String ticketId, double prize) async {
    if (_currentUser == null) return false;
    _ensureNotExpired();
    final t = await db.getTicketById(ticketId);
    if (t == null) return false;
    if (t['status'] == 'paid') return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.updateTicketStatus(ticketId, 'paid', prizeAmount: prize, paidAt: now, paidBy: _currentUser!['username']);
    await db.insertCashLedger({
      'id': const Uuid().v4(),
      'type': 'payout',
      'amount': prize,
      'direction': 'out',
      'description': 'Prize payout for $ticketId',
      'operatorId': _currentUser!['id'],
      'createdAt': now,
      'ticketId': ticketId,
    });
    await db.insertBalanceMovement({
      'id': const Uuid().v4(),
      'type': 'payout',
      'amount': prize,
      'direction': 'debit',
      'description': 'Payout $ticketId',
      'operatorId': _currentUser!['id'],
      'createdAt': now,
      'ticketId': ticketId,
    });
    notifyListeners();
    return true;
  }

  /// Cancel whole ticket (all remaining active plays) — refunds total of active lines
  Future<double> cancelWholeTicket(String ticketId) async {
    if (_currentUser == null) throw Exception('Not logged in');
    _ensureNotExpired();
    final ticket = await db.getTicketById(ticketId);
    if (ticket == null) throw Exception('Ticket not found');
    if (ticket['status'] == 'paid') throw Exception('Already paid');
    if (ticket['status'] == 'cancelled') throw Exception('Already cancelled');
    if (ticket['status'] == 'winning') throw Exception('Winning ticket cannot be cancelled');
    final lines = await db.getTicketLines(ticketId);
    final activeLines = lines.where((l) => (l['periodStatus'] as String?) != 'cancelled' && (l['winningStatus'] as String?) != 'void').toList();
    if (activeLines.isEmpty) throw Exception('No active plays to cancel');
    // cutoff check on first active line (all same cutoff, but check each)
    for (final l in activeLines) {
      final periodId = l['periodId'] as String?;
      if (periodId != null) {
        final p = await db.getPeriodById(periodId);
        if (p != null && p['result'] != null && (p['result'] as String).isNotEmpty) {
          throw Exception('Cannot cancel — result already published for $periodId');
        }
        if (p != null) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now >= (p['salesCloseTime'] as int)) throw Exception('Sales closed for $periodId');
        }
      }
      final drawId = l['drawId'] as String?;
      if (drawId != null && (l['periodId'] == null)) {
        final d = await db.getDrawById(drawId);
        if (d != null && d['winningNumbers'] != null && (d['winningNumbers'] as String).toString().isNotEmpty) {
          throw Exception('Winning number already set');
        }
      }
    }
    double totalRefund = 0;
    for (final l in activeLines) {
      totalRefund += (l['amount'] as num).toDouble();
      await db.voidTicketLine(l['id'] as String);
    }
    await db.recalcTicketTotals(ticketId);
    // financial
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.insertCashLedger({
      'id': const Uuid().v4(),
      'type': 'cancel',
      'amount': totalRefund,
      'direction': 'out',
      'description': 'Cancel ticket $ticketId — ${activeLines.length} plays voided',
      'operatorId': _currentUser!['id'],
      'createdAt': nowMs,
      'ticketId': ticketId,
    });
    await db.insertBalanceMovement({
      'id': const Uuid().v4(),
      'type': 'cancel',
      'amount': totalRefund,
      'direction': 'debit',
      'description': 'Cancel ticket $ticketId',
      'operatorId': _currentUser!['id'],
      'createdAt': nowMs,
      'ticketId': ticketId,
    });
    notifyListeners();
    return totalRefund;
  }

  /// Cancel a single play (line) inside an invoice before draw cutoff.
  /// Returns refund amount. Throws if not allowed (already closed / winning etc).
  Future<double> cancelTicketLine({required String ticketId, required String lineId}) async {
    if (_currentUser == null) throw Exception('Not logged in');
    _ensureNotExpired();
    final ticket = await db.getTicketById(ticketId);
    if (ticket == null) throw Exception('Ticket not found');
    if (ticket['status'] == 'paid') throw Exception('Ticket already paid — cannot void');
    if (ticket['status'] == 'cancelled') throw Exception('Ticket already cancelled');
    // winning tickets cannot be partially voided (already decided)
    if (ticket['status'] == 'winning') throw Exception('Winning ticket — cannot void lines after result');

    final line = await db.getTicketLineById(lineId);
    if (line == null) throw Exception('Play not found');
    if ((line['ticketId'] as String) != ticketId) throw Exception('Line does not belong to ticket');
    if ((line['periodStatus'] as String?) == 'cancelled' || (line['winningStatus'] as String?) == 'void') {
      throw Exception('Play already cancelled');
    }

    // cutoff check: if period has result or sales closed, forbid void
    final periodId = line['periodId'] as String?;
    final drawId = line['drawId'] as String?;
    if (periodId != null) {
      final p = await db.getPeriodById(periodId);
      if (p != null) {
        if (p['result'] != null && (p['result'] as String).isNotEmpty) {
          throw Exception('Cannot void — result already published for $periodId');
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        final close = p['salesCloseTime'] as int;
        if (now >= close) throw Exception('Sales closed for $periodId — cannot void after cutoff');
        if (p['status'] == 'RESULT_PUBLISHED' || p['status'] == 'COMPLETED') {
          throw Exception('Draw $periodId already closed');
        }
      }
    }
    if (drawId != null) {
      final d = await db.getDrawById(drawId);
      if (d != null) {
        if (d['winningNumbers'] != null && (d['winningNumbers'] as String).toString().isNotEmpty) {
          throw Exception('Cannot void — winning number already set');
        }
        final dt = d['drawTime'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now >= dt - 5 * 60 * 1000) {
          // within 5 min cutoff and no result -> still sales closed
          // allow void only if period still OPEN, draw check is secondary
          if (periodId == null) throw Exception('Cutoff — cannot void');
        }
      }
    }

    final refund = (line['amount'] as num).toDouble();
    await db.voidTicketLine(lineId);
    await db.recalcTicketTotals(ticketId);

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // financial reversal: refund to customer (cash out)
    await db.insertCashLedger({
      'id': const Uuid().v4(),
      'type': 'cancel',
      'amount': refund,
      'direction': 'out',
      'description': 'Void play ${line['numbers']} ${line['betType']} — ticket $ticketId',
      'operatorId': _currentUser!['id'],
      'createdAt': nowMs,
      'ticketId': ticketId,
    });
    await db.insertBalanceMovement({
      'id': const Uuid().v4(),
      'type': 'cancel',
      'amount': refund,
      'direction': 'debit',
      'description': 'Void play ${line['numbers']} — ticket $ticketId',
      'operatorId': _currentUser!['id'],
      'createdAt': nowMs,
      'ticketId': ticketId,
    });

    // audit
    try {
      await db.insertAuditLog({
        'id': 'audit_${DateTime.now().microsecondsSinceEpoch}',
        'user': _currentUser!['username'],
        'action': 'LINE_VOIDED',
        'periodId': periodId,
        'oldValue': line['numbers'],
        'newValue': 'void ${line['id']} refund $refund',
        'timestamp': nowMs,
        'reason': 'Void line $lineId from ticket $ticketId',
      });
    } catch (_) {}

    notifyListeners();
    return refund;
  }

  double _mult(Map<String, String> cfg, String key, double def) {
    final v = cfg[key];
    if (v == null) return def;
    return double.tryParse(v) ?? def;
  }

  int _factorial(int n) => n <= 1 ? 1 : n * _factorial(n - 1);

  int _comboCount(List<String> digits) {
    final n = digits.length;
    final freq = <String, int>{};
    for (final d in digits) freq[d] = (freq[d] ?? 0) + 1;
    var denom = 1;
    for (final c in freq.values) denom *= _factorial(c);
    return _factorial(n) ~/ denom;
  }

  String _boxType3(List<String> digits) {
    final uniq = digits.toSet().length;
    if (uniq == 1) return 'triple';
    if (uniq == 2) return '3way';
    return '6way';
  }

  String _boxType4(List<String> digits) {
    final freq = <String, int>{};
    for (final d in digits) freq[d] = (freq[d] ?? 0) + 1;
    final vals = freq.values.toList()..sort();
    if (vals.length == 1) return '4ofKind';
    if (vals.length == 2) {
      if (vals.contains(3)) return '4way';
      return '6way';
    }
    if (vals.length == 3) return '12way';
    return '24way';
  }

  double _calculatePrize({
    required List<String> ticketDigits,
    required List<String> winningDigits,
    required String betType,
    required double amount,
    required Map<String, String> cfg,
  }) {
    if (ticketDigits.isEmpty || winningDigits.isEmpty) return 0;
    if (ticketDigits.length != winningDigits.length) return 0;
    final n = ticketDigits.length;
    final bt = betType.trim().toLowerCase().replaceAll('-', '/').replaceAll('_', '/').replaceAll(' ', '');

    final numbersStraight = _mult(cfg, 'numbers_straight', 500);
    final numbersBox3Way = _mult(cfg, 'numbers_box_3way', 160);
    final numbersBox6Way = _mult(cfg, 'numbers_box_6way', 80);
    final win4Straight = _mult(cfg, 'win4_straight', 5000);
    final win4Box4Way = _mult(cfg, 'win4_box_4way', 1200);
    final win4Box6Way = _mult(cfg, 'win4_box_6way', 800);
    final win4Box12Way = _mult(cfg, 'win4_box_12way', 400);
    final win4Box24Way = _mult(cfg, 'win4_box_24way', 200);
    final winzStd = _mult(cfg, 'winz_std_multiplier', 10);
    final winzJack = _mult(cfg, 'winz_jackpot_multiplier', 100);
    final winzInstant = _mult(cfg, 'winz_instant_multiplier', 5);

    final ticketStr = ticketDigits.join();
    final winStr = winningDigits.join();
    final isExact = ticketStr == winStr;
    final sortedTicket = List<String>.from(ticketDigits)..sort();
    final sortedWin = List<String>.from(winningDigits)..sort();
    final isSortedEqual = sortedTicket.join() == sortedWin.join();

    if (bt == 'straight') {
      if (!isExact) return 0;
      if (n == 3) return amount * numbersStraight;
      if (n == 4) return amount * win4Straight;
      return amount * (n <= 3 ? numbersStraight : win4Straight);
    }
    if (bt == 'box') {
      if (!isSortedEqual) return 0;
      if (n == 3) {
        final t = _boxType3(ticketDigits);
        if (t == 'triple') return 0;
        if (t == '3way') return amount * numbersBox3Way;
        return amount * numbersBox6Way;
      }
      if (n == 4) {
        final t = _boxType4(ticketDigits);
        if (t == '4ofKind') return 0;
        if (t == '4way') return amount * win4Box4Way;
        if (t == '6way') return amount * win4Box6Way;
        if (t == '12way') return amount * win4Box12Way;
        return amount * win4Box24Way;
      }
      return amount * numbersBox3Way;
    }
    // Combo / Fifty Combo — price = combos × wager, prize = wager × Straight (   Fifty Combo)
    // wager = amount/combos (e.g. 6-way $3 => $0.50 per combo => prize $250, $6 => $1 => $500)
    if (bt.contains('combo')) {
      if (!isSortedEqual) return 0;
      final combos = _comboCount(ticketDigits);
      if (combos <= 1) return 0;
      final wagerPerCombo = amount / combos;
      if (n == 3) return wagerPerCombo * numbersStraight;
      if (n == 4) return wagerPerCombo * win4Straight;
      return wagerPerCombo * numbersStraight;
    }
    // Straight/Box and All —    (  Straight   Box) — also handles ST/BOX (st/box)
    if (bt == 'straight/box' || bt == 'straightbox' || bt == 'str/box' || bt == 'strbox' || bt == 'st/box' || bt == 'stbox' || bt == 'all' || bt == 'all/box' || bt == 'all/straight' || (bt.contains('straight') && bt.contains('box'))) {
      if (n == 3) {
        final t = _boxType3(ticketDigits);
        if (t == 'triple') return isExact ? amount * numbersStraight * 0.5 : 0;
        final boxPrizePerDollar = t == '3way' ? numbersBox3Way : numbersBox6Way;
        if (isExact) return amount * 0.5 * numbersStraight + amount * 0.5 * boxPrizePerDollar;
        if (isSortedEqual) return amount * 0.5 * boxPrizePerDollar;
        return 0;
      }
      if (n == 4) {
        final t = _boxType4(ticketDigits);
        if (t == '4ofKind') return isExact ? amount * win4Straight * 0.5 : 0;
        double boxPerDollar;
        if (t == '4way') boxPerDollar = win4Box4Way;
        else if (t == '6way') boxPerDollar = win4Box6Way;
        else if (t == '12way') boxPerDollar = win4Box12Way;
        else boxPerDollar = win4Box24Way;
        if (isExact) return amount * 0.5 * win4Straight + amount * 0.5 * boxPerDollar;
        if (isSortedEqual) return amount * 0.5 * boxPerDollar;
        return 0;
      }
    }
    if (bt == 'frontpair' || bt == 'front/pair' || bt == 'pairfront') {
      if (n != 3) return 0;
      if (ticketDigits[0] == winningDigits[0] && ticketDigits[1] == winningDigits[1]) {
        final perDollar = _mult(cfg, 'numbers_front_pair', 50);
        return amount * perDollar;
      }
      return 0;
    }
    if (bt == 'backpair' || bt == 'back/pair' || bt == 'pairback') {
      if (n != 3) return 0;
      if (ticketDigits[1] == winningDigits[1] && ticketDigits[2] == winningDigits[2]) {
        final perDollar = _mult(cfg, 'numbers_back_pair', 50);
        return amount * perDollar;
      }
      return 0;
    }
    if (bt == 'winz/std' || bt == 'winzstd') return isExact ? amount * winzStd : 0;
    if (bt == 'winz/jackpot' || bt == 'winzjackpot') return isExact ? amount * winzJack : 0;
    if (bt == 'winz/instant' || bt == 'winzinstant') return isExact ? amount * winzInstant : 0;
    if (n == 3) return isExact ? amount * numbersStraight : 0;
    if (n == 4) return isExact ? amount * win4Straight : 0;
    return isExact ? amount * numbersStraight : 0;
  }

  // Multi-line aware validation — supports both legacy draws and new period-based results
  // Supports barcode, id, serialNumber — also cleans scanned QR noise
  Future<Map<String, dynamic>> validateTicket(String code) async {
    code = code.trim().replaceAll(RegExp(r'[\r\n]'), '').trim();
    // Extract numeric ticket id if QR contains extra text
    if(code.contains(' ') || code.contains(':') || code.contains('|')){
      final parts = code.split(RegExp(r'[^A-Za-z0-9]+')).where((p)=> p.isNotEmpty).toList();
      final numeric = parts.where((p)=> RegExp(r'^\d{4,10}$').hasMatch(p)).toList();
      if(numeric.isNotEmpty) code = numeric.last;
      else if(parts.isNotEmpty) code = parts.last;
    }
    final t = await db.getTicketByBarcode(code);
    if (t == null) return {'found': false};
    if (t['status'] == 'cancelled') {
      return {'found': true, 'ticket': t, 'isWinning': false, 'prize': 0, 'cancelled': true};
    }
    String _toDigits(String raw) => raw.replaceAll(',', '').replaceAll(' ', '');
    Future<String?> _resolveWinning(List<String> Function(String) digitsFromWinStr, {String? periodId, String? drawId, int? nDigits}) async {
      if (periodId != null) {
        final p = await db.getPeriodById(periodId);
        if (p != null) {
          // Dual winners: prefer result3/result4 based on length
          if (nDigits == 3) {
            final r3 = p['result3'] as String?;
            if (r3 != null && r3.trim().isNotEmpty) return r3;
          } else if (nDigits == 4) {
            final r4 = p['result4'] as String?;
            if (r4 != null && r4.trim().isNotEmpty) return r4;
          }
          final res = p['result'] as String?;
          if (res != null && res.trim().isNotEmpty) {
            // fallback legacy: only use if length matches
            final digits = res.replaceAll(',', '').trim();
            if (nDigits == null || digits.length == nDigits) return res;
            // if legacy result length doesn't match, don't return (treat as pending for other length)
            if (nDigits != null && digits.length != nDigits) {
              // try to continue to draw fallback, but don't return mismatched legacy
            } else {
              return res;
            }
          }
          // fall through to draw if period has no result for this length yet
        }
      }
      if (drawId != null) {
        final draw = await db.getDrawById(drawId);
        final win = draw?['winningNumbers'] as String?;
        if (win != null && win.trim().isNotEmpty) {
          final digits = win.replaceAll(',', '').trim();
          if (nDigits == null || digits.length == nDigits) return win;
        }
      }
      return null;
    }
    // Try multi-line first
    final lines = await db.getTicketLines(t['id']);
    if (lines.isNotEmpty) {
      final configs = await db.getAppConfig();
      final cfg = {for (var c in configs) c['key'] as String: c['value'] as String};
      double totalPrize = 0;
      bool hasPending = false;
      final lineDetails = <Map<String,dynamic>>[];
      for (final line in lines) {
        final ticketDigits = (line['numbers'] as String).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        final periodId = line['periodId'] as String?;
        final drawId = line['drawId'] as String?;
        final winStr = await _resolveWinning((s)=> s.split(''), periodId: periodId, drawId: drawId, nDigits: ticketDigits.length);
        if (winStr == null) {
          // Determine drawStatus for pending info
          String statusInfo = 'pending';
          if (periodId != null) {
            final p = await db.getPeriodById(periodId);
            if (p != null) statusInfo = p['status'] as String;
          } else if (drawId != null) {
            final d = await db.getDrawById(drawId);
            if (d != null) statusInfo = d['status'] as String;
          }
          hasPending = true; lineDetails.add({'line': line, 'pending': true, 'drawStatus': statusInfo}); continue;
        }
        // ticketDigits already computed above
        // winningDigits: winStr may be "472" or "4,7,2" — handle both
        final winningDigits = _toDigits(winStr).split('').where((e)=> e.isNotEmpty).toList();
        if (winningDigits.isEmpty) { hasPending = true; lineDetails.add({'line': line, 'pending': true}); continue; }
        final amount = (line['amount'] as num).toDouble();
        final betType = (line['betType'] as String?) ?? 'Straight';
        final prize = _calculatePrize(ticketDigits: ticketDigits, winningDigits: winningDigits, betType: betType, amount: amount, cfg: cfg);
        if (prize > 0) totalPrize += prize;
        lineDetails.add({'line': line, 'prize': prize, 'isWinning': prize>0});
      }
      if (hasPending && totalPrize==0) {
        // if at least one line pending and no win yet, treat as pending
        // but if any line already winning, we still report win (partial)
      }
      final isWinning = totalPrize > 0;
      if (isWinning) {
        if (t['status'] == 'paid') {
          return {'found': true, 'ticket': t, 'lines': lines, 'lineDetails': lineDetails, 'isWinning': true, 'prize': (t['prizeAmount'] as num?)?.toDouble() ?? totalPrize, 'alreadyPaid': true, 'totalPrize': totalPrize};
        }
        if (t['status'] == 'active' || t['status'] == 'losing') {
          await db.updateTicketStatus(t['id'] as String, 'winning', prizeAmount: totalPrize);
          t['status'] = 'winning';
          t['prizeAmount'] = totalPrize;
        } else if (t['status'] == 'winning' && t['prizeAmount'] == null) {
          await db.updateTicketStatus(t['id'] as String, 'winning', prizeAmount: totalPrize);
          t['prizeAmount'] = totalPrize;
        } else if (t['status'] == 'winning' && (t['prizeAmount'] as num?)?.toDouble() != totalPrize) {
          await db.updateTicketStatus(t['id'] as String, 'winning', prizeAmount: totalPrize);
          t['prizeAmount'] = totalPrize;
        }
        final pendingFlag = hasPending ? true : false;
        return {'found': true, 'ticket': t, 'lines': lines, 'lineDetails': lineDetails, 'isWinning': true, 'prize': totalPrize, 'alreadyPaid': false, 'pending': pendingFlag, 'totalPrize': totalPrize};
      } else {
        if (hasPending) {
          return {'found': true, 'ticket': t, 'lines': lines, 'lineDetails': lineDetails, 'isWinning': false, 'prize': 0, 'pending': true, 'totalPrize': 0};
        }
        if (t['status'] == 'winning') {
          await db.updateTicketStatus(t['id'] as String, 'losing', prizeAmount: 0);
          t['status'] = 'losing';
          t['prizeAmount'] = 0;
        } else if (t['status'] == 'active') {
          await db.updateTicketStatus(t['id'] as String, 'losing');
          t['status'] = 'losing';
        }
        return {'found': true, 'ticket': t, 'lines': lines, 'lineDetails': lineDetails, 'isWinning': false, 'prize': 0, 'totalPrize': 0};
      }
    }

    // Legacy single-line ticket
    final drawId = t['drawId'] as String?;
    if (drawId == null) {
      return {'found': true, 'ticket': t, 'isWinning': false, 'prize': 0, 'pending': true, 'reason': 'No draw assigned'};
    }
    final draw = await db.getDrawById(drawId);
    if (draw == null) {
      return {'found': true, 'ticket': t, 'isWinning': false, 'prize': 0, 'pending': true, 'reason': 'Draw not found'};
    }
    final winStr = draw['winningNumbers'] as String?;
    if (winStr == null || winStr.trim().isEmpty) {
      return {'found': true, 'ticket': t, 'isWinning': false, 'prize': 0, 'pending': true, 'drawStatus': draw['status']};
    }
    final ticketDigits = (t['numbers'] as String).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final winningDigits = winStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final amount = (t['amount'] as num).toDouble();
    final betType = (t['betType'] as String?) ?? 'Straight';
    final configs = await db.getAppConfig();
    final cfg = {for (var c in configs) c['key'] as String: c['value'] as String};
    final prize = _calculatePrize(ticketDigits: ticketDigits, winningDigits: winningDigits, betType: betType, amount: amount, cfg: cfg);
    final isWinning = prize > 0;
    if (isWinning) {
      if (t['status'] == 'paid') {
        return {'found': true, 'ticket': t, 'isWinning': true, 'prize': (t['prizeAmount'] as num?)?.toDouble() ?? prize, 'alreadyPaid': true};
      }
      if (t['status'] == 'active' || t['status'] == 'losing') {
        await db.updateTicketStatus(t['id'] as String, 'winning', prizeAmount: prize);
        t['status'] = 'winning';
        t['prizeAmount'] = prize;
      } else if (t['status'] == 'winning' && t['prizeAmount'] == null) {
        await db.updateTicketStatus(t['id'] as String, 'winning', prizeAmount: prize);
        t['prizeAmount'] = prize;
      }
      return {'found': true, 'ticket': t, 'isWinning': true, 'prize': prize, 'alreadyPaid': false};
    } else {
      if (t['status'] == 'winning') {
        await db.updateTicketStatus(t['id'] as String, 'losing', prizeAmount: 0);
        t['status'] = 'losing';
        t['prizeAmount'] = 0;
      } else if (t['status'] == 'active') {
        await db.updateTicketStatus(t['id'] as String, 'losing');
        t['status'] = 'losing';
      }
      return {'found': true, 'ticket': t, 'isWinning': false, 'prize': 0};
    }
  }

  Future<Map<String, dynamic>> processPeriodResult({
    required String periodId,
    required List<String> winningNumbers,
    bool autoPay = false,
    String resultSource = 'manual',
    bool isCorrection = false,
  }) async {
    if (_currentUser == null) throw Exception('Not logged in');
    _ensureNotExpired();
    if (!isAdmin) throw Exception('Only admin can set winning numbers');
    final winStr = winningNumbers.join('');
    if (winStr.isEmpty) throw Exception('winningNumbers empty');
    for (final d in winningNumbers) {
      if (!RegExp(r'^[0-9]$').hasMatch(d)) throw Exception('Winning digits must be 0-9');
    }
    if (winStr.length < 3 || winStr.length > 4) throw Exception('Result must be 3 or 4 digits');
    final pBefore = await db.getPeriodById(periodId);
    if (pBefore == null) throw Exception('Period not found: $periodId');
    final is3 = winStr.length == 3;
    final is4 = winStr.length == 4;
    if (is3 && pBefore['result3'] != null && (pBefore['result3'] as String).isNotEmpty && !isCorrection) {
      throw Exception('Result 3-digit already published for $periodId: ${pBefore['result3']} — use correction');
    }
    if (is4 && pBefore['result4'] != null && (pBefore['result4'] as String).isNotEmpty && !isCorrection) {
      throw Exception('Result 4-digit already published for $periodId: ${pBefore['result4']} — use correction');
    }
    // For dual, only reset lines matching this digit length? But for now reset all pending status for that length will be handled via validate.
    await db.resetPeriodTickets(periodId);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (is3) {
      await db.publishPeriodResult3(periodId, winStr, nowMs, _currentUser!['username'] as String, resultSource);
    } else if (is4) {
      await db.publishPeriodResult4(periodId, winStr, nowMs, _currentUser!['username'] as String, resultSource);
    } else {
      await db.publishPeriodResult(periodId, winStr, nowMs, _currentUser!['username'] as String, resultSource);
    }
    // Audit
    await db.insertAuditLog({
      'id': 'audit_${DateTime.now().microsecondsSinceEpoch}',
      'user': _currentUser!['username'],
      'action': isCorrection ? 'RESULT_CORRECTED' : 'RESULT_PUBLISHED',
      'periodId': periodId,
      'oldValue': is3 ? pBefore['result3']?.toString() : is4 ? pBefore['result4']?.toString() : pBefore['result']?.toString(),
      'newValue': winStr,
      'timestamp': nowMs,
      'reason': isCorrection ? 'Correction $periodId ($winStr)' : 'Publish $periodId ($winStr)',
    });
    // Auto winner evaluation for period lines
    final allLines = await db.getAllTicketLines();
    final periodLines = allLines.where((l) => l['periodId'] == periodId).toList();
    final ticketIds = periodLines.map((l) => l['ticketId'] as String).toSet();
    final tickets = await db.getTickets();
    int winningCount = 0, losingCount = 0;
    double totalPrize = 0, totalSales = 0;
    for (final l in periodLines) totalSales += (l['amount'] as num).toDouble();
    for (final tid in ticketIds) {
      final ticket = tickets.firstWhere((t) => t['id'] == tid, orElse: () => {});
      if (ticket.isEmpty || ticket['status'] == 'paid' || ticket['status'] == 'cancelled') continue;
      final res = await validateTicket(ticket['barcode'] ?? ticket['id'] as String);
      bool isWinForPeriod = false;
      double prizeForPeriod = 0;
      if (res['lineDetails'] != null) {
        for (final d in res['lineDetails'] as List) {
          final line = d['line'] as Map<String, dynamic>;
          if (line['periodId'] == periodId && (d['isWinning'] == true)) {
            isWinForPeriod = true;
            prizeForPeriod += (d['prize'] as num).toDouble();
          }
        }
        if (isWinForPeriod) {
          winningCount++;
          totalPrize += prizeForPeriod;
          if (autoPay && res['alreadyPaid'] != true) await payWinningTicket(tid, (res['prize'] as num).toDouble());
        } else if (res['pending'] != true) {
          final has = (res['lineDetails'] as List).any((d) => (d['line'] as Map)['periodId'] == periodId);
          if (has) losingCount++;
        }
      }
    }
    // Update status to COMPLETED after evaluation if not suspended etc
    final pAfter = await db.getPeriodById(periodId);
    if (pAfter != null && pAfter['status'] == 'RESULT_PUBLISHED') {
      await db.updatePeriodStatus(periodId, 'COMPLETED');
    }
    notifyListeners();
    return {
      'winningCount': winningCount,
      'losingCount': losingCount,
      'totalPrize': totalPrize,
      'totalSales': totalSales,
      'net': totalSales - totalPrize,
      'totalTickets': ticketIds.length,
    };
  }

  Future<Map<String, dynamic>> processDrawResult({
    required String drawId,
    required List<String> winningNumbers,
    bool autoPay = false,
  }) async {
    if (_currentUser == null) throw Exception('Not logged in');
    _ensureNotExpired();
    if (!isAdmin) throw Exception('Only admin can set winning numbers');
    final winStr = winningNumbers.map((e) => e.trim()).where((e) => e.isNotEmpty).join(',');
    if (winStr.isEmpty) throw Exception('winningNumbers empty');
    for (final d in winningNumbers) {
      if (!RegExp(r'^[0-9]$').hasMatch(d)) throw Exception('Winning digits must be 0-9');
    }
    await db.resetDrawTickets(drawId);
    await db.updateDrawResult(drawId, winStr);
    // Also sync to period if possible
    try {
      final draw = await db.getDrawById(drawId);
      if (draw != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch(draw['drawTime'] as int);
        final name = draw['name'] as String;
        String pType = name.contains('Evening') ? 'EVENING' : 'MIDDAY';
        if (name.toLowerCase().contains('evening')) pType = 'EVENING';
        else if (name.toLowerCase().contains('midday') || name.toLowerCase().contains('morning')) pType = 'MIDDAY';
        final pid = _periodIdForDate(dt, pType);
        final p = await db.getPeriodById(pid);
        if (p != null) {
          final plain = winningNumbers.join('');
          await db.resetPeriodTickets(pid);
          await db.publishPeriodResult(pid, plain, DateTime.now().millisecondsSinceEpoch, _currentUser!['username'] as String, 'manual');
        }
      }
    } catch (_) {}
    final tickets = await db.getTickets();
    // For multi-tickets, we need to evaluate if ticket has at least one line matching this draw
    // Simpler: iterate all tickets, but validate will check its lines
    final allLines = await db.getAllTicketLines();
    final ticketIdsForDraw = allLines.where((l)=> l['drawId']==drawId).map((l)=> l['ticketId'] as String).toSet();
    // Also include legacy tickets with drawId == drawId
    final legacyForDraw = tickets.where((t)=> t['drawId']==drawId && !ticketIdsForDraw.contains(t['id'])).map((t)=> t['id'] as String).toSet();
    final drawTicketIds = {...ticketIdsForDraw, ...legacyForDraw};
    final drawTickets = tickets.where((t)=> drawTicketIds.contains(t['id'])).toList();

    int winningCount = 0;
    int losingCount = 0;
    double totalPrize = 0;
    double totalSales = 0;
    // totalSales should sum line amounts for draw, not ticket total if ticket multi-draw
    for (final tid in drawTicketIds) {
      final lines = allLines.where((l)=> l['ticketId']==tid).toList();
      if (lines.isNotEmpty) {
        for (final l in lines.where((x)=> x['drawId']==drawId)) totalSales += (l['amount'] as num).toDouble();
      } else {
        final t = tickets.firstWhere((x)=> x['id']==tid);
        totalSales += (t['amount'] as num).toDouble();
      }
    }

    for (final ticket in drawTickets) {
      if (ticket['status'] == 'paid' || ticket['status'] == 'cancelled') continue;
      final res = await validateTicket(ticket['barcode'] ?? ticket['id'] as String);
      // For multi tickets, validate aggregates; we count ticket as winning if any line wins for this draw
      // Check lineDetails for this draw if multi
      bool isWinForThisDraw = false;
      double prizeForThisDraw = 0;
      if (res['lineDetails'] != null) {
        for (final d in res['lineDetails'] as List) {
          final line = d['line'] as Map<String,dynamic>;
          if (line['drawId'] == drawId && (d['isWinning']==true)) { isWinForThisDraw = true; prizeForThisDraw += (d['prize'] as num).toDouble(); }
        }
        // if pending for this draw, skip counting
        if (res['pending']==true && !isWinForThisDraw) {
          // need to know if lines for this draw are pending? if winStr present they wouldn't be pending
        }
        if (isWinForThisDraw) { winningCount++; totalPrize += prizeForThisDraw; if (autoPay && res['alreadyPaid'] != true) { await payWinningTicket(ticket['id'] as String, (res['prize'] as num).toDouble()); } }
        else if (res['pending'] != true) { // only count losing if not pending
          // check if ticket has at least one line for this draw that is not pending and not winning -> losing
          final hasLinesForDraw = (res['lineDetails'] as List).any((d)=> (d['line'] as Map)['drawId']==drawId);
          if (hasLinesForDraw) losingCount++;
        }
      } else {
        if (res['found'] == true && res['isWinning'] == true) {
          winningCount++;
          totalPrize += (res['prize'] as num).toDouble();
          if (autoPay && res['alreadyPaid'] != true) {
            await payWinningTicket(ticket['id'] as String, (res['prize'] as num).toDouble());
          }
        } else if (res['found'] == true && res['isWinning'] == false && res['pending'] != true) {
          losingCount++;
        }
      }
    }
    notifyListeners();
    return {
      'winningCount': winningCount,
      'losingCount': losingCount,
      'totalPrize': totalPrize,
      'totalSales': totalSales,
      'net': totalSales - totalPrize,
      'totalTickets': drawTickets.length,
    };
  }
}
