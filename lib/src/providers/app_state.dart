import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../data/database.dart';

class AppState extends ChangeNotifier {
  final AppDatabase db;
  AppState(this.db);

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
    // fallback: if filtered returns empty but global exists and op null, already handled
    if (op != null && rows.isEmpty) {
      // check global as fallback for legacy data without operator filter? No — use filtered
    }
    double bal = 0;
    for (final r in rows) {
      final amt = (r['amount'] as num).toDouble();
      if (r['direction'] == 'credit' || r['direction'] == 'in') {
        bal += amt;
      } else {
        bal -= amt;
      }
    }
    // If per-operator and no rows, also compute global for display compatibility
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

  // Global variants for reports
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

  // Guards
  void _ensureNotExpired() {
    if (isSessionExpired) throw Exception('Session expired — please login again');
  }

  bool get isAdmin => _currentUser?['role'] == 'admin';

  // Ticket creation — with NY guards
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
    if (_currentUser == null) throw Exception('Not logged in');
    _ensureNotExpired();
    // Validate draw still open and not past cutoff
    if (drawId != null) {
      final draw = await db.getDrawById(drawId);
      if (draw != null) {
        if (draw['status'] == 'closed') throw Exception('Draw is closed — sales blocked');
        final drawTime = draw['drawTime'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        // NY cutoff: 5 minutes before draw
        if (now > drawTime - 5 * 60 * 1000 && now < drawTime + 60 * 60 * 1000) {
          // If within 5min before or after draw time and winningNumbers not set, block? Only block if past cutoff and not yet drawn
          final win = draw['winningNumbers'] as String?;
          if (win == null || win.isEmpty) {
            if (now >= drawTime - 5 * 60 * 1000) throw Exception('Sales closed — draw cutoff (5 min before)');
          }
        }
        // Validate numbers are 0-9
        for (final d in numbers) {
          if (!RegExp(r'^[0-9]$').hasMatch(d)) throw Exception('Digits must be 0-9');
        }
        // NY length rules
        if (gameId == 'g_numbers') {
          if (numbers.length != 3 && numbers.length != 4) throw Exception('Numbers requires 3 or 4 digits');
        } else if (gameId == 'g_winz') {
          if (numbers.length != 4) throw Exception('Win 4 requires exactly 4 digits');
        }
        // Combo cost validation
        final btNorm = betType.trim().toLowerCase().replaceAll('-', '/').replaceAll('_', '/').replaceAll(' ', '');
        if (btNorm == 'combo' || btNorm == 'combination') {
          final combos = _comboCount(numbers);
          if (combos <= 1) throw Exception('Combo not valid for repeating digits like ${numbers.join()}');
          // amount must be divisible to per-combo 0.50 or 1.00 — allow 0.50 steps
          final perCombo = amount / combos;
          if ((perCombo * 100).round() % 50 != 0) {
            throw Exception('Combo amount must be divisible by combos=$combos (per combo \$0.50 steps)');
          }
        }
      }
    }
    final id = 'T${DateTime.now().microsecondsSinceEpoch}${const Uuid().v4().substring(0, 4).toUpperCase()}';
    final serial = 'SN${const Uuid().v4().substring(0, 8).toUpperCase()}';
    final total = amount; // single play; multi-play handled by caller
    final barcode = id; // barcode = ticket id
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
    // financial: cash in, balance credit
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
    if (t['status'] == 'paid') return false; // idempotent guard
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

  // Helpers for prize calculation — NY Lottery الرسمي
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
    if (uniq == 1) return 'triple'; // 111 — لا يوجد Box صالح
    if (uniq == 2) return '3way'; // 112
    return '6way'; // 123
  }

