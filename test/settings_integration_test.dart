// Integration tests for the Laravel settings API and their real side effects.
//
// Run with the Laravel API up:
//   flutter test --no-pub test/settings_integration_test.dart
//
// Contract: POST {baseUrl}/call  {scope: 'db'|'state', method, args}
//                              -> {ok: true, result: ...} | {ok: false, error}
//           POST {baseUrl}/restore {backup: {table: [rows]}} -> {ok, result|error}
//
// All test data uses unique ids and every config key that is touched is
// restored in tearDownAll, so the suite is safe to re-run.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const String apiBaseUrl = 'http://127.0.0.1:8100/api';

final http.Client _client = http.Client();

// ---------------------------------------------------------------- HTTP helpers

Future<Map<String, dynamic>> _request(
  String path,
  Map<String, dynamic> payload,
) async {
  late final http.Response response;
  try {
    response = await _client.post(
      Uri.parse('$apiBaseUrl$path'),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
  } catch (e) {
    fail('Cannot reach $apiBaseUrl$path — is the Laravel server running? $e');
  }

  try {
    return jsonDecode(response.body) as Map<String, dynamic>;
  } catch (e) {
    fail('Non-JSON reply from $path (HTTP ${response.statusCode}): '
        '${response.body}');
  }
}

/// Calls an RPC method and asserts the envelope's `ok` flag.
Future<dynamic> _call(
  String scope,
  String method, [
  Map<String, dynamic> args = const <String, dynamic>{},
]) async {
  final body = await _request('/call', <String, dynamic>{
    'scope': scope,
    'method': method,
    'args': args,
  });
  expect(body['ok'], isTrue,
      reason: '$scope.$method returned ok:false — ${body['error']}');
  return body['result'];
}

Future<Map<String, dynamic>> _callMap(
  String scope,
  String method, [
  Map<String, dynamic> args = const <String, dynamic>{},
]) async {
  final result = await _call(scope, method, args);
  expect(result, isA<Map<String, dynamic>>(),
      reason: '$scope.$method should return an object, got $result');
  return result as Map<String, dynamic>;
}

Future<List<dynamic>> _callList(
  String scope,
  String method, [
  Map<String, dynamic> args = const <String, dynamic>{},
]) async {
  final result = await _call(scope, method, args);
  expect(result, isA<List<dynamic>>(),
      reason: '$scope.$method should return a list, got $result');
  return result as List<dynamic>;
}

/// `state.*` methods always wrap their answer in {value, state}.
Map<String, dynamic> _stateOf(dynamic result) {
  final map = result as Map<String, dynamic>;
  expect(map['state'], isA<Map<String, dynamic>>(),
      reason: 'state RPC must return a state envelope');
  return map['state'] as Map<String, dynamic>;
}

dynamic _valueOf(dynamic result) => (result as Map<String, dynamic>)['value'];

double _d(dynamic value) {
  if (value is num) return value.toDouble();
  return double.parse(value.toString());
}

int _i(dynamic value) {
  if (value is num) return value.toInt();
  return int.parse(value.toString());
}

String _suffix() => DateTime.now().microsecondsSinceEpoch.toString();

// ------------------------------------------------------------------ config I/O

Future<Map<String, String>> _config() async {
  final rows = await _callList('db', 'getAppConfig');
  return <String, String>{
    for (final row in rows)
      (row as Map<String, dynamic>)['key'] as String:
          (row['value'] ?? '').toString(),
  };
}

Future<String> _configValue(String key) async => (await _config())[key] ?? '';

Future<void> _setConfig(String key, String value) async {
  await _call('db', 'upsertConfig', <String, dynamic>{
    'key': key,
    'value': value,
    'scope': 'local',
  });
  expect(await _configValue(key), value,
      reason: 'config "$key" should read back exactly "$value"');
}

// ------------------------------------------- New York wall-time -> UTC helpers
// Mirrors winz-api/app/Services/TimezoneService.php (US DST: 2nd Sunday of
// March -> 1st Sunday of November). This lets us assert exact epochs.

DateTime _nthSunday(int year, int month, int nth) {
  final first = DateTime.utc(year, month, 1);
  final daysUntilSunday = (7 - first.weekday) % 7; // Dart: Mon=1 .. Sun=7
  return first.add(Duration(days: daysUntilSunday + (nth - 1) * 7));
}

int _nyOffsetHours(DateTime wallDate) {
  final dstStart = _nthSunday(wallDate.year, 3, 2);
  final dstEnd = _nthSunday(wallDate.year, 11, 1);
  final date = DateTime.utc(wallDate.year, wallDate.month, wallDate.day);
  return (!date.isBefore(dstStart) && date.isBefore(dstEnd)) ? -4 : -5;
}

int _nyEpochMs(int y, int m, int d, int h, int min) {
  final offset = _nyOffsetHours(DateTime.utc(y, m, d));
  return DateTime.utc(y, m, d, h - offset, min).millisecondsSinceEpoch;
}

String _ymd(DateTime utc) =>
    '${utc.year.toString().padLeft(4, '0')}-'
    '${utc.month.toString().padLeft(2, '0')}-'
    '${utc.day.toString().padLeft(2, '0')}';

void main() {
  group('Laravel settings integration', () {
    late Map<String, String> originalConfig;
    late Map<String, dynamic> adminUser;

    late String workerId;
    late String workerUsername;
    late String workerPassword;
    late Map<String, dynamic> workerUser;

    late String middayPeriodId;
    late String originalMiddayStatus;
    late int originalMiddayClose;
    late int originalMiddayDraw;

    late Map<String, dynamic> prizePeriodBefore;
    late String prizePeriodId;
    late String prizeBarcode;

    late Map<String, dynamic> backupPayload;

    const drawKeys = <String>[
      'midday_sales_close',
      'midday_draw_time',
      'draw_timezone',
      'winning_time_restricted',
    ];
    const generalKeys = <String>[
      'company_name',
      'currency',
      'ticket_footer',
      'printer_type',
      'client_commission_rate',
    ];

    setUpAll(() async {
      originalConfig = await _config();
      final login = await _callMap('state', 'login', <String, dynamic>{
        'username': 'admin',
        'password': 'admin123',
      });
      adminUser =
          Map<String, dynamic>.from(_stateOf(login)['user'] as Map<String, dynamic>);
    });

    tearDownAll(() async {
      // Restore every config key this suite touched, then re-seed so period
      // times follow the restored configuration again.
      for (final key in <String>[
        ...drawKeys,
        ...generalKeys,
        'numbers_straight',
      ]) {
        await _call('db', 'upsertConfig', <String, dynamic>{
          'key': key,
          'value': originalConfig[key] ?? '',
          'scope': 'local',
        });
      }
      await _call('db', 'seedDrawPeriods');
      _client.close();
    });

    // ------------------------------------------------------- A) USERS/WORKERS

    test('A1 admin login reports admin role and isAdmin', () async {
      final result = await _callMap('state', 'login', <String, dynamic>{
        'username': 'admin',
        'password': 'admin123',
      });
      final state = _stateOf(result);
      expect(_valueOf(result), isTrue,
          reason: 'admin/admin123 should authenticate successfully');
      final user = state['user'] as Map<String, dynamic>;
      expect(user['role'], 'admin',
          reason: 'logged-in admin user must have role admin');
      expect(state['isAdmin'], isTrue,
          reason: 'logged-in admin user must expose isAdmin == true');
      adminUser = Map<String, dynamic>.from(user);
    });

    test('A2 insert a new active worker with commission 12.5', () async {
      workerUsername = 'it_worker_${_suffix()}';
      workerId = workerUsername;
      workerPassword = 'pw_${_suffix()}';

      await _call('db', 'insertAccount', <String, dynamic>{
        'a': <String, dynamic>{
          'id': workerId,
          'username': workerUsername,
          'password': workerPassword,
          'role': 'worker',
          'status': 'active',
          'commission': 12.5,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        },
      });

      final accounts = await _callList('db', 'getAccounts');
      final row = accounts.cast<Map<String, dynamic>>().firstWhere(
            (a) => a['id'] == workerId,
            orElse: () => fail('inserted worker $workerId missing from getAccounts'),
          );
      expect(row['role'], 'worker', reason: 'new account role must be worker');
      expect(row['status'], 'active', reason: 'new account status must be active');
      expect(_d(row['commission']), closeTo(12.5, 0.001),
          reason: 'new account commission must be 12.5');
    });

    test('A3 findAccount returns the worker as active at 12.5', () async {
      final found = await _callMap('db', 'findAccount', <String, dynamic>{
        'username': workerUsername,
        'password': workerPassword,
      });
      expect(found['id'], workerId, reason: 'findAccount must locate the worker');
      expect(found['status'], 'active', reason: 'worker must be active');
      expect(_d(found['commission']), closeTo(12.5, 0.001),
          reason: 'worker commission must read back as 12.5 (DECIMAL is a string on the wire)');
    });

    test('A4 updateAccountCommission(25) is visible via findAccount', () async {
      await _call('db', 'updateAccountCommission', <String, dynamic>{
        'id': workerId,
        'commission': 25,
      });
      final found = await _callMap('db', 'findAccount', <String, dynamic>{
        'username': workerUsername,
        'password': workerPassword,
      });
      expect(_d(found['commission']), closeTo(25, 0.001),
          reason: 'commission should now be 25');
    });

    test('A5 worker login exposes worker role and isAdmin false', () async {
      final result = await _callMap('state', 'login', <String, dynamic>{
        'username': workerUsername,
        'password': workerPassword,
      });
      final state = _stateOf(result);
      expect(_valueOf(result), isTrue, reason: 'active worker must log in');
      expect((state['user'] as Map<String, dynamic>)['role'], 'worker',
          reason: 'worker login role must be worker');
      expect(state['isAdmin'], isFalse,
          reason: 'worker login must have isAdmin == false');
      workerUser =
          Map<String, dynamic>.from(state['user'] as Map<String, dynamic>);
    });

    test('A6 worker has zero general balance and an empty cash ledger',
        () async {
      final workerBalance = await _callMap(
          'state', 'computeGeneralBalance', <String, dynamic>{
        'user': workerUser,
      });
      expect(_d(_valueOf(workerBalance)), 0.0,
          reason: 'a brand-new worker must have a 0 general balance');

      final adminGlobal = await _callMap(
          'state', 'computeGeneralBalanceGlobal', <String, dynamic>{
        'user': adminUser,
      });
      expect(_d(_valueOf(adminGlobal)) >= 0, isTrue,
          reason: 'admin global balance must be non-negative');

      final ledger = await _callList(
          'db', 'getCashLedgerByOperator', <String, dynamic>{
        'operatorId': workerId,
      });
      expect(ledger, isEmpty,
          reason: 'a brand-new worker must have no cash ledger rows');
    });

    test('A7 deactivated worker can no longer log in', () async {
      await _call('db', 'deactivateAccount', <String, dynamic>{'id': workerId});

      // Actual behaviour: state.login returns ok:true with result.value=false
      // (a false return value is a valid RPC result, not an error envelope).
      final result = await _callMap('state', 'login', <String, dynamic>{
        'username': workerUsername,
        'password': workerPassword,
      });
      expect(_valueOf(result), isFalse,
          reason: 'deactivated worker login must return false');
      expect(_stateOf(result)['isLoggedIn'], isFalse,
          reason: 'deactivated worker must not be logged in');

      final found = await _callMap('db', 'findAccount', <String, dynamic>{
        'username': workerUsername,
        'password': workerPassword,
      });
      expect(found['status'], 'inactive',
          reason: 'deactivateAccount must persist status=inactive');
    });

    test('A8 audit log row is inserted and readable', () async {
      final auditId = 'it_audit_${_suffix()}';
      await _call('db', 'insertAuditLog', <String, dynamic>{
        'a': <String, dynamic>{
          'id': auditId,
          'user': 'integration_test',
          'action': 'SETTINGS_TEST',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'reason': 'settings integration suite',
        },
      });
      final logs = await _callList('db', 'getAuditLogs');
      final row = logs.cast<Map<String, dynamic>>().firstWhere(
            (e) => e['id'] == auditId,
            orElse: () => fail('inserted audit log $auditId not found'),
          );
      expect(row['action'], 'SETTINGS_TEST',
          reason: 'getAuditLogs must return the inserted row with its action');
    });

    // ------------------------------------------------------ B) DRAW SCHEDULE

    test('B9 draw schedule config is written and read back', () async {
      final before = await _config();
      expect(before.containsKey('midday_sales_close'), isTrue,
          reason: 'bootstrap must provide midday_sales_close config');
      expect(before.containsKey('draw_timezone'), isTrue,
          reason: 'bootstrap must provide draw_timezone config');

      final nowY = DateTime.now().toUtc();
      originalMiddayClose = _nyEpochMs(nowY.year, nowY.month, nowY.day, 14, 15);
      originalMiddayDraw = _nyEpochMs(nowY.year, nowY.month, nowY.day, 14, 30);

      await _setConfig('midday_sales_close', '13:05');
      await _setConfig('midday_draw_time', '13:20');
      await _setConfig('draw_timezone', 'America/New_York');
      await _setConfig('winning_time_restricted', '0');

      final after = await _config();
      expect(after['midday_sales_close'], '13:05',
          reason: 'midday sales close config must be 13:05');
      expect(after['midday_draw_time'], '13:20',
          reason: 'midday draw time config must be 13:20');
      expect(after['draw_timezone'], 'America/New_York',
          reason: 'draw timezone config must be America/New_York');
      expect(after['winning_time_restricted'], '0',
          reason: 'winning_time_restricted config must be 0');
    });

    test('B10 seedDrawPeriods applies schedule config to today\'s MIDDAY',
        () async {
      await _call('db', 'seedDrawPeriods');

      final today = DateTime.now().toUtc();
      final periods =
          await _callList('db', 'getPeriodsByDate', <String, dynamic>{
        'date': _ymd(today),
      });
      final midday = periods.cast<Map<String, dynamic>>()
          .where((p) => p['drawType'] == 'MIDDAY')
          .toList();
      expect(midday, isNotEmpty,
          reason: 'seeding must create a MIDDAY period for today (${_ymd(today)})');

      final expectedClose =
          _nyEpochMs(today.year, today.month, today.day, 13, 5);
      final expectedDraw =
          _nyEpochMs(today.year, today.month, today.day, 13, 20);

      final match = midday.firstWhere(
        (p) =>
            _i(p['salesCloseTime']) == expectedClose &&
            _i(p['drawTime']) == expectedDraw,
        orElse: () => fail(
          'No MIDDAY period has salesCloseTime=$expectedClose (13:05 NY) '
          'and drawTime=$expectedDraw (13:20 NY). Got: '
          '${midday.map((p) => {'id': p['id'], 'close': p['salesCloseTime'], 'draw': p['drawTime']}).toList()}',
        ),
      );
      middayPeriodId = match['id'] as String;
      originalMiddayStatus = (match['status'] as String?) ?? 'OPEN';
    });

    test('B11 refreshPeriodStatuses does not overwrite SUSPENDED', () async {
      expect(middayPeriodId, isNotEmpty,
          reason: 'B10 must have identified a MIDDAY period');
      await _call('db', 'updatePeriodStatus', <String, dynamic>{
        'id': middayPeriodId,
        'status': 'SUSPENDED',
      });
      await _call('db', 'refreshPeriodStatuses');

      final period = await _callMap('db', 'getPeriodById', <String, dynamic>{
        'id': middayPeriodId,
      });
      expect(period['status'], 'SUSPENDED',
          reason: 'blocked states (SUSPENDED) must survive refreshPeriodStatuses');

      // Cleanup: return the period to its prior status so the sale/prize tests
      // can still find a sellable MIDDAY period.
      await _call('db', 'updatePeriodStatus', <String, dynamic>{
        'id': middayPeriodId,
        'status': originalMiddayStatus,
      });
    });

    test('B12 draw schedule config is restored', () async {
      for (final key in drawKeys) {
        await _setConfig(key, originalConfig[key]!);
      }
      await _call('db', 'seedDrawPeriods');

      final today = DateTime.now().toUtc();
      final periods =
          await _callList('db', 'getPeriodsByDate', <String, dynamic>{
        'date': _ymd(today),
      });
      final midday = periods.cast<Map<String, dynamic>>()
          .where((p) => p['id'] == middayPeriodId)
          .toList();
      if (midday.isNotEmpty) {
        expect(_i(midday.first['salesCloseTime']), originalMiddayClose,
            reason: 're-seeding after restoring config must restore the 14:15 close');
        expect(_i(midday.first['drawTime']), originalMiddayDraw,
            reason: 're-seeding after restoring config must restore the 14:30 draw');
      }
    });

    // ------------------------------------------------------ C) PRIZE SETTINGS

    test('C13 straight 3-digit prize uses the current 600x multiplier',
        () async {
      await _setConfig('numbers_straight', '600');

      final cartResult = await _callMap('state', 'addToCart', <String, dynamic>{
        'user': adminUser,
        'gameId': 'g_numbers',
        'gameName': 'Numbers',
        'drawType': 'MIDDAY',
        'numbers': <String>['9', '8', '7'],
        'betType': 'Straight',
        'amount': 0.5,
      });
      final cart = (_stateOf(cartResult)['cart'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(cart, isNotEmpty, reason: 'addToCart must put a play in the cart');
      prizePeriodId = cart.first['periodId'] as String;
      expect(prizePeriodId, isNotEmpty,
          reason: 'cart line must carry the resolved period id');

      prizePeriodBefore =
          await _callMap('db', 'getPeriodById', <String, dynamic>{
        'id': prizePeriodId,
      });

      final sale = await _callMap('state', 'commitSale', <String, dynamic>{
        'user': adminUser,
        'cart': cart,
      });
      prizeBarcode = sale['barcode'] as String;
      expect(prizeBarcode, isNotEmpty,
          reason: 'commitSale must assign a barcode to the ticket');

      // Publish a matching 3-digit result so validateTicket can score it.
      await _callMap('state', 'processPeriodResult', <String, dynamic>{
        'user': adminUser,
        'periodId': prizePeriodId,
        'winningNumbers': <String>['9', '8', '7'],
        'resultSource': 'integration-test',
        'isCorrection': true,
      });

      final validation =
          await _callMap('state', 'validateTicket', <String, dynamic>{
        'user': adminUser,
        'code': prizeBarcode,
      });
      expect(validation['found'], isTrue,
          reason: 'validateTicket must find the committed ticket by barcode');
      expect(_d(validation['prize']), closeTo(300.0, 0.001),
          reason: '0.50 x 600 = 300: prize must use the current multiplier');
    });

    test('C14 re-validating the same ticket with 500x returns 250', () async {
      await _setConfig('numbers_straight', '500');
      final validation =
          await _callMap('state', 'validateTicket', <String, dynamic>{
        'user': adminUser,
        'code': prizeBarcode,
      });
      expect(_d(validation['prize']), closeTo(250.0, 0.001),
          reason: 'the same ticket re-validated at 500x must pay 0.50 x 500 = 250 '
              '(current design applies the current multiplier, not a stored prize)');

      // Cleanup: restore the period row (clears result/result3/result4), reset
      // ticket statuses and leave the period OPEN for other tests/agents.
      await _call('db', 'insertPeriod', <String, dynamic>{
        'p': <String, dynamic>{
          'id': prizePeriodBefore['id'],
          'drawType': prizePeriodBefore['drawType'],
          'drawDate': prizePeriodBefore['drawDate'],
          'salesOpenTime': prizePeriodBefore['salesOpenTime'],
          'salesCloseTime': prizePeriodBefore['salesCloseTime'],
          'drawTime': prizePeriodBefore['drawTime'],
          'status': prizePeriodBefore['status'] ?? 'OPEN',
          'timezone': prizePeriodBefore['timezone'],
          'result': null,
          'resultPublishedAt': null,
          'publishedBy': null,
          'resultSource': null,
        },
      });
      await _call('db', 'resetPeriodTickets', <String, dynamic>{
        'periodId': prizePeriodId,
      });
    });

    test('C15 config values are strings on the API; non-strings rejected',
        () async {
      await _setConfig('numbers_straight', '600');
      final readback = await _config();
      expect(readback['numbers_straight'], isA<String>(),
          reason: 'config values must be strings on the wire');
      expect(readback['numbers_straight'], '600',
          reason: 'config value must read back exactly as written');

      // Empty string is a valid string value (ticket_footer defaults to "").
      // Laravel's ConvertEmptyStringsToNull middleware used to turn this into
      // null and make the typed API reject it.
      await _setConfig('ticket_footer', '');
      expect(await _configValue('ticket_footer'), '',
          reason: 'an empty config value must round-trip as ""');

      final rejected = await _request('/call', <String, dynamic>{
        'scope': 'db',
        'method': 'upsertConfig',
        'args': <String, dynamic>{
          'key': 'probe_type_check',
          'value': 123,
          'scope': 'local',
        },
      });
      expect(rejected['ok'], isFalse,
          reason: 'the API must reject a numeric (non-string) config value');
      expect(rejected['error'].toString(), contains('string'),
          reason: 'the rejection error should mention the string type '
              '(the Flutter UI separately validates invalid multipliers)');
    });

    // ---------------------------------------------------- D) GENERAL SETTINGS

    test('D16 general settings and client commission round-trip', () async {
      await _setConfig('company_name', 'Test Store');
      await _setConfig('currency', 'EUR');
      await _setConfig('ticket_footer', 'Thanks');
      await _setConfig('printer_type', 'thermal_80mm');
      await _call('db', 'setClientCommissionRate', <String, dynamic>{
        'rate': 12.5,
      });

      final config = await _config();
      expect(config['company_name'], 'Test Store',
          reason: 'company_name must round-trip');
      expect(config['currency'], 'EUR', reason: 'currency must round-trip');
      expect(config['ticket_footer'], 'Thanks',
          reason: 'ticket_footer must round-trip');
      expect(config['printer_type'], 'thermal_80mm',
          reason: 'printer_type must round-trip');
      expect(_d(config['client_commission_rate']), closeTo(12.5, 0.001),
          reason: 'client_commission_rate config must be 12.5');

      final rate = await _call('db', 'getClientCommissionRate');
      expect(_d(rate), closeTo(12.5, 0.001),
          reason: 'getClientCommissionRate must return exactly 12.5');
    });

    test('D17 general settings are restored', () async {
      for (final key in generalKeys) {
        await _setConfig(key, originalConfig[key] ?? '');
      }
      final config = await _config();
      for (final key in generalKeys) {
        expect(config[key], originalConfig[key],
            reason: '$key must be restored to its original value');
      }
    });

    // ------------------------------------------------------------- E) BACKUP

    test('E18 full backup restores with ticket count unchanged', () async {
      final customerPlays = <dynamic>[];
      final customers = await _callList('db', 'getCustomers');
      for (final customer in customers.cast<Map<String, dynamic>>()) {
        customerPlays.addAll(
          await _callList('db', 'getCustomerPlays', <String, dynamic>{
            'customerId': customer['id'] as String,
          }),
        );
      }

      backupPayload = <String, dynamic>{
        'accounts': await _callList('db', 'getAccounts'),
        'games': await _callList('db', 'getGames'),
        'draws': await _callList('db', 'getAllDraws'),
        'customers': customers,
        'draw_periods': await _callList('db', 'getAllPeriods'),
        'tickets': await _callList('db', 'getTickets'),
        'ticket_lines': await _callList('db', 'getAllTicketLines'),
        'customer_plays': customerPlays,
        'cash_ledger': await _callList('db', 'getCashLedger'),
        'balance_movements': await _callList('db', 'getBalanceMovements'),
        'cash_sessions': await _callList('db', 'getCashSessions'),
        'app_config': await _callList('db', 'getAppConfig'),
        'audit_logs': await _callList('db', 'getAuditLogs'),
      };
      expect(backupPayload['app_config'], isA<List<dynamic>>(),
          reason: 'backup must include app_config rows');
      expect(backupPayload['cash_ledger'], isA<List<dynamic>>(),
          reason: 'backup must include cash_ledger rows');

      final ticketsBefore = (backupPayload['tickets'] as List<dynamic>).length;
      final restored = await _request('/restore', <String, dynamic>{
        'backup': backupPayload,
      });
      expect(restored['ok'], isTrue,
          reason: 'POST /restore with a complete backup must succeed — '
              '${restored['error']}');

      final ticketsAfter = await _callList('db', 'getTickets');
      expect(ticketsAfter.length, ticketsBefore,
          reason: 'ticket count must be unchanged after restore '
              '($ticketsBefore before, ${ticketsAfter.length} after)');
    });

    test('E19 restore rejects a backup missing a required table', () async {
      final incomplete = Map<String, dynamic>.from(backupPayload)
        ..remove('cash_ledger');
      final result = await _request('/restore', <String, dynamic>{
        'backup': incomplete,
      });
      expect(result['ok'], isFalse,
          reason: 'POST /restore without cash_ledger must fail');
      expect(result['error'].toString(), contains('cash_ledger'),
          reason: 'the error must name the missing required table cash_ledger');
    });

    // ------------------------------------------------------ F) CUSTOMERS EFFECT

    test('F20 customer plays are created, read and deleted', () async {
      final customerId = 'it_cust_${_suffix()}';
      final playId = 'it_play_${_suffix()}';
      final now = DateTime.now().millisecondsSinceEpoch;

      await _call('db', 'insertCustomer', <String, dynamic>{
        'c': <String, dynamic>{
          'id': customerId,
          'name': 'Integration Customer',
          'phone': '555-0100',
          'notes': '',
          'isDefault': 0,
          'createdAt': now,
        },
      });
      await _call('db', 'insertCustomerPlay', <String, dynamic>{
        'play': <String, dynamic>{
          'id': playId,
          'customerId': customerId,
          'gameId': 'g_numbers',
          'gameName': 'Numbers',
          'numbers': '1,2,3',
          'betType': 'Straight',
          'amount': 1.0,
          'drawType': 'MIDDAY',
          'createdAt': now,
        },
      });

      final plays = await _callList('db', 'getCustomerPlays', <String, dynamic>{
        'customerId': customerId,
      });
      final play = plays.cast<Map<String, dynamic>>().firstWhere(
            (p) => p['id'] == playId,
            orElse: () => fail('inserted customer play $playId not found'),
          );
      expect(play['numbers'], '1,2,3', reason: 'play numbers must round-trip');
      expect(play['betType'], 'Straight', reason: 'play betType must round-trip');
      expect(_d(play['amount']), closeTo(1.0, 0.001),
          reason: 'play amount must round-trip');

      await _call('db', 'deleteCustomerPlay', <String, dynamic>{
        'id': playId,
      });
      expect(
        await _callList('db', 'getCustomerPlays', <String, dynamic>{
          'customerId': customerId,
        }),
        isEmpty,
        reason: 'deleteCustomerPlay must remove the play',
      );

      await _call('db', 'deleteCustomer', <String, dynamic>{
        'id': customerId,
      });
      final customers = await _callList('db', 'getCustomers');
      expect(
        customers.cast<Map<String, dynamic>>()
            .any((c) => c['id'] == customerId),
        isFalse,
        reason: 'deleteCustomer must remove the customer from getCustomers',
      );
    });
  });
}
