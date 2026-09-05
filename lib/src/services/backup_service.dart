import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../data/database.dart';

class BackupService {
  final AppDatabase db;
  BackupService(this.db);

  static const keyEnabled = 'backup_enabled';
  static const keyInterval = 'backup_interval';
  static const keyLastAt = 'backup_last_at';
  static const keyRetention = 'backup_retention';
  static const keyLastPath = 'backup_last_path';

  // Arabic labels for UI
  static const intervals = <String, String>{
    'never': 'إيقاف',
    'hourly': 'كل ساعة',
    '6h': 'كل 6 ساعات',
    '12h': 'كل 12 ساعة',
    'daily': 'يومياً (افتراضي)',
    'weekly': 'أسبوعياً',
  };

  static const intervalDurations = <String, Duration>{
    'never': Duration.zero,
    'hourly': Duration(hours: 1),
    '6h': Duration(hours: 6),
    '12h': Duration(hours: 12),
    'daily': Duration(hours: 24),
    'weekly': Duration(days: 7),
  };

  Future<Map<String, String>> _configMap() async {
    final rows = await db.getAppConfig();
    return {for (var r in rows) r['key'] as String: r['value'] as String};
  }

  Future<Map<String, dynamic>> getBackupConfig() async {
    final cfg = await _configMap();
    final enabled = (cfg[keyEnabled] ?? '1') == '1';
    final interval = cfg[keyInterval] ?? 'daily';
    final lastAtStr = cfg[keyLastAt];
    final lastAt = lastAtStr == null ? null : int.tryParse(lastAtStr);
    final lastPath = cfg[keyLastPath];
    final retention = int.tryParse(cfg[keyRetention] ?? '10') ?? 10;
    final duration = intervalDurations[interval] ?? const Duration(hours: 24);
    DateTime? nextAt;
    if (lastAt != null && duration != Duration.zero && enabled && interval != 'never') {
      nextAt = DateTime.fromMillisecondsSinceEpoch(lastAt).add(duration);
    } else if (lastAt == null && enabled && interval != 'never') {
      nextAt = DateTime.now().add(duration);
    }
    return {
      'enabled': enabled,
      'interval': interval,
      'intervalLabel': intervals[interval] ?? interval,
      'lastAt': lastAt,
      'lastAtDate': lastAt == null ? null : DateTime.fromMillisecondsSinceEpoch(lastAt),
      'lastPath': lastPath,
      'nextAt': nextAt,
      'retention': retention,
      'duration': duration,
    };
  }

  Future<void> setEnabled(bool v) async {
    await db.upsertConfig(keyEnabled, v ? '1' : '0', 'local');
  }

  Future<void> setInterval(String interval) async {
    if (!intervals.containsKey(interval)) throw Exception('Invalid interval: $interval');
    await db.upsertConfig(keyInterval, interval, 'local');
  }

  Future<void> setRetention(int n) async {
    await db.upsertConfig(keyRetention, n.toString(), 'local');
  }

