import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/api_config.dart';
import '../data/database.dart';
import '../utils/format.dart';

/// JSON backup format identifier written into every exported file.
const String _backupFormat = 'yelottery-json-backup';

/// Tables that must be present in a valid JSON backup.
const List<String> _requiredTables = [
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

  /// Returns the current data as JSON backup bytes (used by "save anywhere").
  Future<Uint8List> readDbBytes() => _buildBackupJsonBytes();

  String suggestedFileName({String reason = 'manual'}) {
    final now = DateTime.now();
    final ts =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'yelottery_backup_${ts}_$reason.json';
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

  /// Kept for API compatibility. There is no longer a local SQLite file;
  /// this returns a representative path for the JSON backup location.
  Future<String> getDbPath() async {
    final doc = await getApplicationDocumentsDirectory();
    return p.join(doc.path, 'yelottery_backup.json');
  }

  // ---------- JSON export helpers ----------

  /// Fetch every table through the typed AppDatabase methods.
  Future<Map<String, dynamic>> _buildBackupMap() async {
    final tables = <String, List<Map<String, dynamic>>>{
      'app_config': await db.getAppConfig(),
      'accounts': await db.getAccounts(),
      'games': await db.getGames(),
      'draws': await db.getAllDraws(),
      'draw_periods': await db.getAllPeriods(),
      'tickets': await db.getTickets(),
      'ticket_lines': await db.getAllTicketLines(),
      'cash_ledger': await db.getCashLedger(),
      'balance_movements': await db.getBalanceMovements(),
      'cash_sessions': await db.getCashSessions(),
      'audit_logs': await db.getAuditLogs(),
      'customers': await db.getCustomers(),
    };
    final plays = <Map<String, dynamic>>[];
    for (final c in tables['customers'] ?? const <Map<String, dynamic>>[]) {
      final id = c['id'] as String?;
      if (id == null || id.isEmpty) continue;
      plays.addAll(await db.getCustomerPlays(id));
    }
    tables['customer_plays'] = plays;
    return {
      'format': _backupFormat,
      'version': 1,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'app': 'YeLottery',
      'tables': tables,
    };
  }

  Future<Uint8List> _buildBackupJsonBytes() async {
    final map = await _buildBackupMap();
    return utf8.encode(jsonEncode(map));
  }

  /// Decode a JSON backup file into a map.
  Future<Map<String, dynamic>> _readBackupMap(String backupPath) async {
    final f = File(backupPath);
    if (!await f.exists()) throw Exception('ملف النسخة غير موجود: $backupPath');
    final decoded = jsonDecode(await f.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw Exception('الملف ليس نسخة YeLottery JSON صالحة');
    }
    return decoded;
  }

  int _countTables(Map<String, dynamic> backup) {
    final tables = backup['tables'];
    if (tables is! Map<String, dynamic>) return 0;
    var n = 0;
    for (final value in tables.values) {
      if (value is List) n += value.length;
    }
    return n;
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
    final bytes = await _buildBackupJsonBytes();
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
            'Backup $reason -> ${saved.join(' | ')} (${bytes.length} bytes, JSON all tables)',
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
    return 'yelottery_backup_${ts}_${reason ?? 'manual'}.json';
  }

  /// Copy an already-written backup file to another path (UI export helper).
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
        .where((f) => f.path.endsWith('.json'))
        .toList();
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    if (files.length <= retention) return;
    for (var i = retention; i < files.length; i++) {
      try {
        await files[i].delete();
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
    final lastAt = cfg['lastAt'] == null ? null : asInt(cfg['lastAt']);
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
        dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')),
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

  /// Validate that the file is a usable YeLottery JSON backup — يتحقق من كااافة الجداول بدون استثناء
  Future<Map<String, dynamic>> validateBackupFile(String backupPath) async {
    final f = File(backupPath);
    if (!await f.exists()) throw Exception('ملف النسخة غير موجود: $backupPath');
    final len = await f.length();
    if (len < 16) throw Exception('ملف النسخة تالف أو فارغ (حجم $len بايت)');

    Map<String, dynamic> decoded;
    try {
      decoded = await _readBackupMap(backupPath);
    } catch (e) {
      if (e.toString().contains('ملف النسخة') ||
          e.toString().contains('نسخة YeLottery'))
        rethrow;
      throw Exception('الملف ليس نسخة YeLottery JSON صالحة: $e');
    }
    if (decoded['format'] != _backupFormat) {
      throw Exception('الملف ليس نسخة YeLottery JSON صالحة');
    }
    final tables = decoded['tables'];
    if (tables is! Map<String, dynamic>) {
      throw Exception('الملف ليس نسخة YeLottery JSON صالحة');
    }
    final missing = _requiredTables
        .where((t) => !tables.containsKey(t))
        .toList();
    if (missing.isNotEmpty) {
      throw Exception(
        'النسخة ناقصة — جداول مفقودة: ${missing.join(', ')} — قد تكون نسخة قديمة أو ملف خاطئ',
      );
    }
    // A backup without the sequence keys resets ticket/serial numbering on
    // restore and produces duplicate ticket IDs. Tolerate a completely empty
    // (old) app_config, but otherwise require both keys to be present.
    final cfgRows = tables['app_config'];
    if (cfgRows is List && cfgRows.isNotEmpty) {
      final cfgKeys = cfgRows
          .map((r) => r is Map ? r['key'] as String? : null)
          .whereType<String>()
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
    }
    return {'valid': true, 'size': len};
  }

  /// Current data counts. With the API-only data layer there is no local
  /// SQLite file, so [size] reports the exported JSON payload size.
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
      tickets = (await db.getTickets()).length;
    } catch (_) {}
    try {
      lines = (await db.getAllTicketLines()).length;
    } catch (_) {}
    try {
      accounts = (await db.getAccounts()).length;
    } catch (_) {}
    try {
      draws = (await db.getAllDraws()).length;
    } catch (_) {}
    try {
      periods = (await db.getAllPeriods()).length;
    } catch (_) {}
    try {
      cash = (await db.getCashLedger()).length;
    } catch (_) {}
    try {
      balance = (await db.getBalanceMovements()).length;
    } catch (_) {}
    try {
      sessions = (await db.getCashSessions()).length;
    } catch (_) {}
    try {
      configs = (await db.getAppConfig()).length;
    } catch (_) {}
    try {
      audits = (await db.getAuditLogs()).length;
    } catch (_) {}
    try {
      dbSize = (await _buildBackupJsonBytes()).length;
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

  /// Count records directly from the JSON backup maps (no SQLite involved).
  Future<Map<String, dynamic>> getBackupStats(String backupPath) async {
    final backup = await _readBackupMap(backupPath);
    final tables = backup['tables'];
    final map = tables is Map<String, dynamic> ? tables : <String, dynamic>{};
    int count(String key) {
      final v = map[key];
      return v is List ? v.length : 0;
    }

    final sz = await File(backupPath).length();
    return {
      'tickets': count('tickets'),
      'lines': count('ticket_lines'),
      'accounts': count('accounts'),
      'draws': count('draws'),
      'periods': count('draw_periods'),
      'cash': count('cash_ledger'),
      'balance': count('balance_movements'),
      'sessions': count('cash_sessions'),
      'configs': count('app_config'),
      'audits': count('audit_logs'),
      'size': sz,
    };
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
    // Compare the current JSON export with the backup contents when the path
    // check is not enough (no local DB file exists to byte-compare anymore).
    bool isIdenticalContent = false;
    try {
      final curBytes = await readDbBytes();
      final bakBytes = await File(backupPath).readAsBytes();
      final n = curBytes.length < bakBytes.length
          ? curBytes.length
          : bakBytes.length;
      final slice = n > 4096 ? 4096 : n;
      isIdenticalContent = _listEquals(
        curBytes.sublist(0, slice),
        bakBytes.sublist(0, slice),
      );
    } catch (_) {}
    final hasCurrentData = cur['hasData'] as bool;
    return {
      'current': cur,
      'backup': bak,
      'isSameAsLastBackup': isSameAsLastBackup,
      'isIdenticalContent': isIdenticalContent,
      'hasCurrentData': hasCurrentData,
      'backupPath': backupPath,
      'totalRecords': _countTables(await _readBackupMap(backupPath)),
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

  /// Execute restore by POSTing the JSON backup to the Laravel API.
  /// لا يتم استبدال ملف محلي — الخادم يعيد بناء البيانات من الـ JSON.
  /// Returns safety backup path if created.
  /// NOTE: After calling this, the app MUST be restarted — data is reloaded
  /// from the server on next launch.
  Future<String?> executeRestore(
    String backupPath, {
    bool createSafety = true,
  }) async {
    await validateBackupFile(backupPath);
    String? safetyPath;
    if (createSafety) {
      try {
        safetyPath = await createSafetyBackup();
      } catch (_) {}
    }
    final backup = await _readBackupMap(backupPath);
    final uri = Uri.parse('${ApiConfig.baseUrl}/restore');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'backup': backup}),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      Map<String, dynamic>? body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {}
      if (body != null) {
        final ok = body['ok'] ?? body['success'];
        final err = body['error'] ?? body['message'];
        if (ok == false) {
          throw Exception('فشل الاستيراد من الخادم: ${err ?? response.body}');
        }
        if (ok == null && err != null) {
          throw Exception('فشل الاستيراد من الخادم: $err');
        }
      }
    } else {
      String msg = response.body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          msg =
              decoded['message']?.toString() ??
              decoded['error']?.toString() ??
              response.body;
        }
      } catch (_) {}
      throw Exception('فشل الاستيراد من الخادم (${response.statusCode}): $msg');
    }
    return safetyPath;
  }

  // Legacy simple restore (kept for compat, not used)
  Future<void> restoreFrom(String backupPath) async {
    await executeRestore(backupPath, createSafety: true);
  }

  Future<void> deleteBackup(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
