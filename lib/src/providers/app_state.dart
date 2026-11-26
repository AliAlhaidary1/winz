import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config/api_config.dart';
import '../data/database.dart';
import '../utils/format.dart';

/// A single line in the sale cart.
///
/// The shape is kept identical to the pre-API version so every screen that
/// reads [AppState.cart] keeps compiling unchanged.
class CartItem {
  final String id; // local uuid for cart manipulation
  final String gameId;
  final String gameName;
  final String? drawId;
  final String? drawName;
  final String? periodId; // e.g., 2026-09-01-MIDDAY
  final String? drawType; // MIDDAY / EVENING / BOTH?
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

/// Thin client for the Laravel `state` scope.
///
/// Every business method forwards to `POST {ApiConfig.baseUrl}/call` with
/// `{"scope":"state","method":...,"args":{...}}`. No pricing, limit, prize or
/// cash computation happens here — it all lives in the Laravel StateService.
/// Only the small amount of UI state the screens read is mirrored locally.
class AppState extends ChangeNotifier {
  final AppDatabase db;

  AppState(this.db);

  static const String defaultCustomerId = 'cust_default';
  static const String defaultCustomerName = 'Cash Customer';

  // ---------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------

  Future<dynamic> _call(
    String scope,
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    late final http.Response response;
    try {
      response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/call'),
        headers: const {
          'Content-Type': 'application/json',
          'X-API-Key': ApiConfig.apiToken,
        },
        body: jsonEncode(<String, dynamic>{
          'scope': scope,
          'method': method,
          // Laravel hydrates its service from this envelope on every call,
          // because HTTP is stateless. Extra keys are ignored by its RPC
          // argument mapper.
          'args': scope == 'state'
              ? <String, dynamic>{
                  ...args,
                  'user': _currentUser,
                  'loginAt': _loginAt?.millisecondsSinceEpoch,
                  'customer': _currentCustomer,
                  'cart': _cart.map((e) => e.toMap()).toList(),
                  'openingCash': _openingCash,
                }
              : args,
        }),
      );
    } on http.ClientException catch (e) {
      throw Exception(
        'API call "$method" could not reach ${ApiConfig.baseUrl}: $e',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'API call "$method" failed with HTTP ${response.statusCode}: '
        '${response.body}',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      throw Exception('API call "$method" returned invalid JSON: $e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw Exception('API call "$method" returned an unexpected payload.');
    }
    if (decoded['ok'] != true) {
      throw Exception(decoded['error'] ?? 'unknown error');
    }
    final result = decoded['result'];
    if (scope == 'state') {
      _applyServerState(result);
    }
    return result;
  }

  void _applyServerState(dynamic result) {
    final map = result is Map ? Map<String, dynamic>.from(result) : null;
    final state = map != null ? map['state'] : null;
    if (state is! Map) return;
    final s = Map<String, dynamic>.from(state);
    if (s.containsKey('user')) {
      final u = s['user'];
      _currentUser = u is Map ? Map<String, dynamic>.from(u) : null;
    }
    if (s['loginAt'] is num) {
      _loginAt = DateTime.fromMillisecondsSinceEpoch(asInt(s['loginAt']));
    }
    if (s['customer'] is Map) {
      _currentCustomer = Map<String, dynamic>.from(s['customer'] as Map);
    }
    if (s['cart'] is List) {
      _cart = (s['cart'] as List).map(_cartItemFromDynamic).toList();
    }
    if (s['openingCash'] is num) {
      _openingCash = asDouble(s['openingCash']);
    }
  }

  // ---------------------------------------------------------------------------
  // Small result/payload helpers (not business logic)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value
        .map(
          (e) => e is Map<String, dynamic>
              ? e
              : Map<String, dynamic>.from(e as Map),
        )
        .toList();
  }

  double _asDouble(dynamic value, [double fallback = 0.0]) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  int _asInt(dynamic value, [int fallback = 0]) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  bool _asBool(dynamic value, [bool fallback = false]) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final s = value.toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return fallback;
  }

  List<Map<String, dynamic>> _cartPayload() =>
      _cart.map((e) => e.toMap()).toList();