  Future<Directory> _backupDir() async {
    // نحاول جعل النسخ مرئية: على Android نستخدم ExternalStorage إن أمكن
    Directory base;
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        base = ext;
      } else {
        base = await getApplicationDocumentsDirectory();
      }
    } catch (_) {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory(p.join(base.path, 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// مجلد بديل واضح في Downloads (للتصدير اليدوي)
  Future<Directory?> getVisibleExportDir() async {
    try {
      if (Platform.isAndroid) {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          // /storage/emulated/0/Download/YeLotteryBackups
          final dl = Directory('/storage/emulated/0/Download/YeLotteryBackups');
          if (!await dl.exists()) await dl.create(recursive: true);
          return dl;
        }
      }
      if (Platform.isWindows) {
        final doc = await getApplicationDocumentsDirectory();
        final dl = Directory(p.join(doc.path, 'YeLotteryBackups'));
        if (!await dl.exists()) await dl.create(recursive: true);
        return dl;
      }
    } catch (_) {}
    return null;
  }

  Future<String> getDbPath() async {
    final doc = await getApplicationDocumentsDirectory();
    return p.join(doc.path, 'yelottery.sqlite');
  }

  /// Perform a backup now. Returns path of backup file.
  /// يحفظ نسخة داخلية + يحاول نسخها تلقائياً إلى مجلد مرئي (Download) ليبقى بعد حذف التطبيق
  Future<String> performBackup({String reason = 'manual'}) async {
    final dbPath = await getDbPath();
    final src = File(dbPath);
    if (!await src.exists()) {
      throw Exception('قاعدة البيانات غير موجودة: $dbPath');
    }
    try {
      await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    final dir = await _backupDir();
    final now = DateTime.now();
    final ts = '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}_${now.hour.toString().padLeft(2,'0')}${now.minute.toString().padLeft(2,'0')}${now.second.toString().padLeft(2,'0')}';
    final fileName = 'yelottery_backup_${ts}_$reason.sqlite';
    final destPath = p.join(dir.path, fileName);
    await src.copy(destPath);
    try {
      final wal = File('$dbPath-wal');
      if (await wal.exists()) await wal.copy('$destPath-wal');
    } catch (_) {}
    try {
      final shm = File('$dbPath-shm');
      if (await shm.exists()) await shm.copy('$destPath-shm');
    } catch (_) {}

    // نسخ تلقائي إلى مجلد مرئي يبقى بعد حذف التطبيق (Download/YeLotteryBackups)
    try {
      final vis = await getVisibleExportDir();
      if (vis != null) {
        final visPath = p.join(vis.path, fileName);
        await src.copy(visPath);
      }
    } catch (_) {}

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.upsertConfig(keyLastAt, nowMs.toString(), 'local');
    await db.upsertConfig(keyLastPath, destPath, 'local');

    await _pruneOld();

    try {
      await db.insertAuditLog({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'user': 'system',
        'action': reason == 'manual' ? 'BACKUP_MANUAL' : 'BACKUP_AUTO',
        'periodId': null,
        'oldValue': null,
        'newValue': destPath,
        'timestamp': nowMs,
        'reason': 'Backup $reason -> $destPath',
      });
    } catch (_) {}

    return destPath;
  }

  Future<void> _pruneOld() async {
    try {
      final cfg = await _configMap();
      final retention = int.tryParse(cfg[keyRetention] ?? '10') ?? 10;
      final dir = await _backupDir();
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.sqlite')).toList();
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      if (files.length > retention) {
        for (var i = retention; i < files.length; i++) {
          try { await files[i].delete(); } catch (_) {}
          // also delete wal/shm companions
          try { await File('${files[i].path}-wal').delete(); } catch (_) {}
          try { await File('${files[i].path}-shm').delete(); } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Check if auto backup is due and perform it if needed. Returns path if performed, null otherwise.
  Future<String?> performAutoBackupIfDue() async {
    final cfg = await getBackupConfig();
    final enabled = cfg['enabled'] as bool;
    final interval = cfg['interval'] as String;
    if (!enabled) return null;
    if (interval == 'never') return null;
    final duration = cfg['duration'] as Duration;
    if (duration == Duration.zero) return null;
    final lastAt = cfg['lastAt'] as int?;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (lastAt == null) {
      // first time — do backup
      return await performBackup(reason: 'auto');
    }
    final elapsed = nowMs - lastAt;
    if (elapsed >= duration.inMilliseconds) {
      return await performBackup(reason: 'auto');
    }
    return null;
  }

  Future<List<FileSystemEntity>> listBackups() async {
    final List<File> all = [];
    try {
      final dir = await _backupDir();
      if (await dir.exists()) {
        all.addAll(dir.listSync().whereType<File>().where((f) => f.path.endsWith('.sqlite')));
      }
    } catch (_) {}
    // أضف أيضاً النسخ المرئية في Download
    try {
      final vis = await getVisibleExportDir();
      if (vis != null && await vis.exists()) {
        all.addAll(vis.listSync().whereType<File>().where((f) => f.path.endsWith('.sqlite')));
      }
    } catch (_) {}
    // إزالة التكرار حسب الاسم
    final seen = <String>{};
    final uniq = <File>[];
    for (final f in all) {
      final key = p.basename(f.path);
      if (!seen.contains(key)) {
        seen.add(key);
        uniq.add(f);
      }
    }
    uniq.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return uniq;
  }

  Future<String> getBackupDirPath() async {
    final d = await _backupDir();
    return d.path;
  }

  // ============ RESTORE ============

  /// Validate that file is a usable SQLite backup
  Future<Map<String, dynamic>> validateBackupFile(String backupPath) async {
    final f = File(backupPath);
    if (!await f.exists()) throw Exception('ملف النسخة غير موجود: $backupPath');
    final len = await f.length();
    if (len < 1024) throw Exception('ملف النسخة تالف أو فارغ (حجم $len بايت)');
    // Check SQLite header
    final raf = await f.open();
    try {
      final header = Uint8List(16);
      await raf.readInto(header);
      final expected = 'SQLite format 3\x00';
      final actual = String.fromCharCodes(header);
      if (actual != expected) throw Exception('الملف ليس قاعدة بيانات SQLite صالحة');
    } finally {
      await raf.close();
    }
    // Try open with sqlite3 and check integrity + tables
    sqlite3.Database? tmp;
    try {
      tmp = sqlite3.sqlite3.open(backupPath, mode: sqlite3.OpenMode.readOnly);
      final res = tmp.select('PRAGMA integrity_check;');
      final first = res.firstOrNull?['integrity_check'] as String? ?? 'ok';
      if (first != 'ok') throw Exception('فحص السلامة فشل: $first');
      // Check essential tables exist
      final tables = tmp.select("SELECT name FROM sqlite_master WHERE type='table'").map((r) => r['name'] as String).toSet();
      if (!tables.contains('tickets') || !tables.contains('app_config')) {
        throw Exception('النسخة لا تحتوي على جداول النظام (tickets/app_config) — قد تكون ملف خاطئ');
      }
    } catch (e) {
      if (e.toString().contains('فحص السلامة') || e.toString().contains('النسخة لا تحتوي')) rethrow;
      throw Exception('تعذر فتح النسخة كـ SQLite: $e');
    } finally {
      tmp?.close();
    }
    return {'valid': true, 'size': len};
  }

  Future<Map<String, dynamic>> getCurrentStats() async {
    int tickets = 0, lines = 0, accounts = 0;
    int dbSize = 0;
    try { final r = await db.customSelect('SELECT COUNT(*) as c FROM tickets').getSingle(); tickets = r.data['c'] as int; } catch (_) {}
    try { final r = await db.customSelect('SELECT COUNT(*) as c FROM ticket_lines').getSingle(); lines = r.data['c'] as int; } catch (_) {}
    try { final r = await db.customSelect('SELECT COUNT(*) as c FROM accounts').getSingle(); accounts = r.data['c'] as int; } catch (_) {}
    try { final path = await getDbPath(); final f = File(path); if (await f.exists()) dbSize = await f.length(); } catch (_) {}
    return {'tickets': tickets, 'lines': lines, 'accounts': accounts, 'size': dbSize, 'hasData': tickets > 0 || lines > 0};
  }

  Future<Map<String, dynamic>> getBackupStats(String backupPath) async {
    sqlite3.Database? tmp;
    try {
      tmp = sqlite3.sqlite3.open(backupPath, mode: sqlite3.OpenMode.readOnly);
      int tickets = 0, lines = 0, accounts = 0;
      try { tickets = tmp.select('SELECT COUNT(*) as c FROM tickets').first['c'] as int; } catch (_) {}
      try { lines = tmp.select('SELECT COUNT(*) as c FROM ticket_lines').first['c'] as int; } catch (_) {}
      try { accounts = tmp.select('SELECT COUNT(*) as c FROM accounts').first['c'] as int; } catch (_) {}
      final sz = await File(backupPath).length();
      return {'tickets': tickets, 'lines': lines, 'accounts': accounts, 'size': sz};
    } finally {
      tmp?.close();
    }
  }

  /// Prepare info for confirmation dialog — detects dumb-user case
  Future<Map<String, dynamic>> prepareRestore(String backupPath) async {
    await validateBackupFile(backupPath);
    final cur = await getCurrentStats();
    final bak = await getBackupStats(backupPath);
    final cfg = await _configMap();
    final lastPath = cfg[keyLastPath];
    final isSameAsLastBackup = lastPath != null && p.equals(p.normalize(lastPath), p.normalize(backupPath));
    // Compare file hashes by size+modified if same path check not enough
    bool isIdenticalContent = false;
    try {
      final curPath = await getDbPath();
      final curFile = File(curPath);
      final bakFile = File(backupPath);
      if (await curFile.exists()) {
        final curLen = await curFile.length();
        final bakLen = await bakFile.length();
        if (curLen == bakLen) {
          // quick byte compare first 4KB
          final curBytes = await curFile.openRead(0, 4096).first;
          final bakBytes = await bakFile.openRead(0, 4096).first;
          isIdenticalContent = _listEquals(curBytes, bakBytes);
        }
      }
    } catch (_) {}
    final hasCurrentData = cur['hasData'] as bool;
    return {
      'current': cur,
      'backup': bak,
      'isSameAsLastBackup': isSameAsLastBackup,
      'isIdenticalContent': isIdenticalContent,
      'hasCurrentData': hasCurrentData,
      'backupPath': backupPath,
    };
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) if (a[i] != b[i]) return false;
    return true;
  }

  /// Create safety backup before destructive restore
  Future<String?> createSafetyBackup() async {
    try {
      final cur = await getCurrentStats();
      if (!(cur['hasData'] as bool)) return null; // no data to save
      return await performBackup(reason: 'before_restore');
    } catch (_) { return null; }
  }

  /// Execute restore — closes DB, copies backup over current DB file.
  /// Returns safety backup path if created.
  /// NOTE: After calling this, the app MUST be restarted — DB handle is closed.
  Future<String?> executeRestore(String backupPath, {bool createSafety = true}) async {
    await validateBackupFile(backupPath);
    final dbPath = await getDbPath();
    String? safetyPath;
    if (createSafety) {
      try { safetyPath = await createSafetyBackup(); } catch (_) {}
    }
    // Checkpoint and close current DB
    try { await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)'); } catch (_) {}
    try { await db.close(); } catch (_) {}
    // Small delay to let file handles release (Windows)
    await Future.delayed(const Duration(milliseconds: 300));
    // Delete WAL/SHM companions of current DB
    try { final wal = File('$dbPath-wal'); if (await wal.exists()) await wal.delete(); } catch (_) {}
    try { final shm = File('$dbPath-shm'); if (await shm.exists()) await shm.delete(); } catch (_) {}
    // Copy backup over
    final src = File(backupPath);
    // Ensure parent dir exists
    final parent = Directory(p.dirname(dbPath));
    if (!await parent.exists()) await parent.create(recursive: true);
    // If db file exists, delete first (Windows lock workaround)
    try { final cur = File(dbPath); if (await cur.exists()) await cur.delete(); } catch (_) {}
    await src.copy(dbPath);
    // Also copy wal/shm if backup had them (rare)
    try { final bw = File('$backupPath-wal'); if (await bw.exists()) await bw.copy('$dbPath-wal'); } catch (_) {}
    try { final bs = File('$backupPath-shm'); if (await bs.exists()) await bs.copy('$dbPath-shm'); } catch (_) {}

    // Audit to new DB? Can't — DB was closed. We log to a marker file instead
    try {
      final marker = File(p.join(p.dirname(dbPath), 'restore_marker.txt'));
      await marker.writeAsString('Restored from $backupPath at ${DateTime.now().toIso8601String()} safety=$safetyPath');
    } catch (_) {}

    return safetyPath;
  }

  // Legacy simple restore (kept for compat, not used)
  Future<void> restoreFrom(String backupPath) async {
    await executeRestore(backupPath, createSafety: true);
  }

  Future<void> deleteBackup(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
    try { final w = File('$path-wal'); if (await w.exists()) await w.delete(); } catch (_) {}
    try { final s = File('$path-shm'); if (await s.exists()) await s.delete(); } catch (_) {}
  }
}
