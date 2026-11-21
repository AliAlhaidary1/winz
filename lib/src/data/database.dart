import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// ignore: unused_import
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart' as s3lib;

import '../utils/timezone.dart';

class AppDatabase extends GeneratedDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 11;

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
        await customStatement(
          'ALTER TABLE tickets ADD COLUMN serialNumber TEXT',
        );
      }
      if (from < 3) {
        await customStatement(
          "UPDATE app_config SET value='USD' WHERE key='currency'",
        );
        await customStatement(
          "UPDATE app_config SET value='en-US' WHERE key='language'",
        );
        await customStatement(
          "UPDATE app_config SET value='NY Lottery POS' WHERE key='company_name'",
        );
        await customStatement(
          "UPDATE app_config SET value='' WHERE key='ticket_footer'",
        );
        await customStatement(
          "UPDATE games SET minAmount=0.5, maxAmount=10, numberRangeMin=1, numberRangeMax=9, description='NY Lottery style: Pick 3/4 using keypad 1-9' WHERE id='g_numbers'",
        );
        await customStatement(
          "UPDATE games SET minAmount=1, maxAmount=20, numberRangeMin=1, numberRangeMax=9, description='NY Lottery style Winz' WHERE id='g_winz'",
        );
      }
      if (from < 4) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('straight_3d_multiplier', '500', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('straight_4d_multiplier', '5000', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('box_3d_multiplier', '80', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('box_4d_multiplier', '400', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('winz_std_multiplier', '10', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('winz_jackpot_multiplier', '100', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('winz_instant_multiplier', '5', 'local', $now)",
        );
      }
      if (from < 5) {
        final now = DateTime.now().millisecondsSinceEpoch;
        // NY Lottery  — Numbers (Pick3)
        await customStatement(
          "UPDATE app_config SET value='500', updatedAt=$now WHERE key='straight_multiplier'",
        );
        await customStatement(
          "INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_straight', '500', 'local', $now)",
        );
        await customStatement(
          "INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_box_3way', '160', 'local', $now)",
        );
        await customStatement(
          "INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_box_6way', '80', 'local', $now)",
        );
        await customStatement(
          "INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_strbox_3way_exact', '330', 'local', $now)",
        );
        await customStatement(
          "INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_strbox_6way_exact', '290', 'local', $now)",
        );
        await customStatement(
          "INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_front_pair', '50', 'local', $now)",
        );
        await customStatement(
          "INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_back_pair', '50', 'local', $now)",
        );
        // NY Win 4 (Pick4) — Winz
        await customStatement(
          "INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_straight', '5000', 'local', $now)",
        );
        await customStatement(
          "INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_4way', '1200', 'local', $now)",
        );
        await customStatement(
          "INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_6way', '800', 'local', $now)",
        );
        await customStatement(
          "INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_12way', '400', 'local', $now)",
        );
        await customStatement(
          "INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_24way', '200', 'local', $now)",
        );
        await customStatement(
          "UPDATE app_config SET value='500', updatedAt=$now WHERE key='straight_3d_multiplier'",
        );
        await customStatement(
          "UPDATE app_config SET value='5000', updatedAt=$now WHERE key='straight_4d_multiplier'",
        );
        await customStatement(
          "UPDATE app_config SET value='160', updatedAt=$now WHERE key='box_3d_multiplier'",
        ); // 3-Way
      }
      if (from < 6) {
        final now = DateTime.now().millisecondsSinceEpoch;
        // Fix 0-9 range and payouts — NY  0-9
        await customStatement(
          "UPDATE games SET numberRangeMin=0, numberRangeMax=9, minAmount=0.5, maxAmount=10, description='NY Lottery Pick 3 (0-9) — Straight/Box/Combo/StrBox/Pairs' WHERE id='g_numbers'",
        );
        await customStatement(
          "UPDATE games SET numberRangeMin=0, numberRangeMax=9, minAmount=0.5, maxAmount=10, description='NY Lottery Win 4 (0-9) — 4 digits Straight/Box/Combo' WHERE id='g_winz'",
        );
        await customStatement(
          "UPDATE app_config SET value='1200', updatedAt=$now WHERE key='win4_box_4way'",
        );
        await customStatement(
          "UPDATE app_config SET value='1200', updatedAt=$now WHERE key='box_4d_multiplier'",
        );
      }
      if (from < 7) {
        await customStatement('''
              CREATE TABLE IF NOT EXISTS ticket_lines (
                id TEXT PRIMARY KEY,
                ticketId TEXT NOT NULL,
                gameId TEXT NOT NULL,
                gameName TEXT NOT NULL,
                drawId TEXT,
                drawName TEXT,
                numbers TEXT NOT NULL,
                betType TEXT NOT NULL,
                amount REAL NOT NULL,
                isQuickPick INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (ticketId) REFERENCES tickets(id)
              )
            ''');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_ticket_lines_ticketId ON ticket_lines(ticketId)',
        );
        // Migrate existing tickets to ticket_lines (one line per old ticket)
        // Use customSelect to iterate
        try {
          final rows = await customSelect(
            'SELECT id, gameId, gameName, drawId, drawName, numbers, betType, amount, isQuickPick FROM tickets',
          ).get();
          for (final r in rows) {
            final tid = r.data['id'] as String;
            final existing = await customSelect(
              'SELECT COUNT(*) as c FROM ticket_lines WHERE ticketId = ?',
              variables: [Variable.withString(tid)],
            ).getSingle();
            if ((existing.data['c'] as int) == 0) {
              final lineId = 'L${tid}';
              await customStatement(
                'INSERT OR IGNORE INTO ticket_lines (id, ticketId, gameId, gameName, drawId, drawName, numbers, betType, amount, isQuickPick) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                [
                  lineId,
                  tid,
                  r.data['gameId'],
                  r.data['gameName'],
                  r.data['drawId'],
                  r.data['drawName'],
                  r.data['numbers'],
                  r.data['betType'],
                  r.data['amount'],
                  r.data['isQuickPick'] ?? 0,
                ],
              );
            }
          }
        } catch (_) {}
      }
      if (from < 8) {
        await customStatement('''
              CREATE TABLE IF NOT EXISTS draw_periods (
                id TEXT PRIMARY KEY,
                drawType TEXT NOT NULL,
                drawDate TEXT NOT NULL,
                salesOpenTime INTEGER NOT NULL,
                salesCloseTime INTEGER NOT NULL,
                drawTime INTEGER NOT NULL,
                status TEXT NOT NULL,
                result TEXT,
                resultPublishedAt INTEGER,
                publishedBy TEXT,
                resultSource TEXT,
                timezone TEXT
              )
            ''');
        // Dual winners: 3-digit and 4-digit (added in v10, but ensure for fresh v8 DB)
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result3 TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result3PublishedAt INTEGER',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result3PublishedBy TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result3Source TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result4 TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result4PublishedAt INTEGER',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result4PublishedBy TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result4Source TEXT',
          );
        } catch (_) {}
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_draw_periods_date ON draw_periods(drawDate)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_draw_periods_type ON draw_periods(drawType)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_draw_periods_status ON draw_periods(status)',
        );
        await customStatement('''
              CREATE TABLE IF NOT EXISTS audit_logs (
                id TEXT PRIMARY KEY,
                user TEXT NOT NULL,
                action TEXT NOT NULL,
                periodId TEXT,
                oldValue TEXT,
                newValue TEXT,
                timestamp INTEGER NOT NULL,
                reason TEXT
              )
            ''');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_audit_period ON audit_logs(periodId)',
        );
        // Add periodId column to ticket_lines for spec compliance
        try {
          await customStatement(
            'ALTER TABLE ticket_lines ADD COLUMN periodId TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE ticket_lines ADD COLUMN periodStatus TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE ticket_lines ADD COLUMN winningStatus TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE ticket_lines ADD COLUMN prizeAmount REAL',
          );
        } catch (_) {}
        // Seed default draw config for new logic
        final now = DateTime.now().millisecondsSinceEpoch;
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('midday_sales_close', '14:15', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('midday_draw_time', '14:30', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('midday_enabled', '1', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('evening_sales_close', '22:20', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('evening_draw_time', '22:30', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('evening_enabled', '1', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('draw_timezone', 'America/New_York', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('midday_result_mode', 'manual', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('evening_result_mode', 'manual', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('auto_open_next', '1', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('winning_time_restricted', '1', 'local', $now)",
        );
        try {
          await customStatement(
            'ALTER TABLE accounts ADD COLUMN commission REAL DEFAULT 0',
          );
        } catch (_) {}
        // Migrate roles: only admin and worker
        await customStatement(
          "UPDATE accounts SET role='worker' WHERE role IN ('agent','cashier','worker')",
        );
        await customStatement(
          "UPDATE accounts SET commission=5.0 WHERE role='worker' AND (commission IS NULL OR commission=0)",
        );
      }
      if (from < 10) {
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result3 TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result3PublishedAt INTEGER',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result3PublishedBy TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result3Source TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result4 TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result4PublishedAt INTEGER',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result4PublishedBy TEXT',
          );
        } catch (_) {}
        try {
          await customStatement(
            'ALTER TABLE draw_periods ADD COLUMN result4Source TEXT',
          );
        } catch (_) {}
      }
      if (from < 11) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('backup_enabled', '1', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('backup_interval', 'daily', 'local', $now)",
        );
        await customStatement(
          "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('backup_retention', '10', 'local', $now)",
        );
      }
    },
    beforeOpen: (details) async {
      await _createAll(customStatement);
      await _seedIfEmpty();
      final now = DateTime.now().millisecondsSinceEpoch;
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('straight_3d_multiplier', '500', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('straight_4d_multiplier', '5000', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('box_3d_multiplier', '160', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('box_4d_multiplier', '400', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('winz_std_multiplier', '10', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('winz_jackpot_multiplier', '100', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('winz_instant_multiplier', '5', 'local', $now)",
      );
      // NY exact
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_straight', '500', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_box_3way', '160', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_box_6way', '80', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_straight', '5000', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_4way', '1200', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_6way', '800', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_12way', '400', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_24way', '200', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('winning_time_restricted', '1', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_straight_3', '100', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_straight_4', '10', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_box_3', '50', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_box_4', '50', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_combo_3', '100', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_combo_4', '10', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_strbox_3', '50', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_strbox_4', '50', 'local', $now)",
      );
      // Ensure 0-9 and 1200 fix on every open (for existing installs)
      await customStatement(
        "UPDATE games SET numberRangeMin=0, numberRangeMax=9 WHERE id IN ('g_numbers','g_winz')",
      );
      await customStatement(
        "UPDATE app_config SET value='1200' WHERE key='win4_box_4way' AND value='1198'",
      );
      // Clear ticket footer per user request — remove "Good luck..." message
      await customStatement(
        "UPDATE app_config SET value='' WHERE key='ticket_footer' AND value='Good luck! Please play responsibly.'",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('ticket_footer', '', 'local', $now)",
      );
      // Ensure dual winner columns exist for v10
      try {
        await customStatement(
          'ALTER TABLE draw_periods ADD COLUMN result3 TEXT',
        );
      } catch (_) {}
      try {
        await customStatement(
          'ALTER TABLE draw_periods ADD COLUMN result3PublishedAt INTEGER',
        );
      } catch (_) {}
      try {
        await customStatement(
          'ALTER TABLE draw_periods ADD COLUMN result3PublishedBy TEXT',
        );
      } catch (_) {}
      try {
        await customStatement(
          'ALTER TABLE draw_periods ADD COLUMN result3Source TEXT',
        );
      } catch (_) {}
      try {
        await customStatement(
          'ALTER TABLE draw_periods ADD COLUMN result4 TEXT',
        );
      } catch (_) {}
      try {
        await customStatement(
          'ALTER TABLE draw_periods ADD COLUMN result4PublishedAt INTEGER',
        );
      } catch (_) {}
      try {
        await customStatement(
          'ALTER TABLE draw_periods ADD COLUMN result4PublishedBy TEXT',
        );
      } catch (_) {}
      try {
        await customStatement(
          'ALTER TABLE draw_periods ADD COLUMN result4Source TEXT',
        );
      } catch (_) {}
      // Migrate legacy single result into result3/result4 if applicable (heuristic: length)
      try {
        final legacy = await customSelect(
          "SELECT id, result FROM draw_periods WHERE result IS NOT NULL AND result != '' AND (result3 IS NULL OR result3='') AND (result4 IS NULL OR result4='')",
        ).get();
        for (final r in legacy) {
          final res = (r.data['result'] as String).trim();
          if (res.length == 3) {
            await customStatement(
              "UPDATE draw_periods SET result3 = ? WHERE id = ?",
              [res, r.data['id']],
            );
          } else if (res.length == 4) {
            await customStatement(
              "UPDATE draw_periods SET result4 = ? WHERE id = ?",
              [res, r.data['id']],
            );
          }
        }
      } catch (_) {}
      // Ensure backup defaults (v11)
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('backup_enabled', '1', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('backup_interval', 'daily', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('backup_retention', '10', 'local', $now)",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('client_commission_rate', '20', 'local', $now)",
      );
    },
  );

  Future<void> _createAll(Future<void> Function(String) exec) async {
    await exec('''
      CREATE TABLE IF NOT EXISTS draw_periods (
        id TEXT PRIMARY KEY,
        drawType TEXT NOT NULL,
        drawDate TEXT NOT NULL,
        salesOpenTime INTEGER NOT NULL,
        salesCloseTime INTEGER NOT NULL,
        drawTime INTEGER NOT NULL,
        status TEXT NOT NULL,
        result TEXT,
        resultPublishedAt INTEGER,
        publishedBy TEXT,
        resultSource TEXT,
        timezone TEXT,
        result3 TEXT,
        result3PublishedAt INTEGER,
        result3PublishedBy TEXT,
        result3Source TEXT,
        result4 TEXT,
        result4PublishedAt INTEGER,
        result4PublishedBy TEXT,
        result4Source TEXT
      )
    ''');
    await exec(
      'CREATE INDEX IF NOT EXISTS idx_draw_periods_date ON draw_periods(drawDate)',
    );
    await exec(
      'CREATE INDEX IF NOT EXISTS idx_draw_periods_type ON draw_periods(drawType)',
    );
    await exec(
      'CREATE INDEX IF NOT EXISTS idx_draw_periods_status ON draw_periods(status)',
    );
    await exec('''
      CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY,
        user TEXT NOT NULL,
        action TEXT NOT NULL,
        periodId TEXT,
        oldValue TEXT,
        newValue TEXT,
        timestamp INTEGER NOT NULL,
        reason TEXT
      )
    ''');
    await exec(
      'CREATE INDEX IF NOT EXISTS idx_audit_period ON audit_logs(periodId)',
    );
    await exec('''
      CREATE TABLE IF NOT EXISTS ticket_lines (
        id TEXT PRIMARY KEY,
        ticketId TEXT NOT NULL,
        gameId TEXT NOT NULL,
        gameName TEXT NOT NULL,
        drawId TEXT,
        drawName TEXT,
        numbers TEXT NOT NULL,
        betType TEXT NOT NULL,
        amount REAL NOT NULL,
        isQuickPick INTEGER NOT NULL DEFAULT 0,
        periodId TEXT,
        periodStatus TEXT,
        winningStatus TEXT,
        prizeAmount REAL,
        FOREIGN KEY (ticketId) REFERENCES tickets(id)
      )
    ''');
    await exec(
      'CREATE INDEX IF NOT EXISTS idx_ticket_lines_ticketId ON ticket_lines(ticketId)',
    );
    await exec('''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        role TEXT NOT NULL,
        status TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        commission REAL DEFAULT 0
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
    try {
      await customStatement(
        'ALTER TABLE accounts ADD COLUMN commission REAL DEFAULT 0',
      );
    } catch (_) {}
    await customStatement(
      "UPDATE accounts SET role='worker' WHERE role IN ('agent','cashier')",
    );
    await customStatement(
      "INSERT OR IGNORE INTO accounts (id, username, password, role, status, createdAt, commission) VALUES ('acc_admin', 'admin', 'admin123', 'admin', 'active', $now, 0)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO accounts (id, username, password, role, status, createdAt, commission) VALUES ('acc_worker1', 'worker1', 'worker123', 'worker', 'active', $now, 5.0)",
    );
    await customStatement(
      "UPDATE accounts SET password='admin123', status='active', role='admin' WHERE username='admin'",
    );
    await customStatement(
      "UPDATE accounts SET password='worker123', status='active', role='worker' WHERE username='worker1'",
    );
    // Keep legacy agent1 for backward compat but as worker
    await customStatement(
      "UPDATE accounts SET role='worker', commission=COALESCE(commission,5.0) WHERE username='agent1'",
    );
    await customStatement(
      "UPDATE accounts SET role='worker' WHERE username='cashier'",
    );
    //    : 0-9
    await customStatement(
      "UPDATE games SET numberRangeMin=0, numberRangeMax=9, description='NY Lottery Pick 3 (0-9) — Straight/Box/Combo/StrBox/Pairs' WHERE id='g_numbers' AND numberRangeMin!=0",
    );
    await customStatement(
      "UPDATE games SET numberRangeMin=0, numberRangeMax=9, description='NY Lottery Win 4 (0-9) — 4 digits Straight/Box/Combo' WHERE id='g_winz' AND numberRangeMin!=0",
    );
    final games = await customSelect('SELECT COUNT(*) as c FROM games')
        .getSingle();
    if ((games.data['c'] as int) == 0) {
      await customStatement(
        "INSERT INTO games (id, name, type, description, minAmount, maxAmount, maxSelections, numberRangeMin, numberRangeMax) VALUES ('g_numbers', 'Numbers', 'numbers', 'NY Lottery Pick 3 (0-9) — Straight/Box/Combo/StrBox/Pairs', 0.5, 10, 5, 0, 9)",
      );
      await customStatement(
        "INSERT INTO games (id, name, type, description, minAmount, maxAmount, maxSelections, numberRangeMin, numberRangeMax) VALUES ('g_winz', 'Win 4', 'winz', 'NY Lottery Win 4 (0-9) — 4 digits Straight/Box/Combo', 0.5, 10, 4, 0, 9)",
      );
    }
    // Ensure games always correct even if existed
    await customStatement(
      "UPDATE games SET name='Win 4', type='winz', maxSelections=4, minAmount=0.5, maxAmount=10, numberRangeMin=0, numberRangeMax=9, description='NY Lottery Win 4 (0-9) — 4 digits Straight/Box/Combo' WHERE id='g_winz'",
    );
    await customStatement(
      "UPDATE games SET name='Numbers', maxSelections=5, minAmount=0.5, maxAmount=10, numberRangeMin=0, numberRangeMax=9 WHERE id='g_numbers'",
    );
    // Midday / Evening — spec defaults 14:15/14:30 and 22:20/22:30 (2 draws per day, 14 days)
    final draws = await customSelect('SELECT COUNT(*) as c FROM draws')
        .getSingle();
    DateTime midday(DateTime base) =>
        DateTime(base.year, base.month, base.day, 14, 30);
    DateTime evening(DateTime base) =>
        DateTime(base.year, base.month, base.day, 22, 30);
    final periods = [(midday, 'Midday'), (evening, 'Evening')];
    if ((draws.data['c'] as int) == 0) {
      final now = DateTime.now();
      for (var i = 0; i < 14; i++) {
        final base = now.add(Duration(days: i));
        for (final entry in periods) {
          final dt = entry.$1(base);
          final label = entry.$2;
          final id =
              'draw_numbers_${label.toLowerCase()}_${base.year}${base.month.toString().padLeft(2, '0')}${base.day.toString().padLeft(2, '0')}';
          final name =
              'Numbers $label - ${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          await customStatement(
            "INSERT OR IGNORE INTO draws (id, gameId, name, drawTime, status) VALUES ('$id', 'g_numbers', '$name', ${dt.millisecondsSinceEpoch}, 'open')",
          );
        }
      }
      for (var i = 0; i < 14; i++) {
        final base = now.add(Duration(days: i));
        for (final entry in periods) {
          final dt = entry.$1(base);
          final label = entry.$2;
          final id =
              'draw_win4_${label.toLowerCase()}_${base.year}${base.month.toString().padLeft(2, '0')}${base.day.toString().padLeft(2, '0')}';
          final name =
              'Win 4 $label - ${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          await customStatement(
            "INSERT OR IGNORE INTO draws (id, gameId, name, drawTime, status) VALUES ('$id', 'g_winz', '$name', ${dt.millisecondsSinceEpoch}, 'open')",
          );
        }
      }
    } else {
      // For existing DBs: ensure next 14 days draws exist with correct spec times
      final now = DateTime.now();
      for (var i = 0; i < 14; i++) {
        final base = now.add(Duration(days: i));
        for (final entry in periods) {
          final dt = entry.$1(base);
          final label = entry.$2;
          final idN =
              'draw_numbers_${label.toLowerCase()}_${base.year}${base.month.toString().padLeft(2, '0')}${base.day.toString().padLeft(2, '0')}';
          final nameN =
              'Numbers $label - ${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          await customStatement(
            "INSERT OR IGNORE INTO draws (id, gameId, name, drawTime, status) VALUES ('$idN', 'g_numbers', '$nameN', ${dt.millisecondsSinceEpoch}, 'open')",
          );
          final idW =
              'draw_win4_${label.toLowerCase()}_${base.year}${base.month.toString().padLeft(2, '0')}${base.day.toString().padLeft(2, '0')}';
          final nameW =
              'Win 4 $label - ${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          await customStatement(
            "INSERT OR IGNORE INTO draws (id, gameId, name, drawTime, status) VALUES ('$idW', 'g_winz', '$nameW', ${dt.millisecondsSinceEpoch}, 'open')",
          );
        }
      }
      // Migrate old Morning 10:00 to Midday 14:30
      await customStatement(
        "UPDATE draws SET drawTime = drawTime + (4*3600+30*60)*1000 WHERE name LIKE '%Morning%'",
      );
      await customStatement(
        "UPDATE draws SET name = REPLACE(name, 'Morning', 'Midday') WHERE name LIKE '%Morning%'",
      );
    }
    // Cleanup old Night draws
    await customStatement("DELETE FROM draws WHERE name LIKE '%Night%'");
    // Ensure draw_periods seeded from config
    await _seedDrawPeriods();
    // Ensure draw config defaults exist (even if configs already seeded)
    final nowCfg = DateTime.now().millisecondsSinceEpoch;
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('midday_sales_close', '14:15', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('midday_draw_time', '14:30', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('midday_enabled', '1', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('evening_sales_close', '22:20', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('evening_draw_time', '22:30', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('evening_enabled', '1', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('draw_timezone', 'America/New_York', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('midday_result_mode', 'manual', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('evening_result_mode', 'manual', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('auto_open_next', '1', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('winning_time_restricted', '1', 'local', $nowCfg)",
    );
    // Per-number per-period limits (risk control) — user request: Straight4=10, Straight3=100, Box4=50
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_straight_3', '100', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_straight_4', '10', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_box_3', '50', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_box_4', '50', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_combo_3', '100', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_combo_4', '10', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_strbox_3', '50', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('limit_strbox_4', '50', 'local', $nowCfg)",
    );
    // Backup defaults (v11)
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('backup_enabled', '1', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('backup_interval', 'daily', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('backup_retention', '10', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('client_commission_rate', '20', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('printer_type', 'thermal_58mm', 'local', $nowCfg)",
    );
    await customStatement(
      "INSERT OR IGNORE INTO app_config (key, value, scope, updatedAt) VALUES ('printer_connection', 'bluetooth', 'local', $nowCfg)",
    );

    final configs = await customSelect('SELECT COUNT(*) as c FROM app_config')
        .getSingle();
    if ((configs.data['c'] as int) == 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('printer_type', 'thermal_58mm', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('printer_connection', 'bluetooth', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('currency', 'USD', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('language', 'en-US', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('ticket_footer', '', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('company_name', 'NY Lottery POS', 'server', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('straight_multiplier', '500', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('box_multiplier', '80', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('combo_multiplier', '500', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('straight_3d_multiplier', '500', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('straight_4d_multiplier', '5000', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('box_3d_multiplier', '160', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('box_4d_multiplier', '400', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_straight', '500', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_box_3way', '160', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('numbers_box_6way', '80', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('win4_straight', '5000', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_4way', '1200', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_6way', '800', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_12way', '400', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('win4_box_24way', '200', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('winz_std_multiplier', '10', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('winz_jackpot_multiplier', '100', 'local', $now)",
      );
      await customStatement(
        "INSERT INTO app_config (key, value, scope, updatedAt) VALUES ('winz_instant_multiplier', '5', 'local', $now)",
      );
    }
  }

  Future<void> seedDrawPeriods() async => _seedDrawPeriods();
  Future<void> refreshPeriodStatuses() async {
    try {
      // إعادة حساب الحالة مع السماح بإعادة الفتح إذا مُدد وقت الإغلاق لليوم نفسه
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final periods = await getAllPeriods();
      for (final p in periods) {
        final status = p['status'] as String;
        if (status == 'CANCELLED' ||
            status == 'POSTPONED' ||
            status == 'SUSPENDED')
          continue;
        final r = p['result'] as String?;
        final r3 = p['result3'] as String?;
        final r4 = p['result4'] as String?;
        final hasResult =
            (r != null && r.isNotEmpty) ||
            (r3 != null && r3.isNotEmpty) ||
            (r4 != null && r4.isNotEmpty);
        if (hasResult) {
          if (status == 'RESULT_PENDING' ||
              status == 'SALES_CLOSED' ||
              status == 'OPEN' ||
              status == 'SCHEDULED' ||
              status == 'DRAWING') {
            await customStatement(
              "UPDATE draw_periods SET status='RESULT_PUBLISHED' WHERE id=?",
              [p['id']],
            );
          } else if (status == 'RESULT_PUBLISHED') {
            await customStatement(
              "UPDATE draw_periods SET status='COMPLETED' WHERE id=?",
              [p['id']],
            );
          }
          continue;
        }
        final salesOpen = p['salesOpenTime'] as int;
        final salesClose = p['salesCloseTime'] as int;
        final drawTime = p['drawTime'] as int;
        String desired;
        if (nowMs < salesOpen)
          desired = 'SCHEDULED';
        else if (nowMs < salesClose)
          desired = 'OPEN';
        else if (nowMs < drawTime)
          desired = 'SALES_CLOSED';
        else
          desired = 'RESULT_PENDING';
        if (desired != status) {
          await customStatement("UPDATE draw_periods SET status=? WHERE id=?", [
            desired,
            p['id'],
          ]);
        }
      }
    } catch (_) {}
  }

  Future<void> ensurePeriodExists(String periodId) async {
    try {
      final existing = await getPeriodById(periodId);
      if (existing != null) return;
      // Parse periodId like 2026-08-31-MIDDAY
      final parts = periodId.split('-');
      if (parts.length < 4) return;
      final drawType = parts.last;
      final dateStr = parts.sublist(0, 3).join('-');
      final cfgRows = await customSelect(
        'SELECT key, value FROM app_config WHERE key IN (\'midday_sales_close\',\'midday_draw_time\',\'evening_sales_close\',\'evening_draw_time\',\'draw_timezone\')',
      ).get();
      final cfg = {
        for (var r in cfgRows)
          r.data['key'] as String: r.data['value'] as String,
      };
      final tz = cfg['draw_timezone'] ?? 'America/New_York';
      String closeStr, drawStr;
      if (drawType == 'MIDDAY') {
        closeStr = cfg['midday_sales_close'] ?? '14:15';
        drawStr = cfg['midday_draw_time'] ?? '14:30';
      } else {
        closeStr = cfg['evening_sales_close'] ?? '22:20';
        drawStr = cfg['evening_draw_time'] ?? '22:30';
      }
      List<int> parseSimple(String s) {
        final p = s.split(':');
        return [int.parse(p[0]), int.parse(p[1])];
      }

      final dp = dateStr.split('-');
      final y = int.parse(dp[0]), m = int.parse(dp[1]), d = int.parse(dp[2]);
      final hmClose = parseSimple(closeStr), hmDraw = parseSimple(drawStr);
      final baseDate = DateTime(y, m, d);
      final salesOpen = MarketTimezone.epochForWallTime(baseDate, 0, 0, tz);
      final salesClose = MarketTimezone.epochForWallTime(
        baseDate,
        hmClose[0],
        hmClose[1],
        tz,
      );
      final drawTime = MarketTimezone.epochForWallTime(
        baseDate,
        hmDraw[0],
        hmDraw[1],
        tz,
      );
      await customStatement(
        'INSERT OR IGNORE INTO draw_periods (id, drawType, drawDate, salesOpenTime, salesCloseTime, drawTime, status, timezone) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          periodId,
          drawType,
          dateStr,
          salesOpen,
          salesClose,
          drawTime,
          'SCHEDULED',
          tz,
        ],
      );
      await refreshPeriodStatuses();
    } catch (_) {}
  }

  Future<void> _seedDrawPeriods() async {
    try {
      final cfgRows = await customSelect(
        'SELECT key, value FROM app_config WHERE key IN (\'midday_sales_close\',\'midday_draw_time\',\'midday_enabled\',\'evening_sales_close\',\'evening_draw_time\',\'evening_enabled\',\'draw_timezone\')',
      ).get();
      final cfg = {
        for (var r in cfgRows)
          r.data['key'] as String: r.data['value'] as String,
      };
      final middayClose = cfg['midday_sales_close'] ?? '14:15';
      final middayDraw = cfg['midday_draw_time'] ?? '14:30';
      final eveningClose = cfg['evening_sales_close'] ?? '22:20';
      final eveningDraw = cfg['evening_draw_time'] ?? '22:30';
      final middayEnabled = (cfg['midday_enabled'] ?? '1') == '1';
      final eveningEnabled = (cfg['evening_enabled'] ?? '1') == '1';
      final tz = cfg['draw_timezone'] ?? 'America/New_York';
      List<int> parseHM(String s) {
        s = s.trim().toUpperCase().replaceAll(RegExp(r'\s*[AP]M'), '').trim();
        final isPM = s.contains('PM');
        final isAM = s.contains('AM');
        // Already stripped, need original flag
        final raw = s;
        final parts = raw.split(':');
        int h = int.parse(parts[0]);
        int m = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
        if (isPM && h < 12) h += 12;
        if (isAM && h == 12) h = 0;
        // Actually need to check original string for PM/AM before stripping
        return [h, m];
      }

      // Simpler parse using stored values which are HH:MM without AM/PM
      List<int> parseSimple(String s) {
        final p = s.split(':');
        return [int.parse(p[0]), int.parse(p[1])];
      }

      final now = DateTime.now();
      for (int i = 0; i < 14; i++) {
        final date = DateTime(
          now.year,
          now.month,
          now.day,
        ).add(Duration(days: i));
        final dateStr =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        if (middayEnabled) {
          final hmClose = parseSimple(middayClose);
          final hmDraw = parseSimple(middayDraw);
          final salesClose = MarketTimezone.epochForWallTime(
            date,
            hmClose[0],
            hmClose[1],
            tz,
          );
          final drawTime = MarketTimezone.epochForWallTime(
            date,
            hmDraw[0],
            hmDraw[1],
            tz,
          );
          final salesOpen = MarketTimezone.epochForWallTime(date, 0, 0, tz);
          final id = '${dateStr}-MIDDAY';
          final exists = await customSelect(
            'SELECT COUNT(*) as c FROM draw_periods WHERE id = ?',
            variables: [Variable.withString(id)],
          ).getSingle();
          if ((exists.data['c'] as int) == 0) {
            await customStatement(
              'INSERT OR IGNORE INTO draw_periods (id, drawType, drawDate, salesOpenTime, salesCloseTime, drawTime, status, timezone) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
              [
                id,
                'MIDDAY',
                dateStr,
                salesOpen,
                salesClose,
                drawTime,
                'SCHEDULED',
                tz,
              ],
            );
          }
        }
        if (eveningEnabled) {
          final hmClose = parseSimple(eveningClose);
          final hmDraw = parseSimple(eveningDraw);
          final salesClose = MarketTimezone.epochForWallTime(
            date,
            hmClose[0],
            hmClose[1],
            tz,
          );
          final drawTime = MarketTimezone.epochForWallTime(
            date,
            hmDraw[0],
            hmDraw[1],
            tz,
          );
          final salesOpen = MarketTimezone.epochForWallTime(date, 0, 0, tz);
          final id = '${dateStr}-EVENING';
          final exists = await customSelect(
            'SELECT COUNT(*) as c FROM draw_periods WHERE id = ?',
            variables: [Variable.withString(id)],
          ).getSingle();
          if ((exists.data['c'] as int) == 0) {
            await customStatement(
              'INSERT OR IGNORE INTO draw_periods (id, drawType, drawDate, salesOpenTime, salesCloseTime, drawTime, status, timezone) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
              [
                id,
                'EVENING',
                dateStr,
                salesOpen,
                salesClose,
                drawTime,
                'SCHEDULED',
                tz,
              ],
            );
          }
        }
      }
      // Auto-open logic: ensure statuses reflect time (مع السماح بإعادة الفتح لليوم نفسه)
      await refreshPeriodStatuses();
    } catch (_) {}
  }

  // Helpers
  Future<List<Map<String, dynamic>>> getAccounts() async {
    final rows = await customSelect('SELECT * FROM accounts ORDER BY username')
        .get();
    return rows.map((r) => r.data).toList();
  }

  Future<Map<String, dynamic>?> findAccount(
    String username,
    String password,
  ) async {
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
    final rows = await customSelect(
      'SELECT * FROM draws ORDER BY drawTime DESC',
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<Map<String, dynamic>?> getDrawById(String id) async {
    final rows = await customSelect(
      'SELECT * FROM draws WHERE id = ? LIMIT 1',
      variables: [Variable.withString(id)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.data;
  }

  Future<void> updateDrawResult(String id, String winningNumbers) async {
    await customStatement(
      "UPDATE draws SET winningNumbers = ?, status = 'closed' WHERE id = ?",
      [winningNumbers, id],
    );
  }

  Future<void> insertTicket(Map<String, dynamic> t) async {
    await customStatement(
      '''
      INSERT INTO tickets
      (id, serialNumber, gameId, gameName, drawId, drawName, numbers, betType, amount, total, operatorId, operatorName, createdAt, status, barcode, prizeAmount, paidAt, paidBy, isQuickPick)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
      [
        t['id'],
        t['serialNumber'],
        t['gameId'],
        t['gameName'],
        t['drawId'],
        t['drawName'],
        t['numbers'],
        t['betType'],
        t['amount'],
        t['total'],
        t['operatorId'],
        t['operatorName'],
        t['createdAt'],
        t['status'],
        t['barcode'],
        t['prizeAmount'],
        t['paidAt'],
        t['paidBy'],
        t['isQuickPick'] ?? 0,
      ],
    );
  }

  // Ticket lines (multi-play per ticket)
  Future<void> insertTicketLine(Map<String, dynamic> l) async {
    await customStatement(
      '''
      INSERT OR REPLACE INTO ticket_lines
      (id, ticketId, gameId, gameName, drawId, drawName, numbers, betType, amount, isQuickPick, periodId, periodStatus, winningStatus, prizeAmount)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
      [
        l['id'],
        l['ticketId'],
        l['gameId'],
        l['gameName'],
        l['drawId'],
        l['drawName'],
        l['numbers'],
        l['betType'],
        l['amount'],
        l['isQuickPick'] ?? 0,
        l['periodId'],
        l['periodStatus'],
        l['winningStatus'],
        l['prizeAmount'],
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getTicketLines(String ticketId) async {
    final rows = await customSelect(
      'SELECT * FROM ticket_lines WHERE ticketId = ? ORDER BY rowid',
      variables: [Variable.withString(ticketId)],
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<int> getTicketLinesCount(String ticketId) async {
    final row = await customSelect(
      'SELECT COUNT(*) as c FROM ticket_lines WHERE ticketId = ?',
      variables: [Variable.withString(ticketId)],
    ).getSingle();
    return (row.data['c'] as int);
  }

  Future<List<Map<String, dynamic>>> getAllTicketLines() async {
    final rows = await customSelect(
      'SELECT * FROM ticket_lines ORDER BY ticketId',
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getTicketLinesByPeriod(
    String periodId,
  ) async {
    final rows = await customSelect(
      'SELECT * FROM ticket_lines WHERE periodId = ?',
      variables: [Variable.withString(periodId)],
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<double> sumTicketLinesAmountByPeriod(String periodId) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(amount),0) as s FROM ticket_lines WHERE periodId = ?',
      variables: [Variable.withString(periodId)],
    ).getSingle();
    return (row.data['s'] as num).toDouble();
  }

  // Insert ticket with its lines in a single helper
  Future<void> insertTicketWithLines(
    Map<String, dynamic> ticket,
    List<Map<String, dynamic>> lines,
  ) async {
    await insertTicket(ticket);
    for (final l in lines) {
      await insertTicketLine(l);
    }
  }

  Future<List<Map<String, dynamic>>> getTickets({String? status}) async {
    final where = status != null ? 'WHERE status = ?' : '';
    final vars = status != null ? [Variable.withString(status)] : <Variable>[];
    final rows = await customSelect(
      'SELECT * FROM tickets $where ORDER BY createdAt DESC',
      variables: vars,
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<Map<String, dynamic>?> getTicketById(String id) async {
    final rows = await customSelect(
      'SELECT * FROM tickets WHERE id = ? LIMIT 1',
      variables: [Variable.withString(id)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.data;
  }

  Future<Map<String, dynamic>?> getTicketByBarcode(String barcode) async {
    barcode = barcode.trim();
    if (barcode.isEmpty) return null;
    Future<Map<String, dynamic>?> lookup(String v) async {
      final rows = await customSelect(
        'SELECT * FROM tickets WHERE barcode = ? OR id = ? OR serialNumber = ? LIMIT 1',
        variables: [
          Variable.withString(v),
          Variable.withString(v),
          Variable.withString(v),
        ],
      ).get();
      if (rows.isEmpty) return null;
      return rows.first.data;
    }

    final exact = await lookup(barcode);
    if (exact != null) return exact;
    if (RegExp(r'^\d+$').hasMatch(barcode)) {
      final padded6 = barcode.padLeft(6, '0');
      final padded8 = barcode.padLeft(8, '0');
      final stripped = barcode.replaceFirst(RegExp(r'^0+'), '');
      for (final v in {padded6, padded8, if (stripped.isNotEmpty) stripped}) {
        if (v == barcode) continue;
        final hit = await lookup(v);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  Future<void> updateTicketStatus(
    String id,
    String status, {
    double? prizeAmount,
    int? paidAt,
    String? paidBy,
  }) async {
    await customStatement(
      'UPDATE tickets SET status = ?, prizeAmount = COALESCE(?, prizeAmount), paidAt = COALESCE(?, paidAt), paidBy = COALESCE(?, paidBy) WHERE id = ?',
      [status, prizeAmount, paidAt, paidBy, id],
    );
  }

  /// Atomically reserves the single prize payout allowed for a ticket.
  /// The deterministic primary key makes concurrent/duplicate attempts fail.
  Future<bool> insertPayoutLedger({
    required String ticketId,
    required double amount,
    required String operatorId,
    required int createdAt,
  }) async {
    try {
      await customStatement(
        'INSERT INTO cash_ledger (id, type, amount, direction, description, operatorId, createdAt, ticketId) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'payout_$ticketId',
          'payout',
          amount,
          'out',
          'Prize payout for $ticketId',
          operatorId,
          createdAt,
          ticketId,
        ],
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<double> getPayoutAmountForTicket(String ticketId) async {
    final row = await customSelect(
      'SELECT amount FROM cash_ledger WHERE id = ? LIMIT 1',
      variables: [Variable.withString('payout_$ticketId')],
    ).getSingleOrNull();
    return row == null ? 0.0 : (row.data['amount'] as num).toDouble();
  }

  /// Frees the payout lock while keeping the original ledger row as history.
  Future<void> releasePayoutLockForTicket(String ticketId, int at) async {
    await customStatement('UPDATE cash_ledger SET id = ? WHERE id = ?', [
      'payout_${ticketId}_reversed_$at',
      'payout_$ticketId',
    ]);
  }

  // Partial void: cancel a single line inside a multi-play ticket
  Future<Map<String, dynamic>?> getTicketLineById(String id) async {
    final rows = await customSelect(
      'SELECT * FROM ticket_lines WHERE id = ? LIMIT 1',
      variables: [Variable.withString(id)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.data;
  }

  Future<void> voidTicketLine(String lineId) async {
    await customStatement(
      "UPDATE ticket_lines SET periodStatus='cancelled', winningStatus='void', prizeAmount=0 WHERE id = ?",
      [lineId],
    );
  }

  Future<void> recalcTicketTotals(String ticketId) async {
    final rows = await customSelect(
      "SELECT COALESCE(SUM(amount),0) as s, COUNT(*) as c FROM ticket_lines WHERE ticketId = ? AND periodStatus != 'cancelled'",
      variables: [Variable.withString(ticketId)],
    ).getSingle();
    final sum = (rows.data['s'] as num).toDouble();
    final cnt = (rows.data['c'] as int);
    if (cnt == 0) {
      await customStatement(
        "UPDATE tickets SET total=0, amount=0, status='cancelled' WHERE id = ?",
        [ticketId],
      );
    } else {
      // rebuild header numbers/betType for display
      final lines = await customSelect(
        "SELECT numbers, betType FROM ticket_lines WHERE ticketId = ? AND periodStatus != 'cancelled' ORDER BY rowid",
        variables: [Variable.withString(ticketId)],
      ).get();
      String headerNums;
      String headerBet;
      if (lines.length == 1) {
        headerNums = lines.first.data['numbers'] as String;
        headerBet = lines.first.data['betType'] as String;
      } else {
        headerNums = lines.map((r) => r.data['numbers'] as String).join(';');
        headerBet = 'Multi';
      }
      await customStatement(
        "UPDATE tickets SET total=?, amount=?, numbers=?, betType=? WHERE id = ?",
        [sum, sum, headerNums, headerBet, ticketId],
      );
      // if ticket was cancelled but now has active lines? keep active
      await customStatement(
        "UPDATE tickets SET status='active' WHERE id = ? AND status='cancelled'",
        [ticketId],
      );
    }
  }

  Future<void> insertCashLedger(Map<String, dynamic> e) async {
    await customStatement(
      'INSERT INTO cash_ledger (id, type, amount, direction, description, operatorId, createdAt, ticketId) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        e['id'],
        e['type'],
        e['amount'],
        e['direction'],
        e['description'],
        e['operatorId'],
        e['createdAt'],
        e['ticketId'],
      ],
    );
  }

  Future<void> insertBalanceMovement(Map<String, dynamic> e) async {
    await customStatement(
      'INSERT INTO balance_movements (id, type, amount, direction, description, operatorId, createdAt, ticketId) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        e['id'],
        e['type'],
        e['amount'],
        e['direction'],
        e['description'],
        e['operatorId'],
        e['createdAt'],
        e['ticketId'],
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getCashLedger() async {
    final rows = await customSelect(
      'SELECT * FROM cash_ledger ORDER BY createdAt DESC',
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getBalanceMovements() async {
    final rows = await customSelect(
      'SELECT * FROM balance_movements ORDER BY createdAt DESC',
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<Map<String, dynamic>?> getOpenCashSession(String operatorId) async {
    final rows = await customSelect(
      "SELECT * FROM cash_sessions WHERE operatorId = ? AND status = 'open' LIMIT 1",
      variables: [Variable.withString(operatorId)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.data;
  }

  Future<void> insertCashSession(Map<String, dynamic> s) async {
    await customStatement(
      'INSERT INTO cash_sessions (id, operatorId, openingAmount, closingAmount, openedAt, closedAt, status) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        s['id'],
        s['operatorId'],
        s['openingAmount'],
        s['closingAmount'],
        s['openedAt'],
        s['closedAt'],
        s['status'],
      ],
    );
  }

  Future<void> closeCashSession(
    String id,
    double closingAmount,
    int closedAt,
  ) async {
    await customStatement(
      "UPDATE cash_sessions SET closingAmount = ?, closedAt = ?, status = 'closed' WHERE id = ?",
      [closingAmount, closedAt, id],
    );
  }

  Future<List<Map<String, dynamic>>> getCashSessions() async {
    final rows = await customSelect(
      'SELECT * FROM cash_sessions ORDER BY openedAt DESC',
    ).get();
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
      [key, value, scope, now],
    );
  }

  static const double defaultClientCommissionRate = 20.0;

  Future<double> getClientCommissionRate() async {
    try {
      final rows = await customSelect(
        "SELECT value FROM app_config WHERE key='client_commission_rate' LIMIT 1",
      ).get();
      if (rows.isEmpty) return defaultClientCommissionRate;
      final v = double.tryParse((rows.first.data['value'] as String?) ?? '');
      if (v == null || v < 0) return defaultClientCommissionRate;
      return v;
    } catch (_) {
      return defaultClientCommissionRate;
    }
  }

  Future<void> setClientCommissionRate(double rate) async {
    final v = rate < 0 ? 0.0 : rate;
    final text = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    await upsertConfig('client_commission_rate', text, 'local');
  }

  Future<String> nextTicketId() async {
    return transaction<String>(() async {
      // Sequential numeric ticket IDs: 000001, 000002, ...
      final row = await customSelect(
        "SELECT value FROM app_config WHERE key='ticket_seq' LIMIT 1",
      ).get();
      int seq = 0;
      if (row.isNotEmpty) {
        seq = int.tryParse(row.first.data['value'] as String? ?? '0') ?? 0;
      } else {
        try {
          final maxRow = await customSelect(
            "SELECT MAX(CAST(id AS INTEGER)) as m FROM tickets WHERE id GLOB '[0-9]*'",
          ).getSingle();
          final m = maxRow.data['m'];
          if (m != null) seq = (m as num).toInt();
        } catch (_) {}
      }
      seq += 1;
      final now = DateTime.now().millisecondsSinceEpoch;
      await customStatement(
        "INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('ticket_seq', ?, 'local', ?)",
        [seq.toString(), now],
      );
      return seq.toString().padLeft(6, '0');
    });
  }

  Future<String> nextSerialNumber() async {
    return transaction<String>(() async {
      final row = await customSelect(
        "SELECT value FROM app_config WHERE key='serial_seq' LIMIT 1",
      ).get();
      int seq = 0;
      if (row.isNotEmpty) {
        seq = int.tryParse(row.first.data['value'] as String? ?? '0') ?? 0;
      } else {
        try {
          final maxRow = await customSelect(
            "SELECT MAX(CAST(value AS INTEGER)) as m FROM app_config WHERE key='serial_seq'",
          ).getSingle();
          final m = maxRow.data['m'];
          if (m != null) seq = (m as num).toInt();
        } catch (_) {}
      }
      seq += 1;
      final now = DateTime.now().millisecondsSinceEpoch;
      await customStatement(
        "INSERT OR REPLACE INTO app_config (key, value, scope, updatedAt) VALUES ('serial_seq', ?, 'local', ?)",
        [seq.toString(), now],
      );
      return seq.toString().padLeft(8, '0');
    });
  }

  Future<double> sumCash(
    String direction, {
    String? type,
    String? operatorId,
  }) async {
    final typeWhere = type != null ? "AND type = '$type'" : '';
    final opWhere = operatorId != null ? "AND operatorId = ?" : '';
    final vars = <Variable>[
      Variable.withString(direction),
      if (operatorId != null) Variable.withString(operatorId),
    ];
    final row = await customSelect(
      "SELECT COALESCE(SUM(amount),0) as s FROM cash_ledger WHERE direction = ? $typeWhere $opWhere",
      variables: vars,
    ).getSingle();
    return (row.data['s'] as num).toDouble();
  }

  /// Sum cash movements strictly after a session boundary. Used so that a
  /// new opening float is not added on top of the previous session's cash.
  Future<double> sumCashSince(
    String direction,
    int since, {
    String? operatorId,
  }) async {
    final opWhere = operatorId != null ? 'AND operatorId = ?' : '';
    final vars = <Variable>[
      Variable.withString(direction),
      Variable.withInt(since),
      if (operatorId != null) Variable.withString(operatorId),
    ];
    final row = await customSelect(
      'SELECT COALESCE(SUM(amount),0) as s FROM cash_ledger '
      'WHERE direction = ? AND createdAt > ? $opWhere',
      variables: vars,
    ).getSingle();
    return (row.data['s'] as num).toDouble();
  }

  Future<Map<String, dynamic>?> getLastClosedCashSession(
    String operatorId,
  ) async {
    final rows = await customSelect(
      "SELECT * FROM cash_sessions WHERE operatorId = ? AND status = 'closed' ORDER BY closedAt DESC LIMIT 1",
      variables: [Variable.withString(operatorId)],
    ).get();
    return rows.isEmpty ? null : rows.first.data;
  }

  Future<List<Map<String, dynamic>>> getCashLedgerByTicket(
    String ticketId,
  ) async {
    final rows = await customSelect(
      'SELECT * FROM cash_ledger WHERE ticketId = ? ORDER BY createdAt',
      variables: [Variable.withString(ticketId)],
    ).get();
    return rows.map((r) => r.data).toList();
  }

  // Reset tickets for draw replacement (fix winning->losing bug)
  Future<void> resetDrawTickets(String drawId) async {
    await customStatement(
      "UPDATE tickets SET status='active', prizeAmount=NULL WHERE drawId = ? AND status IN ('winning','losing')",
      [drawId],
    );
  }

  // Operator-filtered ledger/balance for per-operator cash
  Future<List<Map<String, dynamic>>> getCashLedgerByOperator(
    String operatorId,
  ) async {
    final rows = await customSelect(
      'SELECT * FROM cash_ledger WHERE operatorId = ? ORDER BY createdAt DESC',
      variables: [Variable.withString(operatorId)],
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getBalanceMovementsByOperator(
    String operatorId,
  ) async {
    final rows = await customSelect(
      'SELECT * FROM balance_movements WHERE operatorId = ? ORDER BY createdAt DESC',
      variables: [Variable.withString(operatorId)],
    ).get();
    return rows.map((r) => r.data).toList();
  }

  // ============ DRAW PERIODS ============
  Future<void> insertPeriod(Map<String, dynamic> p) async {
    await customStatement(
      'INSERT OR REPLACE INTO draw_periods (id, drawType, drawDate, salesOpenTime, salesCloseTime, drawTime, status, result, resultPublishedAt, publishedBy, resultSource, timezone) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        p['id'],
        p['drawType'],
        p['drawDate'],
        p['salesOpenTime'],
        p['salesCloseTime'],
        p['drawTime'],
        p['status'],
        p['result'],
        p['resultPublishedAt'],
        p['publishedBy'],
        p['resultSource'],
        p['timezone'],
      ],
    );
  }

  Future<Map<String, dynamic>?> getPeriodById(String id) async {
    final rows = await customSelect(
      'SELECT * FROM draw_periods WHERE id = ? LIMIT 1',
      variables: [Variable.withString(id)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.data;
  }

  Future<List<Map<String, dynamic>>> getAllPeriods() async {
    final rows = await customSelect(
      'SELECT * FROM draw_periods ORDER BY drawTime DESC',
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getPeriodsByDate(String date) async {
    final rows = await customSelect(
      'SELECT * FROM draw_periods WHERE drawDate = ? ORDER BY drawType',
      variables: [Variable.withString(date)],
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getOpenPeriods() async {
    final rows = await customSelect(
      "SELECT * FROM draw_periods WHERE status = 'OPEN' ORDER BY drawTime",
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<void> updatePeriodStatus(String id, String status) async {
    await customStatement('UPDATE draw_periods SET status = ? WHERE id = ?', [
      status,
      id,
    ]);
  }

  Future<void> updatePeriodTimes(
    String id,
    int salesOpen,
    int salesClose,
    int drawTime,
  ) async {
    await customStatement(
      'UPDATE draw_periods SET salesOpenTime = ?, salesCloseTime = ?, drawTime = ? WHERE id = ?',
      [salesOpen, salesClose, drawTime, id],
    );
  }

  Future<void> publishPeriodResult(
    String id,
    String result,
    int publishedAt,
    String publishedBy,
    String source,
  ) async {
    await customStatement(
      'UPDATE draw_periods SET result = ?, resultPublishedAt = ?, publishedBy = ?, resultSource = ?, status = ? WHERE id = ?',
      [result, publishedAt, publishedBy, source, 'RESULT_PUBLISHED', id],
    );
    // Also set to COMPLETED after? Keep RESULT_PUBLISHED for immediate, service will transition to COMPLETED
  }

  // Dual winners: separate 3-digit and 4-digit results
  Future<void> publishPeriodResult3(
    String id,
    String result,
    int publishedAt,
    String publishedBy,
    String source,
  ) async {
    await customStatement(
      'UPDATE draw_periods SET result3 = ?, result3PublishedAt = ?, result3PublishedBy = ?, result3Source = ?, result = COALESCE(result, ?), status = ? WHERE id = ?',
      [
        result,
        publishedAt,
        publishedBy,
        source,
        result,
        'RESULT_PUBLISHED',
        id,
      ],
    );
  }

  Future<void> publishPeriodResult4(
    String id,
    String result,
    int publishedAt,
    String publishedBy,
    String source,
  ) async {
    await customStatement(
      'UPDATE draw_periods SET result4 = ?, result4PublishedAt = ?, result4PublishedBy = ?, result4Source = ?, result = COALESCE(result, ?), status = ? WHERE id = ?',
      [
        result,
        publishedAt,
        publishedBy,
        source,
        result,
        'RESULT_PUBLISHED',
        id,
      ],
    );
  }

  Future<void> clearPeriodResult3(String id) async {
    await customStatement(
      "UPDATE draw_periods SET result3 = NULL, result3PublishedAt = NULL, result3PublishedBy = NULL, result3Source = NULL WHERE id = ?",
      [id],
    );
  }

  Future<void> clearPeriodResult4(String id) async {
    await customStatement(
      "UPDATE draw_periods SET result4 = NULL, result4PublishedAt = NULL, result4PublishedBy = NULL, result4Source = NULL WHERE id = ?",
      [id],
    );
  }

  Future<void> resetPeriodTickets(String periodId) async {
    // Reset tickets that have lines for this period
    final lines = await customSelect(
      'SELECT ticketId FROM ticket_lines WHERE periodId = ?',
      variables: [Variable.withString(periodId)],
    ).get();
    for (final r in lines) {
      await customStatement(
        "UPDATE tickets SET status='active', prizeAmount=NULL WHERE id = ? AND status IN ('winning','losing')",
        [r.data['ticketId']],
      );
    }
    // Also legacy tickets with drawId matching periodId? Not needed
    // Voided/cancelled lines must keep their marker — otherwise a later
    // validation would treat them as live plays and pay a prize for them.
    await customStatement(
      "UPDATE ticket_lines SET winningStatus=NULL, prizeAmount=NULL "
      "WHERE periodId = ? AND periodStatus != 'cancelled' "
      "AND (winningStatus IS NULL OR winningStatus != 'void')",
      [periodId],
    );
  }

  // ============ AUDIT LOGS ============
  Future<void> insertAuditLog(Map<String, dynamic> a) async {
    await customStatement(
      'INSERT OR REPLACE INTO audit_logs (id, user, action, periodId, oldValue, newValue, timestamp, reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        a['id'],
        a['user'],
        a['action'],
        a['periodId'],
        a['oldValue'],
        a['newValue'],
        a['timestamp'],
        a['reason'],
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getAuditLogs({String? periodId}) async {
    if (periodId != null) {
      final rows = await customSelect(
        'SELECT * FROM audit_logs WHERE periodId = ? ORDER BY timestamp DESC',
        variables: [Variable.withString(periodId)],
      ).get();
      return rows.map((r) => r.data).toList();
    }
    final rows = await customSelect(
      'SELECT * FROM audit_logs ORDER BY timestamp DESC',
    ).get();
    return rows.map((r) => r.data).toList();
  }
}
