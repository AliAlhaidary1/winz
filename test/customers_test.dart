import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:winz/src/data/database.dart';
import 'package:winz/src/providers/app_state.dart';

void main() {
  group('Registered customers', () {
    late AppDatabase db;
    late AppState app;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();
      app = AppState(db);
      expect(await app.login('admin', 'admin123'), isTrue);
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final later = now.add(const Duration(hours: 12)).millisecondsSinceEpoch;
      await db.customStatement(
        "UPDATE draw_periods SET salesOpenTime=0, salesCloseTime=$later, drawTime=$later, status='OPEN' WHERE drawDate='$dateStr'",
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('default customer exists and is used for walk-in sales', () async {
      final customers = await app.getCustomers();
      expect(
        customers.any((c) => c['id'] == AppState.defaultCustomerId),
        isTrue,
      );
      expect(app.currentCustomer['id'], AppState.defaultCustomerId);
    });

    test('save routine, replay it, print name, then delete safely', () async {
      final id = await app.addCustomer(name: 'Ali', phone: '123456');
      await app.selectCustomer(id);

      await app.addToCart(
        gameId: 'g_numbers',
        gameName: 'Numbers',
        drawType: 'MIDDAY',
        numbers: const ['1', '2', '3'],
        betType: 'Straight',
        amount: 1.0,
      );
      expect(await app.saveCartAsCustomerPlays(id), 1);
      app.clearCart();

      final replay = await app.playCustomerUsual(id);
      expect(replay['added'], 1);
      expect(app.currentCustomer['id'], id);

      final ticket = await app.commitSale();
      expect(ticket['customerId'], id);
      expect(ticket['customerName'], 'Ali');

      await app.deleteCustomer(id);
      final stored = await db.getTicketById(ticket['id'] as String);
      expect(stored?['customerId'], AppState.defaultCustomerId);
      expect(app.currentCustomer['id'], AppState.defaultCustomerId);
    });
  });
}