  String _boxType4(List<String> digits) {
    final freq = <String, int>{};
    for (final d in digits) freq[d] = (freq[d] ?? 0) + 1;
    final vals = freq.values.toList()..sort();
    if (vals.length == 1) return '4ofKind'; // 1111
    if (vals.length == 2) {
      if (vals.contains(3)) return '4way'; // 1112
      return '6way'; // 1122 (2+2)
    }
    if (vals.length == 3) return '12way'; // 1123
    return '24way'; // 1234
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

    // NY الرسمي لكل $1 wager
    final numbersStraight = _mult(cfg, 'numbers_straight', 500); // Pick3 Straight $500 /$1
    final numbersBox3Way = _mult(cfg, 'numbers_box_3way', 160);
    final numbersBox6Way = _mult(cfg, 'numbers_box_6way', 80);
    final win4Straight = _mult(cfg, 'win4_straight', 5000);
    final win4Box4Way = _mult(cfg, 'win4_box_4way', 1200);
    final win4Box6Way = _mult(cfg, 'win4_box_6way', 800);
    final win4Box12Way = _mult(cfg, 'win4_box_12way', 400);
    final win4Box24Way = _mult(cfg, 'win4_box_24way', 200);
    // Winz legacy (يعامل مثل Win4 Straight)
    final winzStd = _mult(cfg, 'winz_std_multiplier', 10);
    final winzJack = _mult(cfg, 'winz_jackpot_multiplier', 100);
    final winzInstant = _mult(cfg, 'winz_instant_multiplier', 5);

    final ticketStr = ticketDigits.join();
    final winStr = winningDigits.join();
    final isExact = ticketStr == winStr;
    final sortedTicket = List<String>.from(ticketDigits)..sort();
    final sortedWin = List<String>.from(winningDigits)..sort();
    final isSortedEqual = sortedTicket.join() == sortedWin.join();

    // ---- Straight: يجب تطابق تام بالترتيب، لا يقبل التشقلب ----
    if (bt == 'straight') {
      if (!isExact) return 0;
      if (n == 3) return amount * numbersStraight;
      if (n == 4) return amount * win4Straight;
      // Winz بأطوال أخرى — نعتبره Straight
      return amount * (n <= 3 ? numbersStraight : win4Straight);
    }

    // ---- Box: يقبل أي ترتيب (تشقلب) بشرط نفس الأرقام، الربح حسب التكرار ----
    if (bt == 'box') {
      if (!isSortedEqual) return 0;
      if (n == 3) {
        final t = _boxType3(ticketDigits);
        if (t == 'triple') return 0; // 111 لا يربح Box
        if (t == '3way') return amount * numbersBox3Way; // $160/$1 — مثال 112 يفوز بـ 121,211
        return amount * numbersBox6Way; // $80/$1 — 123 يفوز بـ 321,213...
      }
      if (n == 4) {
        final t = _boxType4(ticketDigits);
        if (t == '4ofKind') return 0;
        if (t == '4way') return amount * win4Box4Way; // 1112
        if (t == '6way') return amount * win4Box6Way; // 1122
        if (t == '12way') return amount * win4Box12Way; // 1123
        return amount * win4Box24Way; // 1234
      }
      return amount * numbersBox3Way;
    }

    // ---- Combo: مثل Box لكن تدفع Straight سعر كل تركيبة، التكلفة = combos × رهان ----
    // الربح لكل $1 مستوى = Straight prize، لكن المبلغ المدخل هو التكلفة الإجمالية
    if (bt == 'combo' || bt == 'combination') {
      if (!isSortedEqual) return 0;
      final combos = _comboCount(ticketDigits);
      if (combos <= 1) return 0;
      if (n == 3) {
        // رهان الفرد = amount / combos → ربح = رهان الفرد × 500
        return (amount / combos) * numbersStraight;
      }
      if (n == 4) {
        return (amount / combos) * win4Straight;
      }
      return (amount / combos) * numbersStraight;
    }

    // ---- Straight/Box: نصف المبلغ Straight ونصف Box ----
    // NY: تكلفة $1 = $0.5 Straight + $0.5 Box
    // إذا مطابق تام → Straight+Box، إذا أي ترتيب → Box فقط (نصف الرهان)
    if (bt == 'straight/box' || bt == 'straightbox' || bt == 'str/box') {
      if (n == 3) {
        final t = _boxType3(ticketDigits);
        if (t == 'triple') {
          return isExact ? amount * numbersStraight * 0.5 : 0;
        }
        final boxPrizePerDollar = t == '3way' ? numbersBox3Way : numbersBox6Way;
        if (isExact) {
          // $1 exact = $250 Straight (0.5×500) + $80/%40 Box (0.5×Box)
          return amount * 0.5 * numbersStraight + amount * 0.5 * boxPrizePerDollar;
        }
        if (isSortedEqual) {
          // Box فقط بنصف الرهان → فعالة = amount×box×0.5
          return amount * 0.5 * boxPrizePerDollar;
        }
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

    // ---- Pair (Front/Back) — للـ Pick3 فقط، يطابق أول رقمين أو آخر رقمين بالترتيب ----
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

    // ---- Winz أنواع قديمة (نعاملها Straight) ----
    if (bt == 'winz/std' || bt == 'winzstd') return isExact ? amount * winzStd : 0;
    if (bt == 'winz/jackpot' || bt == 'winzjackpot') return isExact ? amount * winzJack : 0;
    if (bt == 'winz/instant' || bt == 'winzinstant') return isExact ? amount * winzInstant : 0;

    // افتراضي Straight
    if (n == 3) return isExact ? amount * numbersStraight : 0;
    if (n == 4) return isExact ? amount * win4Straight : 0;
    return isExact ? amount * numbersStraight : 0;
  }

  Future<Map<String, dynamic>> validateTicket(String code) async {
    final t = await db.getTicketByBarcode(code);
    if (t == null) return {'found': false};
    if (t['status'] == 'cancelled') {
      return {'found': true, 'ticket': t, 'isWinning': false, 'prize': 0, 'cancelled': true};
    }

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
      // Draw not drawn yet — do not mark losing
      return {'found': true, 'ticket': t, 'isWinning': false, 'prize': 0, 'pending': true, 'drawStatus': draw['status']};
    }

    final ticketDigits = (t['numbers'] as String).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final winningDigits = winStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final amount = (t['amount'] as num).toDouble();
    final betType = (t['betType'] as String?) ?? 'Straight';

    final configs = await db.getAppConfig();
    final cfg = {for (var c in configs) c['key'] as String: c['value'] as String};

    final prize = _calculatePrize(
      ticketDigits: ticketDigits,
      winningDigits: winningDigits,
      betType: betType,
      amount: amount,
      cfg: cfg,
    );
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
      // losing — handle demotion if previously winning and now losing (replacement fix)
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

  // Process the draw result - called by admin (persists winningNumbers and evaluates tickets)
  // autoPay = false by default: فقط يعلّم التذاكر رابحة/خاسرة ويحفظ قيمة الربح بناء على المبلغ المدخل
  // إذا autoPay = true سيدفع تلقائيا ويخصم من الكاش
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
    // Validate digits 0-9
    for (final d in winningNumbers) {
      if (!RegExp(r'^[0-9]$').hasMatch(d)) throw Exception('Winning digits must be 0-9');
    }
    // Reset previous evaluations to fix winning->losing bug
    await db.resetDrawTickets(drawId);
    // persist to draw
    await db.updateDrawResult(drawId, winStr);

    final tickets = await db.getTickets();
    final drawTickets = tickets.where((t) => t['drawId'] == drawId).toList();

    int winningCount = 0;
    int losingCount = 0;
    double totalPrize = 0;
    double totalSales = 0;
    for (final t in drawTickets) totalSales += (t['amount'] as num).toDouble();

    for (final ticket in drawTickets) {
      // skip already paid or cancelled
      if (ticket['status'] == 'paid' || ticket['status'] == 'cancelled') continue;
      final res = await validateTicket(ticket['barcode'] ?? ticket['id'] as String);
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
