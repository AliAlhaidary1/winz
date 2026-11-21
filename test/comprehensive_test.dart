import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:winz/src/data/database.dart';
import 'package:winz/src/providers/app_state.dart';

void main() {
  group('YeLottery Comprehensive - Full Flow', () {
    late AppDatabase db;
    late AppState app;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      // Trigger DB creation (beforeOpen seeds)
      await db.customSelect('SELECT 1').get();
      // Clean and reseed with controlled data
      await db.customStatement('DELETE FROM tickets');
      await db.customStatement('DELETE FROM cash_ledger');
      await db.customStatement('DELETE FROM balance_movements');
      await db.customStatement('DELETE FROM cash_sessions');
      await db.customStatement('DELETE FROM draws');
      await db.customStatement(
        "DELETE FROM app_config WHERE key IN ('numbers_straight','numbers_box_3way','numbers_box_6way','numbers_front_pair','numbers_back_pair','win4_straight','win4_box_4way','win4_box_6way','win4_box_12way','win4_box_24way')",
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final e in [
        ['numbers_straight', '500'],
        ['numbers_box_3way', '160'],
        ['numbers_box_6way', '80'],
        ['numbers_front_pair', '50'],
        ['numbers_back_pair', '50'],
        ['win4_straight', '5000'],
        ['win4_box_4way', '1200'],
        ['win4_box_6way', '800'],
        ['win4_box_12way', '400'],
        ['win4_box_24way', '200'],
      ]) {
        await db.customStatement(
          "INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('${e[0]}', '${e[1]}', 'local', $now)",
        );
      }
      // Draws - future to avoid cutoff (5 min rule)
      final future = DateTime.now().add(Duration(hours: 6));
      await db.customStatement(
        "INSERT INTO draws (id, gameId, name, drawTime, status) VALUES ('draw_midday', 'g_numbers', 'Numbers Midday - 02:30 PM', ${future.millisecondsSinceEpoch}, 'open')",
      );
      await db.customStatement(
        "INSERT INTO draws (id, gameId, name, drawTime, status) VALUES ('draw_evening', 'g_numbers', 'Numbers Evening - 10:30 PM', ${future.add(Duration(hours: 8)).millisecondsSinceEpoch}, 'open')",
      );
      await db.customStatement(
        "INSERT INTO draws (id, gameId, name, drawTime, status) VALUES ('draw_win4_midday', 'g_winz', 'Win 4 Midday - 02:30 PM', ${future.millisecondsSinceEpoch}, 'open')",
      );
      await db.customStatement(
        "INSERT INTO draws (id, gameId, name, drawTime, status) VALUES ('draw_win4_evening', 'g_winz', 'Win 4 Evening - 10:30 PM', ${future.add(Duration(hours: 8)).millisecondsSinceEpoch}, 'open')",
      );

      app = AppState(db);
      expect(await app.login('admin', 'admin123'), isTrue);
      final today = DateTime.now();
      final dateStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final later = today.add(const Duration(hours: 12)).millisecondsSinceEpoch;
      await db.customStatement(
        "UPDATE draw_periods SET salesOpenTime=0, salesCloseTime=$later, drawTime=$later, status='OPEN' WHERE drawDate='$dateStr'",
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('Play - Numbers 3-digit Straight with 0', () async {
      final t = await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_midday',
        drawName: 'Numbers Midday',
        numbers: ['0', '1', '2'],
        betType: 'Straight',
        amount: 1.0,
        isQuickPick: false,
      );
      expect(t['numbers'], '0,1,2');
      expect(t['status'], 'active');
      final cash = await app.computeCashBalance();
      expect(cash, 1.0);
    });

    test('All bet types prize calculation - Pick 3', () async {
      // Create tickets for each type
      await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_midday',
        drawName: 'Midday',
        numbers: ['1', '2', '3'],
        betType: 'Straight',
        amount: 1.0,
        isQuickPick: false,
      ); // T1
      await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_midday',
        drawName: 'Midday',
        numbers: ['1', '1', '2'],
        betType: 'Box',
        amount: 1.0,
        isQuickPick: false,
      ); // T2 3-way
      await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_midday',
        drawName: 'Midday',
        numbers: ['1', '2', '3'],
        betType: 'Box',
        amount: 1.0,
        isQuickPick: false,
      ); // T3 6-way
      await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_midday',
        drawName: 'Midday',
        numbers: ['1', '1', '2'],
        betType: 'Combo',
        amount: 3.0,
        isQuickPick: false,
      ); // T4 combo 3-way cost 3
      await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_midday',
        drawName: 'Midday',
        numbers: ['1', '2', '3'],
        betType: 'Straight/Box',
        amount: 1.0,
        isQuickPick: false,
      ); // T5 strbox 6-way
      await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_midday',
        drawName: 'Midday',
        numbers: ['1', '2', '3'],
        betType: 'Front Pair',
        amount: 1.0,
        isQuickPick: false,
      ); // T6 pair
      await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_midday',
        drawName: 'Midday',
        numbers: ['1', '2', '3'],
        betType: 'Back Pair',
        amount: 1.0,
        isQuickPick: false,
      );
      // Process draw 123
      final res = await app.processDrawResult(
        drawId: 'draw_midday',
        winningNumbers: ['1', '2', '3'],
      );
      expect(res['totalTickets'], 7); // includes earlier 0,1,2? Actually 7 from this test isolation? each test has fresh DB, so 7
      // Validate each ticket individually
      final tickets = await db.getTickets();
      // Straight 123 should win 500
      var r = await app.validateTicket(
        (await db.getTickets()).firstWhere(
          (e) => e['betType'] == 'Straight' && e['numbers'] == '1,2,3',
        )['barcode'],
      );
      expect(r['isWinning'], isTrue);
      expect(r['prize'], 500.0);
      // Box 112 vs 123 should lose
      r = await app.validateTicket(
        tickets.firstWhere(
          (e) => e['numbers'] == '1,1,2' && e['betType'] == 'Box',
        )['barcode'],
      );
      expect(r['isWinning'], isFalse);
      // Box 123 vs 123 should win 80
      r = await app.validateTicket(
        tickets.firstWhere(
          (e) => e['numbers'] == '1,2,3' && e['betType'] == 'Box',
        )['barcode'],
      );
      expect(r['isWinning'], isTrue);
      expect(r['prize'], 80.0);
      // Combo 112 with winning 123 should lose, but our combo is 112 vs 123 -> lose
      // For combo test create separate draw
    });

    test('Box permutation wins - 0 handling', () async {
      await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_evening',
        drawName: 'Evening',
        numbers: ['0', '1', '2'],
        betType: 'Box',
        amount: 1.0,
        isQuickPick: false,
      );
      await app.processDrawResult(
        drawId: 'draw_evening',
        winningNumbers: ['2', '1', '0'],
      ); // permutation
      final t = (await db.getTickets()).firstWhere(
        (e) => e['numbers'] == '0,1,2',
      );
      final res = await app.validateTicket(t['barcode']);
      expect(res['isWinning'], isTrue);
      expect(res['prize'], 80.0); // 6-way
    });

    test('Straight does NOT allow permutation', () async {
      await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_evening',
        drawName: 'Evening',
        numbers: ['1', '2', '3'],
        betType: 'Straight',
        amount: 1.0,
        isQuickPick: false,
      );
      await app.processDrawResult(
        drawId: 'draw_evening',
        winningNumbers: ['3', '2', '1'],
      );
      final t = (await db.getTickets()).first;
      final res = await app.validateTicket(t['barcode']);
      expect(res['isWinning'], isFalse);
    });

    test('Win 4 all Box types', () async {
      // 4-way 1112, 6-way 1122, 12-way 1123, 24-way 1234, straight 0123
      final t1 = await app.createTicket(
        gameId: 'g_winz',
        gameName: 'Win 4',
        drawId: 'draw_win4_midday',
        drawName: 'Win4 Midday',
        numbers: ['1', '1', '1', '2'],
        betType: 'Box',
        amount: 1.0,
        isQuickPick: false,
      );
      await app.createTicket(
        gameId: 'g_winz',
        gameName: 'Win 4',
        drawId: 'draw_win4_midday',
        drawName: 'Win4 Midday',
        numbers: ['1', '1', '2', '2'],
        betType: 'Box',
        amount: 1.0,
        isQuickPick: false,
      );
      await app.createTicket(
        gameId: 'g_winz',
        gameName: 'Win 4',
        drawId: 'draw_win4_midday',
        drawName: 'Win4 Midday',
        numbers: ['1', '1', '2', '3'],
        betType: 'Box',
        amount: 1.0,
        isQuickPick: false,
      );
      await app.createTicket(
        gameId: 'g_winz',
        gameName: 'Win 4',
        drawId: 'draw_win4_midday',
        drawName: 'Win4 Midday',
        numbers: ['1', '2', '3', '4'],
        betType: 'Box',
        amount: 1.0,
        isQuickPick: false,
      );
      await app.createTicket(
        gameId: 'g_winz',
        gameName: 'Win 4',
        drawId: 'draw_win4_midday',
        drawName: 'Win4 Midday',
        numbers: ['0', '1', '2', '3'],
        betType: 'Straight',
        amount: 1.0,
        isQuickPick: false,
      );
      await app.processDrawResult(
        drawId: 'draw_win4_midday',
        winningNumbers: ['1', '1', '1', '2'],
      ); // only first wins
      var r = await app.validateTicket(t1['barcode']);
      expect(r['isWinning'], isTrue);
      expect(r['prize'], 1200.0);
      // Reset and test permutation still wins
      await db.resetDrawTickets('draw_win4_midday');
      await app.processDrawResult(
        drawId: 'draw_win4_midday',
        winningNumbers: ['2', '1', '1', '1'],
      ); // permutation of 1112 should still win 1200
      r = await app.validateTicket(t1['barcode']);
      expect(r['isWinning'], isTrue);
      expect(r['prize'], 1200.0);
    });

    test('Replacement demotes winner to loser', () async {
      await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_midday',
        drawName: 'Midday',
        numbers: ['1', '2', '3'],
        betType: 'Straight',
        amount: 1.0,
        isQuickPick: false,
      );
      await app.processDrawResult(
        drawId: 'draw_midday',
        winningNumbers: ['1', '2', '3'],
      );
      var t = (await db.getTickets()).first;
      expect(t['status'], 'winning');
      // Replace with different number
      await app.processDrawResult(
        drawId: 'draw_midday',
        winningNumbers: ['9', '9', '9'],
      );
      t = (await db.getTickets()).first;
      expect(t['status'], 'losing');
    });

    test('Combo cost validation - amount must be divisible', () async {
      // الجديد: المبلغ هو الإجمالي المطلوب دفعه ويتوزع على التركيبات — $1.00 مسموح حتى لـ 6-way (perCombo = 1/6)
      final t1 = await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_midday',
        drawName: 'Midday',
        numbers: ['1', '2', '3'],
        betType: 'Combo',
        amount: 1.0,
        isQuickPick: false,
      );
      expect(t1['amount'], 1.0);
      // لكن المبلغ يجب أن يكون بخطوات $0.50 — $1.25 مرفوض
      try {
        await app.createTicket(
          gameId: 'g_numbers',
          gameName: 'Numbers',
          drawId: 'draw_midday',
          drawName: 'Midday',
          numbers: ['1', '2', '3'],
          betType: 'Combo',
          amount: 1.25,
          isQuickPick: false,
        );
        fail('Should have thrown for \$0.50 steps');
      } catch (e) {
        expect(e.toString(), contains('0.50'));
      }
      // Valid combo 6-way with $6 should succeed
      final t = await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_midday',
        drawName: 'Midday',
        numbers: ['1', '2', '3'],
        betType: 'Combo',
        amount: 6.0,
        isQuickPick: false,
      );
      expect(t['amount'], 6.0);
    });

    test('Settings change affects prize', () async {
      await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_midday',
        drawName: 'Midday',
        numbers: ['1', '2', '3'],
        betType: 'Straight',
        amount: 1.0,
        isQuickPick: false,
      );
      // Change multiplier
      await db.upsertConfig('numbers_straight', '600', 'local');
      await app.processDrawResult(
        drawId: 'draw_midday',
        winningNumbers: ['1', '2', '3'],
      );
      final t = (await db.getTickets()).first;
      final res = await app.validateTicket(t['barcode']);
      expect(res['prize'], 600.0);
    });

    test('Cash and Balance per operator', () async {
      await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_midday',
        drawName: 'Midday',
        numbers: ['1', '2', '3'],
        betType: 'Straight',
        amount: 2.0,
        isQuickPick: false,
      );
      double cash = await app.computeCashBalance();
      double bal = await app.computeGeneralBalance();
      expect(cash, 2.0);
      expect(bal, 2.0);
      // Win and pay
      await app.processDrawResult(
        drawId: 'draw_midday',
        winningNumbers: ['1', '2', '3'],
      );
      final t = (await db.getTickets()).first;
      final prize = 2.0 * 500; // 1000
      await app.payWinningTicket(t['id'], prize);
      cash = await app.computeCashBalance();
      expect(cash, 2.0 - 1000); // negative cash allowed
      // Duplicate pay blocked
      final ok2 = await app.payWinningTicket(t['id'], prize);
      expect(ok2, isFalse);
    });

    test('Draw period Midday/Evening exists', () async {
      final draws = await db.getAllDraws();
      final hasMidday = draws.any(
        (d) => (d['name'] as String).contains('Midday'),
      );
      final hasEvening = draws.any(
        (d) => (d['name'] as String).contains('Evening'),
      );
      expect(hasMidday, isTrue);
      expect(hasEvening, isTrue);
    });

    test('Evening cart line stays Evening — not Midday', () async {
      await app.addToCart(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawType: 'EVENING',
        numbers: ['4', '5', '6'],
        betType: 'Straight',
        amount: 1.0,
      );
      expect(app.cart, hasLength(1));
      final item = app.cart.single;
      expect(item.drawType, 'EVENING');
      expect(item.periodId, contains('EVENING'));
      expect(item.drawName!.toLowerCase(), contains('evening'));
      expect(item.drawName, isNot(contains('Midday')));
      expect(item.drawId, isNot('draw_midday'));
    });

    test('Midday cart line stays Midday', () async {
      await app.addToCart(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawType: 'MIDDAY',
        numbers: ['7', '8', '9'],
        betType: 'Straight',
        amount: 1.0,
      );
      expect(app.cart, hasLength(1));
      final item = app.cart.single;
      expect(item.drawType, 'MIDDAY');
      expect(item.periodId, contains('MIDDAY'));
      expect(item.drawName, isNot(contains('Evening')));
    });

    test('Both cart creates Midday and Evening lines', () async {
      await app.addBothToCart(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        numbers: ['1', '2', '3'],
        betType: 'Straight',
        amountPerDraw: 1.0,
      );
      expect(app.cart, hasLength(2));
      final types = app.cart.map((e) => e.drawType).toSet();
      expect(types, containsAll(['MIDDAY', 'EVENING']));
      expect(
        app.cart.any(
          (e) =>
              (e.drawName ?? '').contains('Evening') ||
              (e.periodId ?? '').contains('EVENING'),
        ),
        isTrue,
      );
      expect(
        app.cart.any(
          (e) =>
              (e.drawName ?? '').contains('Midday') ||
              (e.periodId ?? '').contains('MIDDAY'),
        ),
        isTrue,
      );
    });

    test('Closed midday cannot be played and Both is blocked', () async {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final middayId = '$dateStr-MIDDAY';
      final eveningId = '$dateStr-EVENING';
      await db.ensurePeriodExists(middayId);
      await db.ensurePeriodExists(eveningId);
      final past = now
          .subtract(const Duration(minutes: 5))
          .millisecondsSinceEpoch;
      final later = now.add(const Duration(hours: 8)).millisecondsSinceEpoch;
      await db.customStatement(
        "UPDATE draw_periods SET salesCloseTime=$past, status='SALES_CLOSED' WHERE drawType='MIDDAY'",
      );
      await db.customStatement(
        "UPDATE draw_periods SET salesOpenTime=0, salesCloseTime=$later, drawTime=$later, status='OPEN' WHERE drawType='EVENING'",
      );

      await expectLater(
        app.addToCart(
          gameId: 'g_numbers',
          gameName: 'Numbers',
          drawType: 'MIDDAY',
          numbers: ['1', '2', '3'],
          betType: 'Straight',
          amount: 1.0,
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        app.addBothToCart(
          gameId: 'g_numbers',
          gameName: 'Numbers',
          numbers: ['1', '2', '3'],
          betType: 'Straight',
          amountPerDraw: 1.0,
        ),
        throwsA(isA<Exception>()),
      );
      await app.addToCart(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawType: 'EVENING',
        numbers: ['1', '2', '3'],
        betType: 'Straight',
        amount: 1.0,
      );
      expect(app.cart, hasLength(1));
      expect(app.cart.single.drawType, 'EVENING');
    });

    test('Print data contains required fields', () async {
      final t = await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_midday',
        drawName: 'Numbers Midday - 02:30 PM',
        numbers: ['0', '1', '2'],
        betType: 'Box',
        amount: 1.5,
        isQuickPick: true,
      );
      expect(t['serialNumber'], isNotNull);
      expect(t['barcode'], isNotNull);
      expect(t['drawName'], contains('Midday'));
      // Simulate print pdf creation would use these fields
      final required = [
        'id',
        'serialNumber',
        'gameName',
        'betType',
        'numbers',
        'drawName',
        'amount',
        'operatorName',
        'barcode',
      ];
      for (final k in required)
        expect(t.containsKey(k), isTrue, reason: 'missing $k');
    });

    test('0 digit allowed everywhere', () async {
      await app.createTicket(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawId: 'draw_midday',
        drawName: 'Midday',
        numbers: ['0', '0', '0'],
        betType: 'Straight',
        amount: 1.0,
        isQuickPick: false,
      );
      await app.processDrawResult(
        drawId: 'draw_midday',
        winningNumbers: ['0', '0', '0'],
      );
      final t = (await db.getTickets()).firstWhere(
        (e) => e['numbers'] == '0,0,0',
      );
      final res = await app.validateTicket(t['barcode']);
      expect(res['isWinning'], isTrue);
      expect(res['prize'], 500.0);
    });
  });
}