  CartItem _cartItemFromDynamic(dynamic value) {
    final m = _asMap(value);
    final numbersRaw = m['numbers'];
    final List<String> numbers = numbersRaw is List
        ? numbersRaw.map((n) => n.toString()).toList()
        : numbersRaw
              .toString()
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
    final qp = m['isQuickPick'];
    return CartItem(
      id: (m['id'] ?? const Uuid().v4()).toString(),
      gameId: (m['gameId'] ?? '').toString(),
      gameName: (m['gameName'] ?? '').toString(),
      drawId: m['drawId']?.toString(),
      drawName: m['drawName']?.toString(),
      periodId: m['periodId']?.toString(),
      drawType: m['drawType']?.toString(),
      numbers: numbers,
      betType: (m['betType'] ?? 'Straight').toString(),
      amount: _asDouble(m['amount']),
      isQuickPick: qp == true || qp == 1 || qp == '1',
    );
  }

  /// Mirrors the cart returned by Laravel; falls back to a locally maintained
  /// list when the endpoint has nothing to say about the cart.
  void _setCartFromResult(dynamic result, {List<CartItem>? fallback}) {
    List<dynamic>? raw;
    if (result is List) {
      raw = result;
    } else {
      final m = _asMap(result);
      if (m['cart'] is List) {
        raw = m['cart'] as List<dynamic>;
      } else if (m['state'] is Map && _asMap(m['state'])['cart'] is List) {
        // StateService returns its snapshot under `state`; _call has already
        // applied it locally, so never append a fallback on top of it.
        raw = _asMap(m['state'])['cart'] as List<dynamic>;
      }
    }
    if (raw != null) {
      _cart = raw.map(_cartItemFromDynamic).toList();
    } else if (fallback != null) {
      _cart = List<CartItem>.from(fallback);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Local UI state
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _currentCustomer = {
    'id': defaultCustomerId,
    'name': defaultCustomerName,
  };

  /// Walk-in sales use this customer until a registered one is selected.
  Map<String, dynamic> get currentCustomer =>
      Map<String, dynamic>.from(_currentCustomer);

  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  // session expiry: 8 hours
  DateTime? _loginAt;
  bool get isSessionExpired {
    if (_loginAt == null) return true;
    return DateTime.now().difference(_loginAt!).inHours >= 8;
  }

  void _ensureNotExpired() {
    if (isSessionExpired) {
      throw Exception('Session expired — please login again');
    }
  }

  bool get isAdmin => _currentUser?['role'] == 'admin';

  List<CartItem> _cart = [];
  List<CartItem> get cart => List.unmodifiable(_cart);
  int get cartCount => _cart.length;
  double get cartTotal => _cart.fold(0, (s, e) => s + e.amount);
  bool get isCartEmpty => _cart.isEmpty;

  double _openingCash = 0;
  double get openingCash => _openingCash;

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  Future<bool> login(String username, String password) async {
    final result = await _call('state', 'login', {
      'username': username,
      'password': password,
    });

    Map<String, dynamic>? account;
    final envelope = _asMap(result);
    final state = envelope['state'];
    if (state is Map) {
      final u = _asMap(state)['user'];
      if (u is Map && u.isNotEmpty) account = Map<String, dynamic>.from(u);
    }
    if (account == null && result == true) {
      final fetched = await db.findAccount(username.trim(), password);
      if (fetched != null && fetched['status'] == 'active') account = fetched;
    }
    if (account == null || account['id'] == null) return false;

    _currentUser = account;
    _loginAt = DateTime.now();
    notifyListeners();
    return true;
  }

  void logout() {
    _currentUser = null;
    _loginAt = null;
    _cart = [];
    _currentCustomer = {'id': defaultCustomerId, 'name': defaultCustomerName};
    notifyListeners();
    unawaited(_call('state', 'logout').catchError((dynamic _) {}));
  }

  // ---------------------------------------------------------------------------
  // Backup
  // ---------------------------------------------------------------------------

  /// Manual backup triggered from UI — returns backup file path.
  Future<String> triggerManualBackup() async {
    final result = await _call('state', 'triggerManualBackup');
    if (result is Map) return (_asMap(result)['path'] ?? '').toString();
    return result?.toString() ?? '';
  }

  /// Get backup config for UI.
  Future<Map<String, dynamic>> getBackupConfig() async =>
      _asMap(await _call('state', 'getBackupConfig'));

  // ---------------------------------------------------------------------------
  // Customers
  // ---------------------------------------------------------------------------

  Future<void> useDefaultCustomer() async {
    final result = await _call('state', 'useDefaultCustomer');
    if (result is Map) {
      _currentCustomer = _asMap(result);
    } else {
      final c = await db.getCustomerById(defaultCustomerId);
      _currentCustomer =
          c ?? {'id': defaultCustomerId, 'name': defaultCustomerName};
    }
    notifyListeners();
  }

  Future<void> selectCustomer(String customerId) async {
    final result = await _call('state', 'selectCustomer', {
      'customerId': customerId,
    });
    if (result is Map) {
      _currentCustomer = _asMap(result);
    } else {
      final c = await db.getCustomerById(customerId);
      if (c == null) throw Exception('Customer not found');
      _currentCustomer = c;
    }
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getCustomers() => db.getCustomers();

  Future<String> addCustomer({
    required String name,
    String? phone,
    String? notes,
  }) async {
    final result = await _call('state', 'addCustomer', {
      'name': name,
      'phone': phone,
      'notes': notes,
    });
    notifyListeners();
    if (result is Map) return (_asMap(result)['id'] ?? '').toString();
    return result?.toString() ?? '';
  }

  Future<void> updateCustomer(
    String id, {
    required String name,
    String? phone,
    String? notes,
  }) async {
    final result = await _call('state', 'updateCustomer', {
      'id': id,
      'name': name,
      'phone': phone,
      'notes': notes,
    });
    if (result is Map && _currentCustomer['id'] == id) {
      _currentCustomer = _asMap(result);
    } else if (_currentCustomer['id'] == id) {
      final c = await db.getCustomerById(id);
      if (c != null) _currentCustomer = c;
    }
    notifyListeners();
  }

  Future<void> deleteCustomer(String id) async {
    await _call('state', 'deleteCustomer', {'id': id});
    if (_currentCustomer['id'] == id) {
      await useDefaultCustomer();
    } else {
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> getCustomerPlays(String customerId) =>
      db.getCustomerPlays(customerId);

  /// Add one saved play for a customer (numbers + type + amount).
  Future<void> addCustomerPlay(
    String customerId, {
    required String gameId,
    required String gameName,
    required String numbers,
    required String betType,
    required double amount,
    String? drawType,
    bool isQuickPick = false,
  }) async {
    await db.insertCustomerPlay({
      'id': const Uuid().v4(),
      'customerId': customerId,
      'gameId': gameId,
      'gameName': gameName,
      'numbers': numbers,
      'betType': betType,
      'amount': amount,
      'drawType': drawType,
      'isQuickPick': isQuickPick ? 1 : 0,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deleteCustomerPlay(String playId) =>
      db.deleteCustomerPlay(playId);

  /// Save every cart line as this customer's usual play.
  Future<int> saveCartAsCustomerPlays(
    String customerId, {
    String? drawType,
  }) async {
    final result = await _call('state', 'saveCartAsCustomerPlays', {
      'customerId': customerId,
      'drawType': drawType,
      'cart': _cartPayload(),
    });
    notifyListeners();
    return _asInt(result, _cart.length);
  }

  /// Add a registered customer's saved plays to the cart.
  Future<Map<String, dynamic>> playCustomerUsual(String customerId) async {
    final result = await _call('state', 'playCustomerUsual', {
      'customerId': customerId,
      'cart': _cartPayload(),
    });
    final map = _asMap(result);

    final returnedCustomer = map['customer'];
    if (returnedCustomer is Map) {
      _currentCustomer = _asMap(returnedCustomer);
    } else {
      try {
        await selectCustomer(customerId);
      } catch (_) {}
    }
    _setCartFromResult(map, fallback: _cart);
    return map;
  }

  // ---------------------------------------------------------------------------
  // Cart / sale
  // ---------------------------------------------------------------------------

  Future<bool> isDrawTypeSellableNow(String drawType) async => _asBool(
    await _call('state', 'isDrawTypeSellableNow', {'drawType': drawType}),
  );

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
    final result = await _call('state', 'addToCart', {
      'gameId': gameId,
      'gameName': gameName,
      'drawId': drawId,
      'drawName': drawName,
      'periodId': periodId,
      'drawType': drawType,
      'numbers': numbers,
      'betType': betType,
      'amount': amount,
      'isQuickPick': isQuickPick,
      'cart': _cartPayload(),
    });
    _setCartFromResult(
      result,
      fallback: [
        ..._cart,
        CartItem(
          id: const Uuid().v4(),
          gameId: gameId,
          gameName: gameName,
          drawId: drawId,
          drawName: drawName,
          periodId: periodId,
          drawType: drawType,
          numbers: List<String>.from(numbers),
          betType: betType,
          amount: amount,
          isQuickPick: isQuickPick,
        ),
      ],
    );
  }

  /// Both Draws: one participation for each of the next two open periods.
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
    final result = await _call('state', 'addBothToCart', {
      'gameId': gameId,
      'gameName': gameName,
      'numbers': numbers,
      'betType': betType,
      'amountPerDraw': amountPerDraw,
      'isQuickPick': isQuickPick,
      'forDate': forDate?.millisecondsSinceEpoch,
      'cart': _cartPayload(),
    });
    _setCartFromResult(
      result,
      fallback: [
        ..._cart,
        for (var i = 0; i < 2; i++)
          CartItem(
            id: const Uuid().v4(),
            gameId: gameId,
            gameName: gameName,
            numbers: List<String>.from(numbers),
            betType: betType,
            amount: amountPerDraw,
            isQuickPick: isQuickPick,
          ),
      ],
    );
  }

  void removeFromCart(String cartId) {
    final payload = _cartPayload();
    _cart.removeWhere((e) => e.id == cartId);
    notifyListeners();
    unawaited(
      _call('state', 'removeFromCart', {'cartId': cartId, 'cart': payload})
          .then((r) => _setCartFromResult(r, fallback: _cart))
          .catchError((dynamic _) {}),
    );
  }

  void clearCart() {
    final payload = _cartPayload();
    _cart = [];
    notifyListeners();
    unawaited(
      _call('state', 'clearCart', {'cart': payload})
          .then((r) => _setCartFromResult(r, fallback: _cart))
          .catchError((dynamic _) {}),
    );
  }

  /// Commit sale -> one ticket containing all cart lines.
  Future<Map<String, dynamic>> commitSale() async {
    if (_currentUser == null) throw Exception('Not logged in');
    _ensureNotExpired();
    final result = await _call('state', 'commitSale', {'cart': _cartPayload()});
    _cart = [];
    notifyListeners();
    return _asMap(result);
  }

  // Replay: copy whole ticket into cart for a new sale.
  Future<Map<String, dynamic>> replayTicketToCart(String ticketId) =>
      replayTicketToCartWithChoice(ticketId, 'AUTO');

  /// Replay with explicit draw choice: MIDDAY / EVENING / BOTH / AUTO.
  Future<Map<String, dynamic>> replayTicketToCartWithChoice(
    String ticketId,
    String drawChoice,
  ) async {
    final result = await _call('state', 'replayTicketToCartWithChoice', {
      'ticketId': ticketId.trim(),
      'drawChoice': drawChoice.trim().toUpperCase(),
      'cart': _cartPayload(),
    });
    final map = _asMap(result);
    _setCartFromResult(map, fallback: _cart);
    return map;
  }

  /// Move every cart line to the next sellable Midday or Evening period.
  Future<void> remapCartToDrawType(String drawType) async {
    final result = await _call('state', 'remapCartToDrawType', {
      'drawType': drawType,
      'cart': _cartPayload(),
    });
    _setCartFromResult(
      result,
      fallback: _cart.map((e) => e.copyWith(drawType: drawType)).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Cash sessions & balances
  // ---------------------------------------------------------------------------

  Future<void> loadOpeningCash() async {
    if (_currentUser == null) return;
    final result = await _call('state', 'loadOpeningCash');
    final m = _asMap(result);
    _openingCash = result is num
        ? result.toDouble()
        : _asDouble(m['openingAmount'] ?? m['openingCash']);
    notifyListeners();
  }

  Future<void> openCashSession(double amount) async {
    if (_currentUser == null) return;
    final result = await _call('state', 'openCashSession', {'amount': amount});
    final m = _asMap(result);
    _openingCash = result is num
        ? result.toDouble()
        : _asDouble(m['openingAmount'] ?? m['openingCash'], amount);
    notifyListeners();
  }

  Future<double> closeCashSession() async {
    if (_currentUser == null) return 0;
    final result = await _call('state', 'closeCashSession');
    final m = _asMap(result);
    final cash = result is num
        ? result.toDouble()
        : _asDouble(m['cashNow'] ?? m['cash'] ?? m['closingAmount']);
    _openingCash = 0;
    notifyListeners();
    return cash;
  }

  Future<double> computeCashBalance({String? operatorId}) async => _asDouble(
    await _call('state', 'computeCashBalance', {'operatorId': operatorId}),
  );

  Future<double> computeGeneralBalance({String? operatorId}) async => _asDouble(
    await _call('state', 'computeGeneralBalance', {'operatorId': operatorId}),
  );

  Future<double> computeCashBalanceGlobal() async =>
      _asDouble(await _call('state', 'computeCashBalanceGlobal'));

  Future<double> computeGeneralBalanceGlobal() async =>
      _asDouble(await _call('state', 'computeGeneralBalanceGlobal'));

  // ---------------------------------------------------------------------------
  // Tickets
  // ---------------------------------------------------------------------------

  /// Legacy single ticket creation — kept for backward compatibility.
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
    final result = await _call('state', 'createTicket', {
      'gameId': gameId,
      'gameName': gameName,
      'drawId': drawId,
      'drawName': drawName,
      'numbers': numbers,
      'betType': betType,
      'amount': amount,
      'isQuickPick': isQuickPick,
      'cart': _cartPayload(),
    });
    notifyListeners();
    return _asMap(result);
  }

  Future<bool> payWinningTicket(String ticketId, double prize) async {
    if (_currentUser == null) return false;
    _ensureNotExpired();
    final result = await _call('state', 'payWinningTicket', {
      'ticketId': ticketId,
      'prize': prize,
    });
    final ok = result is Map
        ? _asBool(_asMap(result)['ok'], true)
        : _asBool(result);
    if (ok) notifyListeners();
    return ok;
  }

  /// Reverse a payout made under a result that was later corrected.
  Future<bool> reversePayout(String ticketId, String reason) async {
    final result = await _call('state', 'reversePayout', {
      'ticketId': ticketId,
      'reason': reason,
    });
    final ok = result is Map
        ? _asBool(_asMap(result)['ok'], true)
        : _asBool(result);
    if (ok) notifyListeners();
    return ok;
  }

  /// Cancel whole ticket (all remaining active plays). Returns the refund.
  Future<double> cancelWholeTicket(String ticketId) async {
    if (_currentUser == null) throw Exception('Not logged in');
    _ensureNotExpired();
    final result = await _call('state', 'cancelWholeTicket', {
      'ticketId': ticketId,
    });
    notifyListeners();
    if (result is Map) return _asDouble(_asMap(result)['refund']);
    return _asDouble(result);
  }

  /// Cancel a single play inside an invoice. Returns the refund amount.
  Future<double> cancelTicketLine({
    required String ticketId,
    required String lineId,
  }) async {
    if (_currentUser == null) throw Exception('Not logged in');
    _ensureNotExpired();
    final result = await _call('state', 'cancelTicketLine', {
      'ticketId': ticketId,
      'lineId': lineId,
    });
    notifyListeners();
    if (result is Map) return _asDouble(_asMap(result)['refund']);
    return _asDouble(result);
  }

  /// Validate a ticket (barcode, id or serial number).
  Future<Map<String, dynamic>> validateTicket(String code) async =>
      _asMap(await _call('state', 'validateTicket', {'code': code}));

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
    final result = await _call('state', 'processPeriodResult', {
      'periodId': periodId,
      'winningNumbers': winningNumbers,
      'autoPay': autoPay,
      'resultSource': resultSource,
      'isCorrection': isCorrection,
    });
    notifyListeners();
    return _asMap(result);
  }

  Future<Map<String, dynamic>> processDrawResult({
    required String drawId,
    required List<String> winningNumbers,
    bool autoPay = false,
  }) async {
    if (_currentUser == null) throw Exception('Not logged in');
    _ensureNotExpired();
    if (!isAdmin) throw Exception('Only admin can set winning numbers');
    final result = await _call('state', 'processDrawResult', {
      'drawId': drawId,
      'winningNumbers': winningNumbers,
      'autoPay': autoPay,
    });
    notifyListeners();
    return _asMap(result);
  }
}
