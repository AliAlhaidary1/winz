import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../data/database.dart';

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
    // تحديث تلقائي كل دقيقة لفتح/إغلاق الفترات حسب الوقت (00:00-14:15 / 00:00-22:20) بدون تدخل يدوي
    Future.delayed(const Duration(seconds: 5), () async {
      try { await db.seedDrawPeriods(); await db.refreshPeriodStatuses(); } catch (_) {}
    });
    // periodic refresh while app is alive
    Stream.periodic(const Duration(minutes: 1)).listen((_) async {
      try { await db.refreshPeriodStatuses(); await db.seedDrawPeriods(); } catch (_) {}
    });
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

  // ============ CART (السلة قبل SALE) ============
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
      norm == 'str/box' ||
      norm == 'strbox';

  String _periodIdForDate(DateTime date, String drawType) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d-${drawType.toUpperCase()}';
  }

  Future<void> _validatePeriodOpen(String periodId) async {
    // Normalize (fixes slash/case like 2026/08/31 middy)
    periodId = periodId.replaceAll('/', '-').trim().toUpperCase();
    // Ensure suffix is upper
    // Auto-heal: ensure period exists and statuses are fresh (fixes 1:55 AM SCHEDULED→OPEN)
    await db.seedDrawPeriods();
    await db.refreshPeriodStatuses();
    var p = await db.getPeriodById(periodId);
    if (p == null) {
      await db.ensurePeriodExists(periodId);
      p = await db.getPeriodById(periodId);
    }
    // Try case-insensitive fallback
    if (p == null) {
      p = await db.getPeriodById(periodId.toLowerCase());
    }
    if (p == null) {
      // Try to parse and re-ensure
      await db.ensurePeriodExists(periodId.toUpperCase());
      p = await db.getPeriodById(periodId.toUpperCase());
    }
    if (p == null) throw Exception('Period $periodId not found — schedule not generated');
    final now = DateTime.now().millisecondsSinceEpoch;
    final salesOpen = p['salesOpenTime'] as int;
    final salesClose = p['salesCloseTime'] as int;
    var status = p['status'] as String;
    // الإدارة التلقائية حسب وقت الإغلاق — حتى لو بقيت الحالة SCHEDULED في DB نعتبرها مفتوحة داخل النافذة
    if (now < salesOpen) {
      throw Exception('${p['drawType']} ${p['drawDate']} not yet open — opens ${DateTime.fromMillisecondsSinceEpoch(salesOpen)}');
    }
    if (now >= salesClose) {
      throw Exception('Sales closed for $periodId — cutoff ${DateTime.fromMillisecondsSinceEpoch(salesClose)}');
    }
    // داخل النافذة: أي حالة ما عدا OPEN نصلحها تلقائياً ونسمح
    if (status != 'OPEN') {
      // حاول تحديثها في الخلفية، لكن لا تمنع البيع حتى لو فشل التحديث
      try { await db.updatePeriodStatus(periodId, 'OPEN'); } catch (_) {}
      // لا نرمي خطأ إذا كنا داخل النافذة — نعتبرها OPEN
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
    if (isCombo) {
      final combos = _comboCount(numbers);
      if (combos <= 1) throw Exception('Combo not valid for repeating digits like ${numbers.join()} — need distinct permutations');
      // المبلغ المدخل هو الإجمالي المطلوب دفعه — يتوزع تلقائياً على عدد التركيبات
      // مثال: 123 (6 combos) + \$6.00 => \$1.00 لكل تركيبة، \$1.00 + \$1.00 => Prize = wagerPerCombo * multiplier
      if (amount < 0.5 - 1e-9) throw Exception('Combo min \$0.50');
      if (amount > combos * 10 + 1e-9) throw Exception('Combo max \$${(combos * 10).toStringAsFixed(2)} ($combos × \$10)');
      if ((amount * 100).round() % 50 != 0) {
        throw Exception('Amount must be \$0.50 steps — e.g. \$0.50, \$1.00, \$1.50');
      }
    } else if (isStrBox) {
      // Straight/Box (All) — النظام يقسم المبلغ تلقائياً نصفين (Straight + Box)
      // السماح حتى بـ $0.50 إجمالي => $0.25 لكل جانب، والإجمالي للاثنين (Both) = amountPerDraw × 2
      if (amount < 0.5 - 1e-9) throw Exception('Straight/Box (All) min \$0.50');
      if (amount > 10 + 1e-9) throw Exception('Amount \$0.50 - \$10.00 for Straight/Box (All)');
      if ((amount * 100).round() % 50 != 0) {
        throw Exception('Amount must be \$0.50 steps — e.g. \$0.50, \$1.00, \$1.50');
      }
    } else {
      if (amount < 0.5 || amount > 10) throw Exception('Amount \$0.50 - \$10.00');
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
    // Derive periodId from drawId if not provided
    String? resolvedPeriodId = periodId;
    String? resolvedDrawType = drawType;
    if (resolvedPeriodId == null && drawId != null) {
      // Try to infer periodId from draw name
      final draw = await db.getDrawById(drawId);
      if (draw != null) {
        final name = draw['name'] as String;
        String inferredPeriod = name.contains('Midday') || name.contains('Morning') ? 'MIDDAY' : name.contains('Evening') ? 'EVENING' : 'MIDDAY';
        resolvedDrawType = inferredPeriod;
        final dt = DateTime.fromMillisecondsSinceEpoch(draw['drawTime'] as int);
        resolvedPeriodId = _periodIdForDate(dt, inferredPeriod);
      }
    }
    // Validate period is open if available
    if (resolvedPeriodId != null) {
      await _validatePeriodOpen(resolvedPeriodId);
    }
    if (drawId != null) {
      final draw = await db.getDrawById(drawId);
      if (draw != null) {
        if (draw['status'] == 'closed') throw Exception('Draw is closed — sales blocked');
        final drawTime = draw['drawTime'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now >= drawTime - 5 * 60 * 1000) {
          final win = draw['winningNumbers'] as String?;
          if (win == null || win.toString().isEmpty) throw Exception('Sales closed — draw cutoff (5 min before)');
        }
      }
    }
    final item = CartItem(
      id: const Uuid().v4(),
      gameId: gameId,
      gameName: gameName,
      drawId: drawId,
      drawName: drawName,
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
  /// إذا كان الصباحي مغلق والمسائي مفتوح → يلعب المسائي اليوم + الصباحي غداً
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
    await db.seedDrawPeriods();
    await db.refreshPeriodStatuses();
    // احصل على أول فترتين مفتوحتين زمنياً (تلقائي حسب الوقت)
    final openPeriods = await db.getOpenPeriods();
    // فلترة حسب الوقت الفعلي (SCHEDULED داخل النافذة يُعتبر مفتوح)
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final filtered = openPeriods.where((p){
      if(p['status']=='OPEN') return true;
      if(p['status']=='SCHEDULED'){
        final o=p['salesOpenTime'] as int, c=p['salesCloseTime'] as int;
        return nowMs >= o && nowMs < c;
      }
      return false;
    }).toList()..sort((a,b)=> (a['drawTime'] as int).compareTo(b['drawTime'] as int));
    List<Map<String,dynamic>> targetPeriods;
    if(filtered.length >= 2){
      targetPeriods = filtered.take(2).toList();
    } else if(filtered.length == 1){
      // إذا فترة واحدة فقط مفتوحة، خذ التالية المجدولة
      final allPeriods = await db.getAllPeriods();
      allPeriods.sort((a,b)=> (a['drawTime'] as int).compareTo(b['drawTime'] as int));
      final nextScheduled = allPeriods.where((p)=> (p['drawTime'] as int) > nowMs).take(2).toList();
      targetPeriods = nextScheduled.length >=2 ? nextScheduled.take(2).toList() : filtered;
      if(targetPeriods.length <2) throw Exception('Both requires two upcoming draws — only ${filtered.length} open');
    } else {
      // لا يوجد مفتوح — حاول توليد
      final date = forDate ?? DateTime.now();
      final middayId = _periodIdForDate(date, 'MIDDAY');
      final eveningId = _periodIdForDate(date, 'EVENING');
      await db.ensurePeriodExists(middayId);
      await db.ensurePeriodExists(eveningId);
      throw Exception('No open draws now — try again after midnight');
    }
    final firstId = targetPeriods[0]['id'] as String;
    final secondId = targetPeriods[1]['id'] as String;
    await _validatePeriodOpen(firstId);
    await _validatePeriodOpen(secondId);
    // Resolve drawIds for each (for backward compat legacy draws)
    String? firstDrawId;
    String? secondDrawId;
    String? firstDrawName;
    String? secondDrawName;
    final draws = await db.getDrawsByGame(gameId);
    for (final d in draws) {
      final name = d['name'] as String;
      final dt = DateTime.fromMillisecondsSinceEpoch(d['drawTime'] as int);
      // Match by period id date+type
      for(final tp in targetPeriods){
        final tpDate = tp['drawDate'] as String;
        final tpType = tp['drawType'] as String;
        final dtStr = '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
        final isMatch = dtStr == tpDate && ((tpType=='MIDDAY' && (name.contains('Midday')||name.contains('Morning'))) || (tpType=='EVENING' && name.contains('Evening')));
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
    final id = 'T${DateTime.now().microsecondsSinceEpoch}${const Uuid().v4().substring(0, 4).toUpperCase()}';
    final serial = 'SN${const Uuid().v4().substring(0, 8).toUpperCase()}';
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
    final lines = await db.getTicketLines(ticketId);
    List<Map<String,dynamic>> source;
    if (lines.isEmpty) {
      final t = await db.getTicketById(ticketId);
      if (t == null) throw Exception('Ticket not found');
      source = [t];
    } else {
      source = lines;
    }
    int added = 0;
    for (final l in source) {
      final numbersRaw = (l['numbers'] as String).split(',').map((e)=> e.trim()).where((e)=> e.isNotEmpty).toList();
      // Try find a current open draw for its game if old draw closed
      String? drawId = l['drawId'] as String?;
      String? drawName = l['drawName'] as String?;
      if (drawId != null) {
        final draw = await db.getDrawById(drawId);
        if (draw == null || draw['status'] == 'closed') {
          // pick first open draw for that game
          final openDraws = await db.getDrawsByGame(l['gameId']);
          final open = openDraws.where((d)=> d['status']=='open').toList();
          if (open.isNotEmpty) {
            drawId = open.first['id'];
            drawName = open.first['name'];
          }
        }
      }
      final item = CartItem(
        id: const Uuid().v4(),
        gameId: l['gameId'],
        gameName: l['gameName'],
        drawId: drawId,
        drawName: drawName,
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
          if ((amount * 100).round() % 50 != 0) throw Exception('Amount must be \$0.50 steps');
        }
      }
    }
    final id = 'T${DateTime.now().microsecondsSinceEpoch}${const Uuid().v4().substring(0, 4).toUpperCase()}';
    final serial = 'SN${const Uuid().v4().substring(0, 8).toUpperCase()}';
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
    // Combo / Fifty Combo — price = combos × wager, prize = wager × Straight (يعمل على أساس Fifty Combo)
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
    // Straight/Box and All — يلعب الاثنتين معاً (نصف للـ Straight ونصف للـ Box)
    if (bt == 'straight/box' || bt == 'straightbox' || bt == 'str/box' || bt == 'strbox' || bt == 'all' || bt == 'all/box' || bt == 'all/straight' || (bt.contains('straight') && bt.contains('box'))) {
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
  Future<Map<String, dynamic>> validateTicket(String code) async {
    final t = await db.getTicketByBarcode(code);
    if (t == null) return {'found': false};
    if (t['status'] == 'cancelled') {
      return {'found': true, 'ticket': t, 'isWinning': false, 'prize': 0, 'cancelled': true};
    }
    String _toDigits(String raw) => raw.replaceAll(',', '').replaceAll(' ', '');
    Future<String?> _resolveWinning(List<String> Function(String) digitsFromWinStr, {String? periodId, String? drawId}) async {
      if (periodId != null) {
        final p = await db.getPeriodById(periodId);
        if (p != null) {
          final res = p['result'] as String?;
          if (res != null && res.trim().isNotEmpty) return res;
          // fall through to draw if period has no result yet
        }
      }
      if (drawId != null) {
        final draw = await db.getDrawById(drawId);
        final win = draw?['winningNumbers'] as String?;
        if (win != null && win.trim().isNotEmpty) return win;
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
        final periodId = line['periodId'] as String?;
        final drawId = line['drawId'] as String?;
        final winStr = await _resolveWinning((s)=> s.split(''), periodId: periodId, drawId: drawId);
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
        final ticketDigits = (line['numbers'] as String).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
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
    if (pBefore['result'] != null && (pBefore['result'] as String).isNotEmpty && !isCorrection) {
      throw Exception('Result already published for $periodId — use correction');
    }
    await db.resetPeriodTickets(periodId);
    await db.publishPeriodResult(periodId, winStr, DateTime.now().millisecondsSinceEpoch, _currentUser!['username'] as String, resultSource);
    // Audit
    await db.insertAuditLog({
      'id': 'audit_${DateTime.now().microsecondsSinceEpoch}',
      'user': _currentUser!['username'],
      'action': isCorrection ? 'RESULT_CORRECTED' : 'RESULT_PUBLISHED',
      'periodId': periodId,
      'oldValue': pBefore['result']?.toString(),
      'newValue': winStr,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'reason': isCorrection ? 'Correction $periodId' : 'Publish $periodId',
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
