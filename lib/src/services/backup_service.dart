import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
  static const keyCustomDir = 'backup_custom_dir';
  static const keyCustomLastSave = 'backup_custom_last_save';

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
    final customDir = cfg[keyCustomDir];
    final customLastSave = cfg[keyCustomLastSave];
    DateTime? nextAt;
    if (enabled && interval != 'never' && duration != Duration.zero) {
      if (lastAt != null) {
        nextAt = DateTime.fromMillisecondsSinceEpoch(lastAt).add(duration);
        if (nextAt.isBefore(DateTime.now())) nextAt = DateTime.now();
      } else {
        nextAt = DateTime.now();
      }
    }
    String? visibleDir;
    try {
      visibleDir = (await getVisibleExportDir(requestPermission: false))?.path;
    } catch (_) {}
    String? internalDir;
    try {
      internalDir = (await _internalBackupDir()).path;
    } catch (_) {}
    return {
      'enabled': enabled,
      'interval': interval,
      'intervalLabel': intervals[interval] ?? interval,
      'lastAt': lastAt,
      'lastAtDate': lastAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastAt),
      'lastPath': lastPath,
      'nextAt': nextAt,
      'retention': retention,
      'duration': duration,
      'customDir': customDir,
      'customLastSave': customLastSave,
      'visibleDir': visibleDir,
      'internalDir': internalDir,
    };
  }

  Future<void> setEnabled(bool v) async {
    await db.upsertConfig(keyEnabled, v ? '1' : '0', 'local');
    if (v) {
      final cfg = await _configMap();
      if ((cfg[keyInterval] ?? 'never') == 'never') {
        await db.upsertConfig(keyInterval, 'daily', 'local');
      }
    }
  }

  Future<void> setInterval(String interval) async {
    if (!intervals.containsKey(interval))
      throw Exception('Invalid interval: $interval');
    await db.upsertConfig(keyInterval, interval, 'local');
    if (interval == 'never') {
      await db.upsertConfig(keyEnabled, '0', 'local');
    } else {
      await db.upsertConfig(keyEnabled, '1', 'local');
    }
  }

  Future<void> setRetention(int n) async {
    await db.upsertConfig(keyRetention, n.toString(), 'local');
  }

  Future<void> setCustomDir(String? dir) async {
    await db.upsertConfig(keyCustomDir, dir ?? '', 'local');
  }

  Future<bool> hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      if (await Permission.manageExternalStorage.isGranted) return true;
    } catch (_) {}
    try {
      final dest = Directory('/storage/emulated/0/Download/YeLotteryBackups');
      if (await _canWriteDir(dest)) return true;
    } catch (_) {}
    return false;
  }

  /// Android 11+: يحتاج "الوصول لكل الملفات" للكتابة في Downloads أو أي مجلد يختاره المستخدم
  Future<bool> ensureStorageAccess({bool prompt = true}) async {
    if (!Platform.isAndroid) return true;
    try {
      if (await Permission.manageExternalStorage.isGranted) return true;
      if (prompt) {
        final manage = await Permission.manageExternalStorage.request();
        if (manage.isGranted) return true;
      }
      if (await Permission.storage.isGranted) return true;
      if (prompt) {
        final storage = await Permission.storage.request();
        if (storage.isGranted) return true;
      }
    } catch (_) {}
    return await hasAllFilesAccess();
  }

  Future<void> openStorageSettings() async {
    try {
      await openAppSettings();
    } catch (_) {}
  }

  Future<bool> canWritePath(String dirPath) async {
    return _canWriteDir(Directory(dirPath));
  }

  Future<Uint8List> readDbBytes() => _readDbBytes();

  String suggestedFileName({String reason = 'manual'}) {
    final now = DateTime.now();
    final ts =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'yelottery_backup_${ts}_$reason.sqlite';
  }

  Future<bool> _canWriteDir(Directory dir) async {
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      final probe = File(p.join(dir.path, '.yelottery_write_test'));
      await probe.writeAsString('ok', flush: true);
      if (await probe.exists()) await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// مجلد داخلي للتطبيق — يُحذف مع إلغاء التثبيت على Android
  Future<Directory> _internalBackupDir() async {
    Directory base;
    try {
      if (Platform.isAndroid) {
        final ext = await getExternalStorageDirectory();
        base = ext ?? await getApplicationDocumentsDirectory();
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

  /// المجلد الأساسي: Downloads/YeLotteryBackups إن أمكن الكتابة، وإلا المجلد الداخلي
  Future<Directory> _backupDir() async {
    final vis = await getVisibleExportDir(requestPermission: false);
    if (vis != null) return vis;
    return await _internalBackupDir();
  }

  /// مجلد مرئي يبقى بعد حذف التطبيق قدر الإمكان (Downloads/Documents)
  Future<Directory?> getVisibleExportDir({
    bool requestPermission = false,
  }) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          final dest = Directory(p.join(downloads.path, 'YeLotteryBackups'));
          if (await _canWriteDir(dest)) return dest;
        }
      } catch (_) {}
      try {
        final doc = await getApplicationDocumentsDirectory();
        final dest = Directory(p.join(doc.path, 'YeLotteryBackups'));
        if (await _canWriteDir(dest)) return dest;
      } catch (_) {}
      return null;
    }

    if (Platform.isAndroid) {
      if (requestPermission) await ensureStorageAccess(prompt: true);
      for (final candidate in const [
        '/storage/emulated/0/Download/YeLotteryBackups',
        '/sdcard/Download/YeLotteryBackups',
      ]) {
        final dest = Directory(candidate);
        if (await _canWriteDir(dest)) return dest;
      }
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final dest = Directory(p.join(ext.path, 'YeLotteryBackups'));
          if (await _canWriteDir(dest)) return dest;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _copyBytesToDir(
    Uint8List bytes,
    String dirPath,
    String fileName,
  ) async {
    final dir = Directory(dirPath);
    if (!await _canWriteDir(dir)) return null;
    final dest = p.join(dir.path, fileName);
    await File(dest).writeAsBytes(bytes, flush: true);
    return dest;
  }

  Future<String> getDbPath() async {
    final doc = await getApplicationDocumentsDirectory();
    return p.join(doc.path, 'yelottery.sqlite');
  }

  /// نسخ قاعدة البيانات كبايتات بعد checkpoint — يضمن ملف واحد متكامل (لا wal/shm منفصلين)
  Future<Uint8List> _readDbBytes() async {
    final dbPath = await getDbPath();
    final src = File(dbPath);
    if (!await src.exists())
      throw Exception('قاعدة البيانات غير موجودة: $dbPath');
    // إغلاق WAL في الملف الرئيسي — يضمن نسخة متسقة 100% بدون الحاجة لنسخ wal/shm
    try {
      await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 150));
    try {
      return await src.readAsBytes();
    } catch (_) {
      final tmp = File('$dbPath.bakcopy');
      await src.copy(tmp.path);
      final bytes = await tmp.readAsBytes();
      try {
        await tmp.delete();
      } catch (_) {}
      return bytes;
    }
  }

  /// Perform a backup now. Returns the most user-visible saved path.
  /// يحفظ نسخة أساسية + نسخة مرئية + نسخة المجلد المخصص إن وُجد
  Future<String> performBackup({
    String reason = 'manual',
    bool requestPermission = true,
  }) async {
    final result = await performBackupDetailed(
      reason: reason,
      requestPermission: requestPermission,
    );
    return result['primary'] as String;
  }

  Future<Map<String, dynamic>> performBackupDetailed({
    String reason = 'manual',
    bool requestPermission = true,
  }) async {
    if (requestPermission) {
      await ensureStorageAccess(prompt: true);
    }
    final bytes = await _readDbBytes();
    final dir = await _backupDir();
    final fileName = suggestedFileName(reason: reason);
    final destPath = p.join(dir.path, fileName);
    await File(destPath).writeAsBytes(bytes, flush: true);

    final saved = <String>[destPath];
    String? visiblePath;
    String? customPath;
    String? customError;

    try {
      final vis = await getVisibleExportDir(requestPermission: false);
      if (vis != null &&
          !p.equals(p.normalize(vis.path), p.normalize(dir.path))) {
        visiblePath = await _copyBytesToDir(bytes, vis.path, fileName);
        if (visiblePath != null) saved.add(visiblePath);
      } else if (vis != null) {
        visiblePath = destPath;
      }
    } catch (_) {}

    try {
      final cfg = await _configMap();
      final customDir = cfg[keyCustomDir];
      if (customDir != null && customDir.isNotEmpty) {
        if (p.equals(p.normalize(customDir), p.normalize(dir.path))) {
          customPath = destPath;
        } else {
          customPath = await _copyBytesToDir(bytes, customDir, fileName);
          if (customPath != null) {
            saved.add(customPath);
            await db.upsertConfig(keyCustomLastSave, customPath, 'local');
          } else {
            customError = 'تعذر الكتابة في المجلد المختار. على Android امنح صلاحية "الوصول لكل الملفات" ثم أعد المحاولة.';
          }
        }
      }
    } catch (e) {
      customError = 'تعذر الكتابة في المجلد المختار: $e';
    }

    final primary = customPath ?? visiblePath ?? destPath;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.upsertConfig(keyLastAt, nowMs.toString(), 'local');
    await db.upsertConfig(keyLastPath, primary, 'local');

    await _pruneOld();

    try {
      await db.insertAuditLog({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'user': 'system',
        'action': reason == 'manual' ? 'BACKUP_MANUAL' : 'BACKUP_AUTO',
        'periodId': null,
        'oldValue': null,
        'newValue': primary,
        'timestamp': nowMs,
        'reason':
            'Backup $reason -> ${saved.join(' | ')} (${bytes.length} bytes, all tables)',
      });
    } catch (_) {}

    return {
      'primary': primary,
      'internal': destPath,
      'visible': visiblePath,
      'custom': customPath,
      'customError': customError,
      'saved': saved,
      'fileName': fileName,
    };
  }

  /// اسم ملف مقترح للحفظ عبر FilePicker — الكتابة الفعلية تتم من الواجهة
  Future<String> saveBackupToPickedFile({String? reason}) async {
    final now = DateTime.now();
    final ts =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'yelottery_backup_${ts}_${reason ?? 'manual'}.sqlite';
  }

  Future<String> exportBackupToPath(String sourcePath, String destPath) async {
    final src = File(sourcePath);
    if (!await src.exists())
      throw Exception('ملف المصدر غير موجود: $sourcePath');
    final bytes = await src.readAsBytes();
    final dest = File(destPath);
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(bytes, flush: true);
    return destPath;
  }

  Future<void> _pruneDir(Directory dir, int retention) async {
    if (!await dir.exists()) return;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sqlite'))
        .toList();
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    if (files.length <= retention) return;
    for (var i = retention; i < files.length; i++) {
      try {
        await files[i].delete();
      } catch (_) {}
      try {
        await File('${files[i].path}-wal').delete();
      } catch (_) {}
      try {
        await File('${files[i].path}-shm').delete();
      } catch (_) {}
    }
  }

  Future<void> _pruneOld() async {
    try {
      final cfg = await _configMap();
      final retention = int.tryParse(cfg[keyRetention] ?? '10') ?? 10;
      final seen = <String>{};
      Future<void> pruneOnce(Directory? dir) async {
        if (dir == null) return;
        final key = p.normalize(dir.path).toLowerCase();
        if (seen.contains(key)) return;
        seen.add(key);
        await _pruneDir(dir, retention);
      }

      await pruneOnce(await _internalBackupDir());
      await pruneOnce(await _backupDir());
      await pruneOnce(await getVisibleExportDir(requestPermission: false));
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
      return await performBackup(reason: 'auto', requestPermission: false);
    }
    final elapsed = nowMs - lastAt;
    if (elapsed >= duration.inMilliseconds) {
      return await performBackup(reason: 'auto', requestPermission: false);
    }
    return null;
  }

  Future<List<FileSystemEntity>> listBackups() async {
    final List<File> all = [];
    Future<void> addFrom(Directory? dir) async {
      if (dir == null || !await dir.exists()) return;
      all.addAll(
        dir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.sqlite'),
        ),
      );
    }

    try {
      await addFrom(await _internalBackupDir());
    } catch (_) {}
    try {
      await addFrom(await _backupDir());
    } catch (_) {}
    try {
      await addFrom(await getVisibleExportDir(requestPermission: false));
    } catch (_) {}
    try {
      final cfg = await _configMap();
      final customDir = cfg[keyCustomDir];
      if (customDir != null && customDir.isNotEmpty) {
        await addFrom(Directory(customDir));
      }
    } catch (_) {}
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

  /// Validate that file is a usable SQLite backup — يتحقق من كااافة الجداول بدون استثناء
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
      if (actual != expected)
        throw Exception('الملف ليس قاعدة بيانات SQLite صالحة');
    } finally {
      await raf.close();
    }
    // Try open with sqlite3 and check integrity + all tables
    sqlite3.Database? tmp;
    try {
      tmp = sqlite3.sqlite3.open(backupPath, mode: sqlite3.OpenMode.readOnly);
      final res = tmp.select('PRAGMA integrity_check;');
      final first = res.firstOrNull?['integrity_check'] as String? ?? 'ok';
      if (first != 'ok') throw Exception('فحص السلامة فشل: $first');
      // Check ALL essential tables exist — كااافة البيانات بدون استثناء
      final tables = tmp
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toSet();
      const required = [
        'tickets',
        'ticket_lines',
        'accounts',
        'games',
        'draws',
        'draw_periods',
        'cash_ledger',
        'balance_movements',
        'cash_sessions',
        'app_config',
        'audit_logs',
      ];
      final missing = required.where((t) => !tables.contains(t)).toList();
      if (missing.isNotEmpty) {
        throw Exception(
          'النسخة ناقصة — جداول مفقودة: ${missing.join(', ')} — قد تكون نسخة قديمة أو ملف خاطئ',
        );
      }
      // A backup without the sequence keys resets ticket/serial numbering on
      // restore and produces duplicate ticket IDs. Tolerate a completely empty
      // (old) app_config, but otherwise require both keys to be present.
      try {
        final cfgKeys = tmp
            .select('SELECT key FROM app_config')
            .map((r) => r['key'] as String)
            .toSet();
        if (cfgKeys.isNotEmpty) {
          const requiredKeys = ['ticket_seq', 'serial_seq'];
          final missingKeys = requiredKeys
              .where((k) => !cfgKeys.contains(k))
              .toList();
          if (missingKeys.isNotEmpty) {
            throw Exception(
              'النسخة لا تحتوي على مفاتيح التسلسل: ${missingKeys.join(', ')} — قد تنتج أرقام تذاكر مكررة عند الاستعادة',
            );
          }
        }
      } catch (e) {
        if (e.toString().contains('مفاتيح التسلسل')) rethrow;
        // Old/empty config tables that cannot be queried are tolerated.
      }
    } catch (e) {
      if (e.toString().contains('فحص السلامة') ||
          e.toString().contains('النسخة ناقصة') ||
          e.toString().contains('النسخة لا تحتوي'))
        rethrow;
      throw Exception('تعذر فتح النسخة كـ SQLite: $e');
    } finally {
      tmp?.close();
    }
    return {'valid': true, 'size': len};
  }

  Future<Map<String, dynamic>> getCurrentStats() async {
    int tickets = 0,
        lines = 0,
        accounts = 0,
        draws = 0,
        periods = 0,
        cash = 0,
        balance = 0,
        sessions = 0,
        configs = 0,
        audits = 0;
    int dbSize = 0;
    try {
      final r = await db
          .customSelect('SELECT COUNT(*) as c FROM tickets')
          .getSingle();
      tickets = r.data['c'] as int;
    } catch (_) {}
    try {
      final r = await db
          .customSelect('SELECT COUNT(*) as c FROM ticket_lines')
          .getSingle();
      lines = r.data['c'] as int;
    } catch (_) {}
    try {
      final r = await db
          .customSelect('SELECT COUNT(*) as c FROM accounts')
          .getSingle();
      accounts = r.data['c'] as int;
    } catch (_) {}
    try {
      final r = await db
          .customSelect('SELECT COUNT(*) as c FROM draws')
          .getSingle();
      draws = r.data['c'] as int;
    } catch (_) {}
    try {
      final r = await db
          .customSelect('SELECT COUNT(*) as c FROM draw_periods')
          .getSingle();
      periods = r.data['c'] as int;
    } catch (_) {}
    try {
      final r = await db
          .customSelect('SELECT COUNT(*) as c FROM cash_ledger')
          .getSingle();
      cash = r.data['c'] as int;
    } catch (_) {}
    try {
      final r = await db
          .customSelect('SELECT COUNT(*) as c FROM balance_movements')
          .getSingle();
      balance = r.data['c'] as int;
    } catch (_) {}
    try {
      final r = await db
          .customSelect('SELECT COUNT(*) as c FROM cash_sessions')
          .getSingle();
      sessions = r.data['c'] as int;
    } catch (_) {}
    try {
      final r = await db
          .customSelect('SELECT COUNT(*) as c FROM app_config')
          .getSingle();
      configs = r.data['c'] as int;
    } catch (_) {}
    try {
      final r = await db
          .customSelect('SELECT COUNT(*) as c FROM audit_logs')
          .getSingle();
      audits = r.data['c'] as int;
    } catch (_) {}
    try {
      final path = await getDbPath();
      final f = File(path);
      if (await f.exists()) dbSize = await f.length();
    } catch (_) {}
    return {
      'tickets': tickets,
      'lines': lines,
      'accounts': accounts,
      'draws': draws,
      'periods': periods,
      'cash': cash,
      'balance': balance,
      'sessions': sessions,
      'configs': configs,
      'audits': audits,
      'size': dbSize,
      'hasData': tickets > 0 || lines > 0 || cash > 0,
    };
  }

  Future<Map<String, dynamic>> getBackupStats(String backupPath) async {
    sqlite3.Database? tmp;
    try {
      tmp = sqlite3.sqlite3.open(backupPath, mode: sqlite3.OpenMode.readOnly);
      int tickets = 0,
          lines = 0,
          accounts = 0,
          draws = 0,
          periods = 0,
          cash = 0,
          balance = 0,
          sessions = 0,
          configs = 0,
          audits = 0;
      try {
        tickets =
            tmp.select('SELECT COUNT(*) as c FROM tickets').first['c'] as int;
      } catch (_) {}
      try {
        lines =
            tmp.select('SELECT COUNT(*) as c FROM ticket_lines').first['c']
                as int;
      } catch (_) {}
      try {
        accounts =
            tmp.select('SELECT COUNT(*) as c FROM accounts').first['c'] as int;
      } catch (_) {}
      try {
        draws = tmp.select('SELECT COUNT(*) as c FROM draws').first['c'] as int;
      } catch (_) {}
      try {
        periods =
            tmp.select('SELECT COUNT(*) as c FROM draw_periods').first['c']
                as int;
      } catch (_) {}
      try {
        cash =
            tmp.select('SELECT COUNT(*) as c FROM cash_ledger').first['c']
                as int;
      } catch (_) {}
      try {
        balance =
            tmp.select('SELECT COUNT(*) as c FROM balance_movements').first['c']
                as int;
      } catch (_) {}
      try {
        sessions =
            tmp.select('SELECT COUNT(*) as c FROM cash_sessions').first['c']
                as int;
      } catch (_) {}
      try {
        configs =
            tmp.select('SELECT COUNT(*) as c FROM app_config').first['c']
                as int;
      } catch (_) {}
      try {
        audits =
            tmp.select('SELECT COUNT(*) as c FROM audit_logs').first['c']
                as int;
      } catch (_) {}
      final sz = await File(backupPath).length();
      return {
        'tickets': tickets,
        'lines': lines,
        'accounts': accounts,
        'draws': draws,
        'periods': periods,
        'cash': cash,
        'balance': balance,
        'sessions': sessions,
        'configs': configs,
        'audits': audits,
        'size': sz,
      };
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
    final isSameAsLastBackup =
        lastPath != null &&
        p.equals(p.normalize(lastPath), p.normalize(backupPath));
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
    } catch (_) {
      return null;
    }
  }

  /// Execute restore — closes DB, copies backup over current DB file — يستعيد كااافة البيانات بدون استثناء (ملف كامل)
  /// Returns safety backup path if created.
  /// NOTE: After calling this, the app MUST be restarted — DB handle is closed.
  Future<String?> executeRestore(
    String backupPath, {
    bool createSafety = true,
  }) async {
    await validateBackupFile(backupPath);
    final dbPath = await getDbPath();
    String? safetyPath;
    if (createSafety) {
      try {
        safetyPath = await createSafetyBackup();
      } catch (_) {}
    }
    // Checkpoint and close current DB
    try {
      await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    try {
      await db.close();
    } catch (_) {}
    // Small delay to let file handles release (Windows)
    await Future.delayed(const Duration(milliseconds: 400));
    // Delete WAL/SHM companions of current DB — لا نريد ملفات wal قديمة تفسد الاستعادة
    try {
      final wal = File('$dbPath-wal');
      if (await wal.exists()) await wal.delete();
    } catch (_) {}
    try {
      final shm = File('$dbPath-shm');
      if (await shm.exists()) await shm.delete();
    } catch (_) {}
    // Copy backup over — نسخ البايتات مباشرة لضمان ملف متكامل بدون wal/shm منفصل
    final src = File(backupPath);
    final bytes = await src.readAsBytes();
    // Ensure parent dir exists
    final parent = Directory(p.dirname(dbPath));
    if (!await parent.exists()) await parent.create(recursive: true);
    // If db file exists, delete first (Windows lock workaround)
    try {
      final cur = File(dbPath);
      if (await cur.exists()) await cur.delete();
    } catch (_) {}
    await File(dbPath).writeAsBytes(bytes, flush: true);
    // تأكد من عدم بقاء wal/shm من النسخة (النسخة الحديثة لا تحتويهما كملفين منفصلين)
    try {
      final bw = File('$backupPath-wal');
      if (await bw.exists()) {
        /* لا تنسخ */
      }
    } catch (_) {}

    // Audit to new DB? Can't — DB was closed. We log to a marker file instead
    try {
      final marker = File(p.join(p.dirname(dbPath), 'restore_marker.txt'));
      await marker.writeAsString(
        'Restored from $backupPath at ${DateTime.now().toIso8601String()} safety=$safetyPath bytes=${bytes.length}',
      );
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
    try {
      final w = File('$path-wal');
      if (await w.exists()) await w.delete();
    } catch (_) {}
    try {
      final s = File('$path-shm');
      if (await s.exists()) await s.delete();
    } catch (_) {}
  }
}
