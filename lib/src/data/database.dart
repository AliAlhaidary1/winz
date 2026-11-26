import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../utils/format.dart';

/// Data-layer client backed by the Laravel API.
///
/// Every public method maps 1:1 to a method exposed by the Laravel `db` scope
/// and is sent as `POST {baseUrl}/call` with:
///
/// ```json
/// {"scope": "db", "method": "<method name>", "args": { ... }}
/// ```
///
/// The server responds with `{"ok": true, "result": ...}` or
/// `{"ok": false, "error": "..."}`. All persistence, schema, seeding and
/// transaction logic lives in the API; this class is a thin typed client.
class AppDatabase {
  /// Creates a client. Calling `AppDatabase()` with no arguments uses
  /// [ApiConfig.baseUrl] and a real [http.Client].
  AppDatabase({String? baseUrl, http.Client? client})
    : _baseUrl = baseUrl ?? ApiConfig.baseUrl,
      _client = client ?? http.Client();

  /// Test-only constructor that accepts an optional mocked [http.Client].
  ///
  /// NOTE: the signature changed from the old
  /// `AppDatabase.forTesting(QueryExecutor e)` because there is no longer a
  /// local query executor to inject.
  AppDatabase.forTesting({http.Client? client, String? baseUrl})
    : _baseUrl = baseUrl ?? ApiConfig.baseUrl,
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  static const double defaultClientCommissionRate = 20.0;

