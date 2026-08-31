import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// ignore: unused_import
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart' as s3lib;

class AppDatabase extends GeneratedDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 6;

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'yelottery.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await _createAll(customStatement);
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await customStatement('ALTER TABLE tickets ADD COLUMN serialNumber TEXT');
          }
          if (from < 3) {
            await customStatement("UPDATE app_config SET value='USD' WHERE key='currency'");
            await customStatement("UPDATE app_config SET value='en-US' WHERE key='language'");
            await customStatement("UPDATE app_config SET value='NY Lottery POS' WHERE key='company_name'");
            await customStatement("UPDATE app_config SET value='Good luck! Please play responsibly.' WHERE key='ticket_footer'");
            await customStatement("UPDATE games SET minAmount=0.5, maxAmount=10, numberRangeMin=1, numberRangeMax=9, description='NY Lottery style: Pick 3/4 using keypad 1-9' WHERE id='g_numbers'");
            await customStatement("UPDATE games SET minAmount=1, maxAmount=20, numberRangeMin=1, numberRangeMax=9, description='NY Lottery style Winz' WHERE id='g_winz'");
          }
          if (from < 4) {
            final now = DateTime.now().millisecondsSinceEpoch;
            await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('straight_3d_multiplier', '500', 'local', $now)");
            await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('straight_4d_multiplier', '5000', 'local', $now)");
            await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('box_3d_multiplier', '80', 'local', $now)");
            await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('box_4d_multiplier', '400', 'local', $now)");
            await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('winz_std_multiplier', '10', 'local', $now)");
            await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('winz_jackpot_multiplier', '100', 'local', $now)");
            await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('winz_instant_multiplier', '5', 'local', $now)");
          }
          if (from < 5) {
            final now = DateTime.now().millisecondsSinceEpoch;
            // NY Lottery الرسمي — Numbers (Pick3)
            await customStatement("UPDATE app_config SET value='500', updatedAt=$now WHERE key='straight_multiplier'");
            await customStatement("INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_straight', '500', 'local', $now)");
            await customStatement("INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_box_3way', '160', 'local', $now)");
            await customStatement("INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_box_6way', '80', 'local', $now)");
            await customStatement("INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_strbox_3way_exact', '330', 'local', $now)");
            await customStatement("INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_strbox_6way_exact', '290', 'local', $now)");
            await customStatement("INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_front_pair', '50', 'local', $now)");
            await customStatement("INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_back_pair', '50', 'local', $now)");
            // NY Win 4 (Pick4) — Winz
            await customStatement("INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_straight', '5000', 'local', $now)");
            await customStatement("INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_4way', '1200', 'local', $now)");
            await customStatement("INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_6way', '800', 'local', $now)");
            await customStatement("INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_12way', '400', 'local', $now)");
            await customStatement("INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_24way', '200', 'local', $now)");
            await customStatement("UPDATE app_config SET value='500', updatedAt=$now WHERE key='straight_3d_multiplier'");
            await customStatement("UPDATE app_config SET value='5000', updatedAt=$now WHERE key='straight_4d_multiplier'");
            await customStatement("UPDATE app_config SET value='160', updatedAt=$now WHERE key='box_3d_multiplier'"); // 3-Way
          }
          if (from < 6) {
            final now = DateTime.now().millisecondsSinceEpoch;
            // Fix 0-9 range and payouts — NY الرسمي 0-9
            await customStatement("UPDATE games SET numberRangeMin=0, numberRangeMax=9, minAmount=0.5, maxAmount=10, description='NY Lottery Pick 3 (0-9) — Straight/Box/Combo/StrBox/Pairs' WHERE id='g_numbers'");
            await customStatement("UPDATE games SET numberRangeMin=0, numberRangeMax=9, minAmount=0.5, maxAmount=10, description='NY Lottery Win 4 (0-9) — 4 digits Straight/Box/Combo' WHERE id='g_winz'");
            await customStatement("UPDATE app_config SET value='1200', updatedAt=$now WHERE key='win4_box_4way'");
            await customStatement("UPDATE app_config SET value='1200', updatedAt=$now WHERE key='box_4d_multiplier'");
          }
        },
        beforeOpen: (details) async {
          await _createAll(customStatement);
          await _seedIfEmpty();
          final now = DateTime.now().millisecondsSinceEpoch;
          await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('straight_3d_multiplier', '500', 'local', $now)");
          await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('straight_4d_multiplier', '5000', 'local', $now)");
          await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('box_3d_multiplier', '160', 'local', $now)");
          await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('box_4d_multiplier', '400', 'local', $now)");
          await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('winz_std_multiplier', '10', 'local', $now)");
          await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('winz_jackpot_multiplier', '100', 'local', $now)");
          await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('winz_instant_multiplier', '5', 'local', $now)");
          // NY exact
          await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_straight', '500', 'local', $now)");
          await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_box_3way', '160', 'local', $now)");
          await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_box_6way', '80', 'local', $now)");
          await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_straight', '5000', 'local', $now)");
          await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_4way', '1200', 'local', $now)");
          await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_6way', '800', 'local', $now)");
          await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_12way', '400', 'local', $now)");
          await customStatement("INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_24way', '200', 'local', $now)");
          // Ensure 0-9 and 1200 fix on every open (for existing installs)
          await customStatement("UPDATE games SET numberRangeMin=0, numberRangeMax=9 WHERE id IN ('g_numbers','g_winz')");
          await customStatement("UPDATE app_config SET value='1200' WHERE key='win4_box_4way' AND value='1198'");
        },
      );

  Future<void> _createAll(Future<void> Function(String) exec) async {
    await exec('''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        role TEXT NOT NULL,
        status TEXT NOT NULL,
        createdAt INTEGER NOT NULL
      )
    ''');
    await exec('''
      CREATE TABLE IF NOT EXISTS games (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        description TEXT,
        minAmount REAL NOT NULL,
        maxAmount REAL NOT NULL,
        maxSelections INTEGER NOT NULL,
        numberRangeMin INTEGER NOT NULL,
        numberRangeMax INTEGER NOT NULL
      )
    ''');
    await exec('''
      CREATE TABLE IF NOT EXISTS draws (
        id TEXT PRIMARY KEY,
        gameId TEXT NOT NULL,
        name TEXT NOT NULL,
        drawTime INTEGER NOT NULL,
        status TEXT NOT NULL,
        winningNumbers TEXT,
        FOREIGN KEY (gameId) REFERENCES games(id)
      )
    ''');
    await exec('''
      CREATE TABLE IF NOT EXISTS tickets (
        id TEXT PRIMARY KEY,
        serialNumber TEXT,
        gameId TEXT NOT NULL,
        gameName TEXT NOT NULL,
        drawId TEXT,
        drawName TEXT,
        numbers TEXT NOT NULL,
        betType TEXT NOT NULL,
        amount REAL NOT NULL,
        total REAL NOT NULL,
        operatorId TEXT NOT NULL,
        operatorName TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        status TEXT NOT NULL,
        barcode TEXT,
        prizeAmount REAL,
        paidAt INTEGER,
        paidBy TEXT,
        isQuickPick INTEGER NOT NULL DEFAULT 0,
        drawDate INTEGER
      )
    ''');
    await exec('''
      CREATE TABLE IF NOT EXISTS cash_ledger (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        direction TEXT NOT NULL,
        description TEXT,
        operatorId TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        ticketId TEXT
      )
    ''');
    await exec('''
      CREATE TABLE IF NOT EXISTS balance_movements (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        direction TEXT NOT NULL,
        description TEXT,
        operatorId TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        ticketId TEXT
      )
    ''');
    await exec('''
      CREATE TABLE IF NOT EXISTS cash_sessions (
        id TEXT PRIMARY KEY,
        operatorId TEXT NOT NULL,
        openingAmount REAL NOT NULL,
        closingAmount REAL,
        openedAt INTEGER NOT NULL,
        closedAt INTEGER,
        status TEXT NOT NULL
      )
    ''');
    await exec('''
      CREATE TABLE IF NOT EXISTS app_config (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        scope TEXT NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _seedIfEmpty() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // تأكد أن الحسابات موجودة دائماً — حتى بعد التحديث (نسخ مطابق NY)
    await customStatement(
        "INSERT OR IGNORE INTO accounts (id, username, password, role, status, createdAt) VALUES ('acc_admin', 'admin', 'admin123', 'admin', 'active', $now)");
    await customStatement(
        "INSERT OR IGNORE INTO accounts (id, username, password, role, status, createdAt) VALUES ('acc_agent1', 'agent1', 'agent123', 'agent', 'active', $now)");
    await customStatement(
        "INSERT OR IGNORE INTO accounts (id, username, password, role, status, createdAt) VALUES ('acc_cashier', 'cashier', 'cashier123', 'cashier', 'active', $now)");
    // إصلاح كلمات مرور قديمة لو تغيرت
    await customStatement("UPDATE accounts SET password='admin123', status='active' WHERE username='admin'");
    await customStatement("UPDATE accounts SET password='agent123', status='active' WHERE username='agent1'");
    await customStatement("UPDATE accounts SET password='cashier123', status='active' WHERE username='cashier'");
    // إصلاح فوري للأجهزة القديمة: 0-9
    await customStatement("UPDATE games SET numberRangeMin=0, numberRangeMax=9, description='NY Lottery Pick 3 (0-9) — Straight/Box/Combo/StrBox/Pairs' WHERE id='g_numbers' AND numberRangeMin!=0");
    await customStatement("UPDATE games SET numberRangeMin=0, numberRangeMax=9, description='NY Lottery Win 4 (0-9) — 4 digits Straight/Box/Combo' WHERE id='g_winz' AND numberRangeMin!=0");
    final games = await customSelect('SELECT COUNT(*) as c FROM games').getSingle();
    if ((games.data['c'] as int) == 0) {
      await customStatement(
          "INSERT INTO games (id, name, type, description, minAmount, maxAmount, maxSelections, numberRangeMin, numberRangeMax) VALUES ('g_numbers', 'Numbers', 'numbers', 'NY Lottery Pick 3 (0-9) — Straight/Box/Combo/StrBox/Pairs', 0.5, 10, 5, 0, 9)");
      await customStatement(
          "INSERT INTO games (id, name, type, description, minAmount, maxAmount, maxSelections, numberRangeMin, numberRangeMax) VALUES ('g_winz', 'Win 4', 'winz', 'NY Lottery Win 4 (0-9) — 4 digits Straight/Box/Combo', 0.5, 10, 4, 0, 9)");
    }
    // Ensure games always correct even if existed
    await customStatement("UPDATE games SET name='Win 4', type='winz', maxSelections=4, minAmount=0.5, maxAmount=10, numberRangeMin=0, numberRangeMax=9, description='NY Lottery Win 4 (0-9) — 4 digits Straight/Box/Combo' WHERE id='g_winz'");
    await customStatement("UPDATE games SET name='Numbers', maxSelections=5, minAmount=0.5, maxAmount=10, numberRangeMin=0, numberRangeMax=9 WHERE id='g_numbers'");
    // Morning / Evening only — as requested (2 draws per day, 14 days)
    final draws = await customSelect('SELECT COUNT(*) as c FROM draws').getSingle();
    DateTime morning(DateTime base) => DateTime(base.year, base.month, base.day, 10, 0);
    DateTime evening(DateTime base) => DateTime(base.year, base.month, base.day, 20, 0);
    final periods = [(morning, 'Morning'), (evening, 'Evening')];
    if ((draws.data['c'] as int) == 0) {
      final now = DateTime.now();
      for (var i = 0; i < 14; i++) {
        final base = now.add(Duration(days: i));
        for (final entry in periods) {
          final dt = entry.$1(base);
          final label = entry.$2;
          final id = 'draw_numbers_${label.toLowerCase()}_${base.year}${base.month.toString().padLeft(2,'0')}${base.day.toString().padLeft(2,'0')}';
          final name = 'Numbers $label - ${dt.month.toString().padLeft(2,'0')}/${dt.day.toString().padLeft(2,'0')} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
          await customStatement(
              "INSERT OR IGNORE INTO draws (id, gameId, name, drawTime, status) VALUES ('$id', 'g_numbers', '$name', ${dt.millisecondsSinceEpoch}, 'open')");
        }
      }
      for (var i = 0; i < 14; i++) {
        final base = now.add(Duration(days: i));
        for (final entry in periods) {
          final dt = entry.$1(base);
          final label = entry.$2;
          final id = 'draw_win4_${label.toLowerCase()}_${base.year}${base.month.toString().padLeft(2,'0')}${base.day.toString().padLeft(2,'0')}';
          final name = 'Win 4 $label - ${dt.month.toString().padLeft(2,'0')}/${dt.day.toString().padLeft(2,'0')} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
          await customStatement(
              "INSERT OR IGNORE INTO draws (id, gameId, name, drawTime, status) VALUES ('$id', 'g_winz', '$name', ${dt.millisecondsSinceEpoch}, 'open')");
        }
      }
    } else {
      // For existing DBs: ensure next 14 days draws exist
      final now = DateTime.now();
      for (var i = 0; i < 14; i++) {
        final base = now.add(Duration(days: i));
        for (final entry in periods) {
          final dt = entry.$1(base);
          final label = entry.$2;
          final idN = 'draw_numbers_${label.toLowerCase()}_${base.year}${base.month.toString().padLeft(2,'0')}${base.day.toString().padLeft(2,'0')}';
          final nameN = 'Numbers $label - ${dt.month.toString().padLeft(2,'0')}/${dt.day.toString().padLeft(2,'0')} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
          await customStatement("INSERT OR IGNORE INTO draws (id, gameId, name, drawTime, status) VALUES ('$idN', 'g_numbers', '$nameN', ${dt.millisecondsSinceEpoch}, 'open')");
          final idW = 'draw_win4_${label.toLowerCase()}_${base.year}${base.month.toString().padLeft(2,'0')}${base.day.toString().padLeft(2,'0')}';
          final nameW = 'Win 4 $label - ${dt.month.toString().padLeft(2,'0')}/${dt.day.toString().padLeft(2,'0')} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
          await customStatement("INSERT OR IGNORE INTO draws (id, gameId, name, drawTime, status) VALUES ('$idW', 'g_winz', '$nameW', ${dt.millisecondsSinceEpoch}, 'open')");
        }
      }
    }
    // Cleanup old Night/Midday draws to keep only Morning/Evening
    await customStatement("DELETE FROM draws WHERE name LIKE '%Night%'");
    await customStatement("UPDATE draws SET name = REPLACE(name, 'Midday', 'Morning') WHERE name LIKE '%Midday%'");
    final configs = await customSelect('SELECT COUNT(*) as c FROM app_config').getSingle();
    if ((configs.data['c'] as int) == 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('printer_type', 'thermal_58mm', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('printer_connection', 'bluetooth', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('currency', 'USD', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('language', 'en-US', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('ticket_footer', 'Good luck! Please play responsibly.', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('company_name', 'NY Lottery POS', 'server', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('straight_multiplier', '500', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('box_multiplier', '80', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('combo_multiplier', '500', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('straight_3d_multiplier', '500', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('straight_4d_multiplier', '5000', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('box_3d_multiplier', '160', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('box_4d_multiplier', '400', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_straight', '500', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_box_3way', '160', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_box_6way', '80', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('win4_straight', '5000', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_4way', '1200', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_6way', '800', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_12way', '400', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_24way', '200', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('winz_std_multiplier', '10', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('winz_jackpot_multiplier', '100', 'local', $now)");
      await customStatement(
          "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('winz_instant_multiplier', '5', 'local', $now)");
    }
  }

  // Helpers
  Future<List<Map<String, dynamic>>> getAccounts() async {
    final rows = await customSelect('SELECT * FROM accounts ORDER BY username').get();
    return rows.map((r) => r.data).toList();
  }

  Future<Map<String, dynamic>?> findAccount(String username, String password) async {
    final rows = await customSelect(
      'SELECT * FROM accounts WHERE username = ? AND password = ? LIMIT 1',
      variables: [Variable.withString(username), Variable.withString(password)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.data;
  }

  Future<List<Map<String, dynamic>>> getGames() async {
    final rows = await customSelect('SELECT * FROM games').get();
    return rows.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getDrawsByGame(String gameId) async {
    final rows = await customSelect(
      'SELECT * FROM draws WHERE gameId = ? ORDER BY drawTime',
      variables: [Variable.withString(gameId)],
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getAllDraws() async {
    final rows = await customSelect('SELECT * FROM draws ORDER BY drawTime DESC').get();
    return rows.map((r) => r.data).toList();
  }

  Future<Map<String, dynamic>?> getDrawById(String id) async {
    final rows = await customSelect('SELECT * FROM draws WHERE id = ? LIMIT 1',
        variables: [Variable.withString(id)]).get();
    if (rows.isEmpty) return null;
    return rows.first.data;
  }

  Future<void> updateDrawResult(String id, String winningNumbers) async {
    await customStatement(
        "UPDATE draws SET winningNumbers = ?, status = 'closed' WHERE id = ?",
        [winningNumbers, id]);
  }

  Future<void> insertTicket(Map<String, dynamic> t) async {
    await customStatement('''
      INSERT OR REPLACE INTO tickets
      (id, serialNumber, gameId, gameName, drawId, drawName, numbers, betType, amount, total, operatorId, operatorName, createdAt, status, barcode, prizeAmount, paidAt, paidBy, isQuickPick)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      t['id'], t['serialNumber'], t['gameId'], t['gameName'], t['drawId'], t['drawName'], t['numbers'], t['betType'], t['amount'], t['total'],
      t['operatorId'], t['operatorName'], t['createdAt'], t['status'], t['barcode'], t['prizeAmount'], t['paidAt'], t['paidBy'], t['isQuickPick'] ?? 0
    ]);
  }

  Future<List<Map<String, dynamic>>> getTickets({String? status}) async {
    final where = status != null ? 'WHERE status = ?' : '';
    final vars = status != null ? [Variable.withString(status)] : <Variable>[];
    final rows = await customSelect('SELECT * FROM tickets $where ORDER BY createdAt DESC', variables: vars).get();
    return rows.map((r) => r.data).toList();
  }

  Future<Map<String, dynamic>?> getTicketById(String id) async {
    final rows = await customSelect('SELECT * FROM tickets WHERE id = ? LIMIT 1',
        variables: [Variable.withString(id)]).get();
    if (rows.isEmpty) return null;
    return rows.first.data;
  }

  Future<Map<String, dynamic>?> getTicketByBarcode(String barcode) async {
    final rows = await customSelect('SELECT * FROM tickets WHERE barcode = ? OR id = ? OR serialNumber = ? LIMIT 1',
        variables: [Variable.withString(barcode), Variable.withString(barcode), Variable.withString(barcode)]).get();
    if (rows.isEmpty) return null;
    return rows.first.data;
  }

  Future<void> updateTicketStatus(String id, String status, {double? prizeAmount, int? paidAt, String? paidBy}) async {
    await customStatement('UPDATE tickets SET status = ?, prizeAmount = COALESCE(?, prizeAmount), paidAt = COALESCE(?, paidAt), paidBy = COALESCE(?, paidBy) WHERE id = ?',
        [status, prizeAmount, paidAt, paidBy, id]);
  }

  Future<void> insertCashLedger(Map<String, dynamic> e) async {
    await customStatement(
        'INSERT INTO cash_ledger (id, type, amount, direction, description, operatorId, createdAt, ticketId) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [e['id'], e['type'], e['amount'], e['direction'], e['description'], e['operatorId'], e['createdAt'], e['ticketId']]);
  }

  Future<void> insertBalanceMovement(Map<String, dynamic> e) async {
    await customStatement(
        'INSERT INTO balance_movements (id, type, amount, direction, description, operatorId, createdAt, ticketId) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [e['id'], e['type'], e['amount'], e['direction'], e['description'], e['operatorId'], e['createdAt'], e['ticketId']]);
  }

  Future<List<Map<String, dynamic>>> getCashLedger() async {
    final rows = await customSelect('SELECT * FROM cash_ledger ORDER BY createdAt DESC').get();
    return rows.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getBalanceMovements() async {
    final rows = await customSelect('SELECT * FROM balance_movements ORDER BY createdAt DESC').get();
    return rows.map((r) => r.data).toList();
  }

  Future<Map<String, dynamic>?> getOpenCashSession(String operatorId) async {
    final rows = await customSelect(
        "SELECT * FROM cash_sessions WHERE operatorId = ? AND status = 'open' LIMIT 1",
        variables: [Variable.withString(operatorId)]).get();
    if (rows.isEmpty) return null;
    return rows.first.data;
  }

  Future<void> insertCashSession(Map<String, dynamic> s) async {
    await customStatement(
        'INSERT INTO cash_sessions (id, operatorId, openingAmount, closingAmount, openedAt, closedAt, status) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [s['id'], s['operatorId'], s['openingAmount'], s['closingAmount'], s['openedAt'], s['closedAt'], s['status']]);
  }

  Future<void> closeCashSession(String id, double closingAmount, int closedAt) async {
    await customStatement("UPDATE cash_sessions SET closingAmount = ?, closedAt = ?, status = 'closed' WHERE id = ?",
        [closingAmount, closedAt, id]);
  }

  Future<List<Map<String, dynamic>>> getCashSessions() async {
    final rows = await customSelect('SELECT * FROM cash_sessions ORDER BY openedAt DESC').get();
    return rows.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getAppConfig() async {
    final rows = await customSelect('SELECT * FROM app_config').get();
    return rows.map((r) => r.data).toList();
  }

  Future<void> upsertConfig(String key, String value, String scope) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await customStatement(
        'INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES (?, ?, ?, ?)',
        [key, value, scope, now]);
  }

  Future<double> sumCash(String direction, {String? type, String? operatorId}) async {
    final typeWhere = type != null ? "AND type = '$type'" : '';
    final opWhere = operatorId != null ? "AND operatorId = ?" : '';
    final vars = <Variable>[
      Variable.withString(direction),
      if (operatorId != null) Variable.withString(operatorId),
    ];
    final row = await customSelect("SELECT COALESCE(SUM(amount),0) as s FROM cash_ledger WHERE direction = ? $typeWhere $opWhere",
            variables: vars)
        .getSingle();
    return (row.data['s'] as num).toDouble();
  }

  // Reset tickets for draw replacement (fix winning->losing bug)
  Future<void> resetDrawTickets(String drawId) async {
    await customStatement(
        "UPDATE tickets SET status='active', prizeAmount=NULL WHERE drawId = ? AND status IN ('winning','losing')",
        [drawId]);
  }

  // Operator-filtered ledger/balance for per-operator cash
  Future<List<Map<String, dynamic>>> getCashLedgerByOperator(String operatorId) async {
    final rows = await customSelect('SELECT * FROM cash_ledger WHERE operatorId = ? ORDER BY createdAt DESC',
            variables: [Variable.withString(operatorId)])
        .get();
    return rows.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getBalanceMovementsByOperator(String operatorId) async {
    final rows = await customSelect('SELECT * FROM balance_movements WHERE operatorId = ? ORDER BY createdAt DESC',
            variables: [Variable.withString(operatorId)])
        .get();
    return rows.map((r) => r.data).toList();
  }
}