  Future<dynamic> _call(String method, [Map<String, dynamic>? args]) async {
    late final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$_baseUrl/call'),
        headers: const {
          'Content-Type': 'application/json',
          'X-API-Key': ApiConfig.apiToken,
        },
        body: jsonEncode(<String, dynamic>{
          'scope': 'db',
          'method': method,
          'args': args ?? <String, dynamic>{},
        }),
      );
    } on http.ClientException catch (e) {
      throw Exception('API call "$method" could not reach $_baseUrl: $e');
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
      throw Exception(
        'API call "$method" failed: ${decoded['error'] ?? 'unknown error'}',
      );
    }
    return decoded['result'];
  }

  Future<List<Map<String, dynamic>>> _callList(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    final result = await _call(method, args);
    if (result == null) return <Map<String, dynamic>>[];
    return (result as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>?> _callMap(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    final result = await _call(method, args);
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  Future<double> _callDouble(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    final value = await _call(method, args);
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  Future<int> _callInt(String method, [Map<String, dynamic>? args]) async {
    final value = await _call(method, args);
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<String> _callString(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    final value = await _call(method, args);
    return value?.toString() ?? '';
  }

  Future<bool> _callBool(String method, [Map<String, dynamic>? args]) async {
    final value = await _call(method, args);
    if (value is bool) return value;
    return value?.toString().toLowerCase() == 'true';
  }

  Future<void> _callVoid(String method, [Map<String, dynamic>? args]) =>
      _call(method, args);

  // ============ SCHEDULING HELPERS ============

  Future<void> seedDrawPeriods() => _callVoid('seedDrawPeriods');

  Future<void> refreshPeriodStatuses() => _callVoid('refreshPeriodStatuses');

  Future<void> ensurePeriodExists(String periodId) =>
      _callVoid('ensurePeriodExists', {'periodId': periodId});

  // Helpers
  Future<List<Map<String, dynamic>>> getAccounts() => _callList('getAccounts');

  Future<Map<String, dynamic>?> findAccount(String username, String password) =>
      _callMap('findAccount', {'username': username, 'password': password});

  Future<List<Map<String, dynamic>>> getGames() => _callList('getGames');

  Future<List<Map<String, dynamic>>> getDrawsByGame(String gameId) =>
      _callList('getDrawsByGame', {'gameId': gameId});

  Future<List<Map<String, dynamic>>> getAllDraws() => _callList('getAllDraws');

  Future<Map<String, dynamic>?> getDrawById(String id) =>
      _callMap('getDrawById', {'id': id});

  Future<void> updateDrawResult(String id, String winningNumbers) => _callVoid(
    'updateDrawResult',
    {'id': id, 'winningNumbers': winningNumbers},
  );

  Future<void> insertTicket(Map<String, dynamic> t) =>
      _callVoid('insertTicket', {'t': t});

  // Ticket lines (multi-play per ticket)
  Future<void> insertTicketLine(Map<String, dynamic> l) =>
      _callVoid('insertTicketLine', {'l': l});

  Future<List<Map<String, dynamic>>> getTicketLines(String ticketId) =>
      _callList('getTicketLines', {'ticketId': ticketId});

  Future<int> getTicketLinesCount(String ticketId) =>
      _callInt('getTicketLinesCount', {'ticketId': ticketId});

  Future<List<Map<String, dynamic>>> getAllTicketLines() =>
      _callList('getAllTicketLines');

  Future<List<Map<String, dynamic>>> getTicketLinesByPeriod(String periodId) =>
      _callList('getTicketLinesByPeriod', {'periodId': periodId});

  Future<double> sumTicketLinesAmountByPeriod(String periodId) =>
      _callDouble('sumTicketLinesAmountByPeriod', {'periodId': periodId});

  // Insert ticket with its lines in a single helper
  Future<void> insertTicketWithLines(
    Map<String, dynamic> ticket,
    List<Map<String, dynamic>> lines,
  ) => _callVoid('insertTicketWithLines', {'ticket': ticket, 'lines': lines});

  Future<List<Map<String, dynamic>>> getTickets({String? status}) =>
      _callList('getTickets', {'status': ?status});

  Future<Map<String, dynamic>?> getTicketById(String id) =>
      _callMap('getTicketById', {'id': id});

  Future<Map<String, dynamic>?> getTicketByBarcode(String barcode) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return null;
    return _callMap('getTicketByBarcode', {'barcode': trimmed});
  }

  Future<void> updateTicketStatus(
    String id,
    String status, {
    double? prizeAmount,
    int? paidAt,
    String? paidBy,
  }) => _callVoid('updateTicketStatus', {
    'id': id,
    'status': status,
    'prizeAmount': ?prizeAmount,
    'paidAt': ?paidAt,
    'paidBy': ?paidBy,
  });

  /// Atomically reserves the single prize payout allowed for a ticket.
  /// Returns `true` when the payout was reserved, `false` on a duplicate.
  Future<bool> insertPayoutLedger({
    required String ticketId,
    required double amount,
    required String operatorId,
    required int createdAt,
  }) => _callBool('insertPayoutLedger', {
    'ticketId': ticketId,
    'amount': amount,
    'operatorId': operatorId,
    'createdAt': createdAt,
  });

  Future<double> getPayoutAmountForTicket(String ticketId) =>
      _callDouble('getPayoutAmountForTicket', {'ticketId': ticketId});

  /// Frees the payout lock while keeping the original ledger row as history.
  Future<void> releasePayoutLockForTicket(String ticketId, int at) =>
      _callVoid('releasePayoutLockForTicket', {'ticketId': ticketId, 'at': at});

  // Partial void: cancel a single line inside a multi-play ticket
  Future<Map<String, dynamic>?> getTicketLineById(String id) =>
      _callMap('getTicketLineById', {'id': id});

  Future<void> voidTicketLine(String lineId) =>
      _callVoid('voidTicketLine', {'lineId': lineId});

  Future<void> recalcTicketTotals(String ticketId) =>
      _callVoid('recalcTicketTotals', {'ticketId': ticketId});

  Future<void> insertCashLedger(Map<String, dynamic> e) =>
      _callVoid('insertCashLedger', {'e': e});

  Future<void> insertBalanceMovement(Map<String, dynamic> e) =>
      _callVoid('insertBalanceMovement', {'e': e});

  Future<List<Map<String, dynamic>>> getCashLedger() =>
      _callList('getCashLedger');

  Future<List<Map<String, dynamic>>> getBalanceMovements() =>
      _callList('getBalanceMovements');

  Future<Map<String, dynamic>?> getOpenCashSession(String operatorId) =>
      _callMap('getOpenCashSession', {'operatorId': operatorId});

  Future<void> insertCashSession(Map<String, dynamic> s) =>
      _callVoid('insertCashSession', {'s': s});

  Future<void> closeCashSession(
    String id,
    double closingAmount,
    int closedAt,
  ) => _callVoid('closeCashSession', {
    'id': id,
    'closingAmount': closingAmount,
    'closedAt': closedAt,
  });

  Future<List<Map<String, dynamic>>> getCashSessions() =>
      _callList('getCashSessions');

  Future<List<Map<String, dynamic>>> getAppConfig() =>
      _callList('getAppConfig');

  Future<void> upsertConfig(String key, String value, String scope) =>
      _callVoid('upsertConfig', {'key': key, 'value': value, 'scope': scope});

  Future<double> getClientCommissionRate() async {
    final result = await _call('getClientCommissionRate');
    if (result == null) return defaultClientCommissionRate;
    final rate = asDouble(result);
    return rate < 0 ? defaultClientCommissionRate : rate;
  }

  Future<void> setClientCommissionRate(double rate) =>
      _callVoid('setClientCommissionRate', {'rate': rate});

  Future<String> nextTicketId() => _callString('nextTicketId');

  Future<String> nextSerialNumber() => _callString('nextSerialNumber');

  Future<double> sumCash(
    String direction, {
    String? type,
    String? operatorId,
  }) => _callDouble('sumCash', {
    'direction': direction,
    'type': ?type,
    'operatorId': ?operatorId,
  });

  /// Sum cash movements strictly after a session boundary.
  Future<double> sumCashSince(
    String direction,
    int since, {
    String? operatorId,
  }) => _callDouble('sumCashSince', {
    'direction': direction,
    'since': since,
    'operatorId': ?operatorId,
  });

  Future<Map<String, dynamic>?> getLastClosedCashSession(String operatorId) =>
      _callMap('getLastClosedCashSession', {'operatorId': operatorId});

  Future<List<Map<String, dynamic>>> getCashLedgerByTicket(String ticketId) =>
      _callList('getCashLedgerByTicket', {'ticketId': ticketId});

  // Reset tickets for draw replacement (fix winning->losing bug)
  Future<void> resetDrawTickets(String drawId) =>
      _callVoid('resetDrawTickets', {'drawId': drawId});

  // Operator-filtered ledger/balance for per-operator cash
  Future<List<Map<String, dynamic>>> getCashLedgerByOperator(
    String operatorId,
  ) => _callList('getCashLedgerByOperator', {'operatorId': operatorId});

  Future<List<Map<String, dynamic>>> getBalanceMovementsByOperator(
    String operatorId,
  ) => _callList('getBalanceMovementsByOperator', {'operatorId': operatorId});

  // ============ DRAW PERIODS ============

  Future<void> insertPeriod(Map<String, dynamic> p) =>
      _callVoid('insertPeriod', {'p': p});

  Future<Map<String, dynamic>?> getPeriodById(String id) =>
      _callMap('getPeriodById', {'id': id});

  Future<List<Map<String, dynamic>>> getAllPeriods() =>
      _callList('getAllPeriods');

  Future<List<Map<String, dynamic>>> getPeriodsByDate(String date) =>
      _callList('getPeriodsByDate', {'date': date});

  Future<List<Map<String, dynamic>>> getOpenPeriods() =>
      _callList('getOpenPeriods');

  Future<void> updatePeriodStatus(String id, String status) =>
      _callVoid('updatePeriodStatus', {'id': id, 'status': status});

  Future<void> updatePeriodTimes(
    String id,
    int salesOpen,
    int salesClose,
    int drawTime,
  ) => _callVoid('updatePeriodTimes', {
    'id': id,
    'salesOpen': salesOpen,
    'salesClose': salesClose,
    'drawTime': drawTime,
  });

  Future<void> publishPeriodResult(
    String id,
    String result,
    int publishedAt,
    String publishedBy,
    String source,
  ) => _callVoid('publishPeriodResult', {
    'id': id,
    'result': result,
    'publishedAt': publishedAt,
    'publishedBy': publishedBy,
    'source': source,
  });

  // Dual winners: separate 3-digit and 4-digit results
  Future<void> publishPeriodResult3(
    String id,
    String result,
    int publishedAt,
    String publishedBy,
    String source,
  ) => _callVoid('publishPeriodResult3', {
    'id': id,
    'result': result,
    'publishedAt': publishedAt,
    'publishedBy': publishedBy,
    'source': source,
  });

  Future<void> publishPeriodResult4(
    String id,
    String result,
    int publishedAt,
    String publishedBy,
    String source,
  ) => _callVoid('publishPeriodResult4', {
    'id': id,
    'result': result,
    'publishedAt': publishedAt,
    'publishedBy': publishedBy,
    'source': source,
  });

  Future<void> clearPeriodResult3(String id) =>
      _callVoid('clearPeriodResult3', {'id': id});

  Future<void> clearPeriodResult4(String id) =>
      _callVoid('clearPeriodResult4', {'id': id});

  Future<void> resetPeriodTickets(String periodId) =>
      _callVoid('resetPeriodTickets', {'periodId': periodId});

  // ============ AUDIT LOGS ============

  Future<void> insertAuditLog(Map<String, dynamic> a) =>
      _callVoid('insertAuditLog', {'a': a});

  Future<List<Map<String, dynamic>>> getAuditLogs({String? periodId}) =>
      _callList('getAuditLogs', {'periodId': ?periodId});

  // ============ CUSTOMERS ============

  Future<List<Map<String, dynamic>>> getCustomers() =>
      _callList('getCustomers');

  Future<Map<String, dynamic>?> getCustomerById(String id) =>
      _callMap('getCustomerById', {'id': id});

  Future<void> insertCustomer(Map<String, dynamic> c) =>
      _callVoid('insertCustomer', {'c': c});

  Future<void> updateCustomer(
    String id,
    String name,
    String phone,
    String notes,
  ) => _callVoid('updateCustomer', {
    'id': id,
    'name': name,
    'phone': phone,
    'notes': notes,
  });

  Future<void> deleteCustomer(String id) =>
      _callVoid('deleteCustomer', {'id': id});

  Future<List<Map<String, dynamic>>> getCustomerPlays(String customerId) =>
      _callList('getCustomerPlays', {'customerId': customerId});

  Future<void> insertCustomerPlay(Map<String, dynamic> play) =>
      _callVoid('insertCustomerPlay', {'play': play});

  Future<void> deleteCustomerPlay(String id) =>
      _callVoid('deleteCustomerPlay', {'id': id});

  Future<void> insertAccount(Map<String, dynamic> a) =>
      _callVoid('insertAccount', {'a': a});

  Future<void> updateAccountCommission(String id, double commission) =>
      _callVoid('updateAccountCommission', {
        'id': id,
        'commission': commission,
      });

  Future<void> deactivateAccount(String id) =>
      _callVoid('deactivateAccount', {'id': id});

  /// Keep historical tickets valid when a customer is removed.
  Future<void> reassignCustomerTickets(
    String fromId,
    String toId,
    String toName,
  ) => _callVoid('reassignCustomerTickets', {
    'fromId': fromId,
    'toId': toId,
    'toName': toName,
  });
}
