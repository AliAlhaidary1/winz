import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database.dart';
import '../../services/backup_service.dart';
import '../../utils/format.dart';
import '../../utils/responsive.dart';

class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({super.key});
  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  bool _loading = true;
  bool _enabled = true;
  String _interval = 'daily';
  int? _lastAt;
  String? _lastPath;
  DateTime? _nextAt;
  String? _dirPath;
  String? _visibleDir;
  String? _customDir;
  List<FileSystemEntity> _backups = [];
  bool _backingUp = false;
  bool _restoring = false;
  bool _hasStorageAccess = true;
  bool _customDirWritable = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = context.read<AppDatabase>();
    final svc = BackupService(db);
    final access = await svc.hasAllFilesAccess();
    final cfg = await svc.getBackupConfig();
    final dir = await svc.getBackupDirPath();
    final list = await svc.listBackups();
    String? custom = cfg['customDir'] as String?;
    if (custom != null && custom.isEmpty) custom = null;
    var customOk = true;
    if (custom != null) customOk = await svc.canWritePath(custom);
    if (!mounted) return;
    setState(() {
      _enabled = cfg['enabled'] as bool;
      _interval = cfg['interval'] as String;
      _lastAt = cfg['lastAt'] == null ? null : asInt(cfg['lastAt']);
      _lastPath = cfg['lastPath'] as String?;
      _nextAt = cfg['nextAt'] as DateTime?;
      _dirPath = dir;
      _visibleDir = cfg['visibleDir'] as String?;
      _customDir = custom;
      _hasStorageAccess = access;
      _customDirWritable = customOk;
      _backups = list;
      _loading = false;
    });
  }

  Future<void> _requestStorageAccess() async {
    final svc = BackupService(context.read<AppDatabase>());
    final ok = await svc.ensureStorageAccess(prompt: true);
    if (!ok) {
      if (mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text(
              'File permission required',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'On Android 11+, you must enable "Allow access to all files" for this app to save to Downloads or any folder you choose.',
              style: TextStyle(fontSize: 12),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Later'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
        if (go == true) await svc.openStorageSettings();
      }
    }
    await _load();
  }

  Future<void> _pickCustomDir() async {
    try {
      final svc = BackupService(context.read<AppDatabase>());
      await svc.ensureStorageAccess(prompt: true);
      final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle:
            'Choose default backup folder — persists after app uninstall',
      );
      if (dir == null) return;
      final writable = await svc.canWritePath(dir);
      if (!writable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cannot write to this folder. Enable "All files access" permission in the app settings, then choose again.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 6),
            ),
          );
        }
        await _requestStorageAccess();
        return;
      }
      await svc.setCustomDir(dir);
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Default folder saved: $dir\nEvery automatic/manual backup will also be copied there',
            ),
            backgroundColor: const Color(0xFF0B8A3E),
            duration: const Duration(seconds: 4),
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to choose folder: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Future<void> _clearCustomDir() async {
    final svc = BackupService(context.read<AppDatabase>());
    await svc.setCustomDir(null);
    await _load();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Custom folder removed — only default folders will be used',
          ),
        ),
      );
  }

  Future<void> _saveAnywhere() async {
    setState(() => _backingUp = true);
    try {
      final svc = BackupService(context.read<AppDatabase>());
      final bytes = await svc.readDbBytes();
      final suggested = svc.suggestedFileName(reason: 'manual');
      String? picked;
      var saveUnsupported = false;
      try {
        // On Android the bytes must be passed or it fails immediately before the dialog opens
        picked = await FilePicker.platform.saveFile(
          dialogTitle: 'Save the backup anywhere you like',
          fileName: suggested,
          bytes: bytes,
          type: FileType.any,
        );
      } catch (_) {
        saveUnsupported = true;
      }
      if ((picked == null || picked.isEmpty) && saveUnsupported) {
        final dir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Choose save folder',
        );
        if (dir != null) {
          picked = '$dir\\$suggested';
          await File(picked).writeAsBytes(bytes, flush: true);
        }
      }
      if (picked == null || picked.isEmpty) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selection cancelled'),
              backgroundColor: Colors.orange,
            ),
          );
        return;
      }
      try {
        await svc.performBackup(reason: 'manual', requestPermission: false);
      } catch (_) {}
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved ✅\n$picked'),
            backgroundColor: const Color(0xFF0B8A3E),
            duration: const Duration(seconds: 5),
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Custom save failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<void> _toggleEnabled(bool v) async {
    final svc = BackupService(context.read<AppDatabase>());
    await svc.setEnabled(v);
    setState(() => _enabled = v);
    await _load();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            v ? 'Automatic backup enabled' : 'Automatic backup disabled',
          ),
          backgroundColor: const Color(0xFF0B8A3E),
        ),
      );
  }

  Future<void> _changeInterval(String? v) async {
    if (v == null) return;
    final svc = BackupService(context.read<AppDatabase>());
    await svc.setInterval(v);
    await _load();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Interval changed to: ${BackupService.intervals[v]}'),
          backgroundColor: const Color(0xFF0B8A3E),
        ),
      );
  }

  Future<void> _doBackup() async {
    setState(() => _backingUp = true);
    try {
      final svc = BackupService(context.read<AppDatabase>());
      await svc.ensureStorageAccess(prompt: true);
      final result = await svc.performBackupDetailed(
        reason: 'manual',
        requestPermission: false,
      );
      await _load();
      if (!mounted) return;
      final saved = (result['saved'] as List).map((e) => e.toString()).toList();
      final customError = result['customError'] as String?;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(
            customError == null
                ? 'Backup successful ✅'
                : 'Backup completed with a warning',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: customError == null
                  ? const Color(0xFF0B8A3E)
                  : Colors.deepOrange,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Saved to:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              ...saved.map(
                (path) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      path,
                      style: const TextStyle(fontSize: 11),
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
              if (customError != null) ...[
                const SizedBox(height: 8),
                Text(
                  customError,
                  style: const TextStyle(fontSize: 11, color: Colors.red),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  // ============ RESTORE ============
  Future<void> _pickAndRestore() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (res == null || res.files.single.path == null) return;
      final path = res.files.single.path!;
      await _confirmAndRestore(path);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick file: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Future<void> _confirmAndRestore(String backupPath) async {
    final svc = BackupService(context.read<AppDatabase>());
    Map<String, dynamic>? info;
    try {
      // show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF0B8A3E)),
        ),
      );
      info = await svc.prepareRestore(backupPath);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted)
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 6),
                Text(
                  'Invalid file',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Text(e.toString(), style: const TextStyle(fontSize: 12)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      return;
    }

    final cur = info['current'] as Map<String, dynamic>;
    final bak = info['backup'] as Map<String, dynamic>;
    final isSame = info['isSameAsLastBackup'] as bool;
    final isIdentical = info['isIdenticalContent'] as bool;
    final hasData = info['hasCurrentData'] as bool;

    // Professional confirmation dialog — fix: vars outside StatefulBuilder so they persist
    bool checked = false;
    bool understoodDumb = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setS) {
          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Confirm import — data will be replaced',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Stats comparison
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Current data',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tickets: ${cur['tickets']}  •  Lines: ${cur['lines']}  •  Accounts: ${cur['accounts']}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  Text(
                                    'Size: ${asInt(cur['size']) / 1024 > 0 ? (asInt(cur['size']) / 1024).toStringAsFixed(1) : '0'} KB',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.grey.shade300,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Selected backup',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0B8A3E),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tickets: ${bak['tickets']}  •  Lines: ${bak['lines']}  •  Accounts: ${bak['accounts']}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  Text(
                                    'Size: ${asInt(bak['size']) / 1024 > 0 ? (asInt(bak['size']) / 1024).toStringAsFixed(1) : '0'} KB',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (hasData)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 16,
                            color: Colors.orange,
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Current data exists — a safety backup (before_restore) will be created automatically before replacement so nothing is lost.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isSame || isIdentical)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.lightbulb,
                            size: 16,
                            color: Colors.deepOrange,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isSame
                                  ? 'Smart warning: this is the same backup you just created (last backup) — importing it will change nothing and may be pointless. Are you sure you want to continue?'
                                  : 'Smart warning: the backup content is almost identical to the current data — importing may not be necessary.',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepOrange,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '⚠️ After import, the database will be closed and the app must be restarted. Current data will be completely replaced.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      backupPath,
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: checked,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'I understand that the current data will be replaced',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => setS(() => checked = v ?? false),
                  ),
                  if (isSame || isIdentical)
                    CheckboxListTile(
                      value: understoodDumb,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'I understand this is the same backup and importing may not be necessary',
                        style: TextStyle(fontSize: 11),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => setS(() => understoodDumb = v ?? false),
                    ),
                  // hidden confirm button logic uses checked
                  Builder(
                    builder: (_) {
                      // store in dialog state via setS closure — we need to pass back via Navigator
                      // Use WillPop to inject logic — simpler: use outer variable
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final needSecond = isSame || isIdentical;
                  if (!checked || (needSecond && !understoodDumb)) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'You must confirm understanding before continuing',
                        ),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  Navigator.pop(c, true);
                },
                child: const Text('Import Now'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;
    // Execute restore
    setState(() => _restoring = true);
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF0B8A3E)),
              const SizedBox(height: 12),
              const Text(
                'Importing...',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                backupPath.split('/').last.split('\\').last,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
      final safety = await svc.executeRestore(
        backupPath,
        createSafety: hasData,
      );
      if (mounted) Navigator.pop(context); // close loading
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF0B8A3E)),
              SizedBox(width: 6),
              Text(
                'Import successful ✅',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0B8A3E),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The database has been replaced with the selected backup.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              if (safety != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shield,
                        size: 14,
                        color: Color(0xFF0B8A3E),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Safety backup saved:\n${safety.split('/').last.split('\\').last}',
                          style: const TextStyle(fontSize: 10),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'You must restart the app now to apply the changes.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close (restart manually)'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B8A3E),
              ),
              onPressed: () {
                // Try to exit app — user must restart
                SystemNavigator.pop();
                Future.delayed(
                  const Duration(milliseconds: 300),
                  () => exit(0),
                );
              },
              child: const Text('Exit app now'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _shareBackup(String path) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          text: 'YeLottery backup — ${path.split('/').last.split('\\').last}',
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Path copied'),
          backgroundColor: Color(0xFF0B8A3E),
        ),
      );
  }

  Future<void> _openFolder(String dir) async {
    try {
      final d = Directory(dir);
      if (!await d.exists()) {
        await d.create(recursive: true);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Folder created: $dir'),
              backgroundColor: Colors.orange,
            ),
          );
      }
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [
          dir,
        ], mode: ProcessStartMode.detached);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Folder opened: $dir'),
              backgroundColor: const Color(0xFF0B8A3E),
            ),
          );
        return;
      } else if (Platform.isAndroid) {
        await _copyPath(dir);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Path: $dir — copied, use a file manager'),
              backgroundColor: Colors.blue,
            ),
          );
        return;
      } else {
        await _copyPath(dir);
        return;
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot open folder: $e — path copied'),
            backgroundColor: Colors.orange,
          ),
        );
      await _copyPath(dir);
    }
  }

  Future<void> _exportToVisible(String path) async {
    try {
      final svc = BackupService(context.read<AppDatabase>());
      await svc.ensureStorageAccess(prompt: true);
      final destDir = await svc.getVisibleExportDir(requestPermission: false);
      if (destDir == null) throw Exception('No export folder available');
      final name = path.split('/').last.split('\\').last;
      final dest = File('${destDir.path}/$name');
      await File(path).copy(dest.path);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to: ${dest.path}'),
            backgroundColor: const Color(0xFF0B8A3E),
            duration: const Duration(seconds: 4),
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e — use Share'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Future<void> _deleteBackup(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(
          'Delete backup?',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Delete ${path.split('/').last.split('\\').last}?',
          style: const TextStyle(fontSize: 12),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final svc = BackupService(context.read<AppDatabase>());
      await svc.deleteBackup(path);
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deleted'),
            backgroundColor: Color(0xFF0B8A3E),
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  String _fmt(int? ms) {
    if (ms == null) return 'Never';
    return DateFormat('yyyy-MM-dd HH:mm:ss')
        .format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  String _fmtDt(DateTime? dt) {
    if (dt == null) return '—';
    return DateFormat('yyyy-MM-dd HH:mm').format(dt);
  }

  /// Paths have no spaces, so a long one would overflow a narrow column.
  /// Zero-width spaces after separators give the paragraph soft wrap points.
  String _wrappablePath(String path) =>
      path.replaceAll('\\', '\\\u200B').replaceAll('/', '/\u200B');

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF0B8A3E);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        backgroundColor: green,
        foregroundColor: Colors.white,
        title: const Text(
          'Backup',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: green))
          : SingleChildScrollView(
              padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: Responsive.contentMaxWidth(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Manual backup card
                      Card(
                        color: green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.backup,
                                color: Colors.white,
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Manual backup',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Tap to back up anytime — the entire database will be saved',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: green,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _backingUp || _restoring
                                      ? null
                                      : _doBackup,
                                  icon: _backingUp
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: green,
                                          ),
                                        )
                                      : const Icon(Icons.cloud_upload),
                                  label: Text(
                                    _backingUp ? 'Backing up...' : 'Backup Now',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.95,
                                    ),
                                    foregroundColor: green,
                                    side: const BorderSide(color: Colors.white),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _backingUp || _restoring
                                      ? null
                                      : _saveAnywhere,
                                  icon: const Icon(Icons.save_alt, size: 18),
                                  label: const Text(
                                    'Save to a custom location — choose any file/folder',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Saves an internal backup + opens a file picker to save a second copy anywhere you like (persists after app uninstall/device change)',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 9,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (Platform.isAndroid && !_hasStorageAccess) ...[
                        const SizedBox(height: 14),
                        Card(
                          color: const Color(0xFFFFF4E5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Colors.orange),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.folder_off,
                                      color: Colors.deepOrange,
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'File permission is not enabled',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.deepOrange,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Without this permission you cannot save to Download or your chosen folder. Tap the button, then enable "Allow access to all files".',
                                  style: TextStyle(fontSize: 11),
                                ),
                                const SizedBox(height: 10),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepOrange,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: _requestStorageAccess,
                                  icon: const Icon(Icons.lock_open, size: 16),
                                  label: const Text(
                                    'Grant file permission',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      // Custom default folder — persists after uninstall
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: Colors.teal.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.folder_special,
                                      color: Colors.teal,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Default backup folder — persists after uninstall',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          'Choose any folder (Downloads / Documents / USB)',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                child: SelectableText(
                                  _customDir == null
                                      ? (_visibleDir == null
                                            ? 'Not selected — the visible default folder will be used if available'
                                            : 'Not selected — default: $_visibleDir')
                                      : _wrappablePath(_customDir!),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: _customDir == null
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                    color: _customDir == null
                                        ? Colors.black54
                                        : Colors.teal,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.teal,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                      onPressed: _pickCustomDir,
                                      icon: const Icon(
                                        Icons.folder_open,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'Choose folder',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.clear, size: 16),
                                    label: const Text(
                                      'Clear',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    onPressed: _customDir == null
                                        ? null
                                        : _clearCustomDir,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              if (_customDir != null &&
                                  !_customDirWritable) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.red.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: const Text(
                                    'This folder is saved but the app cannot write to it. Enable all-files access permission, then choose the folder again.',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '• Every manual/automatic backup will also be copied here automatically — the external folder is not deleted when the app is uninstalled or the device changes, and can be copied to the new device and imported.',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Import card — professional
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: Colors.blue.withOpacity(0.15),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.restore,
                                      color: Colors.blue,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Import a backup',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          'Restore deleted data',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_restoring)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.blue,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.blue,
                                    side: const BorderSide(color: Colors.blue),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: _restoring
                                      ? null
                                      : _pickAndRestore,
                                  icon: const Icon(Icons.file_open, size: 18),
                                  label: const Text(
                                    'Import from external file',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '• Supports importing any valid .sqlite file — it is verified and checked automatically. • If current data exists, a safety backup is created before replacement. • After import you must restart the app.',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Auto config
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: green.withOpacity(0.12)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.schedule,
                                      color: green,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Automatic backup',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Switch(
                                    value: _enabled,
                                    activeColor: green,
                                    onChanged: _restoring
                                        ? null
                                        : _toggleEnabled,
                                  ),
                                ],
                              ),
                              const Divider(height: 16),
                              const Text(
                                'Interval — how often to back up',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                value: _interval,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  isDense: true,
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                ),
                                items: BackupService.intervals.entries
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e.key,
                                        child: Text(
                                          e.value,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (_enabled && !_restoring)
                                    ? _changeInterval
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.amber.withOpacity(0.2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.info_outline,
                                      size: 14,
                                      color: Colors.deepOrange,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _interval == 'never' || !_enabled
                                            ? 'Automatic backup is off — use the button above for a manual backup'
                                            : 'Default: Daily — backups run automatically when the app opens and periodically',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Status
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Status',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _row(
                                'Last backup:',
                                _fmt(_lastAt),
                                Icons.history,
                                Colors.blue,
                              ),
                              const SizedBox(height: 6),
                              _row(
                                'Next backup:',
                                _enabled && _interval != 'never'
                                    ? _fmtDt(_nextAt)
                                    : 'Off',
                                Icons.timer,
                                Colors.orange,
                              ),
                              const SizedBox(height: 6),
                              _row(
                                'Backup folder:',
                                _dirPath ?? '—',
                                Icons.folder,
                                Colors.green,
                                small: true,
                              ),
                              if (_visibleDir != null &&
                                  _visibleDir != _dirPath) ...[
                                const SizedBox(height: 6),
                                _row(
                                  'Visible folder:',
                                  _visibleDir!,
                                  Icons.download,
                                  Colors.teal,
                                  small: true,
                                ),
                              ],
                              if (_customDir != null) ...[
                                const SizedBox(height: 6),
                                _row(
                                  'Custom folder:',
                                  _customDir!,
                                  Icons.folder_special,
                                  Colors.teal,
                                  small: true,
                                ),
                              ],
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(
                                        Icons.folder_open,
                                        size: 14,
                                      ),
                                      label: const Text(
                                        'Open folder',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                      onPressed: _dirPath == null
                                          ? null
                                          : () => _openFolder(
                                              _visibleDir ??
                                                  _customDir ??
                                                  _dirPath!,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.copy, size: 14),
                                      label: const Text(
                                        'Copy path',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                      onPressed: _dirPath == null
                                          ? null
                                          : () => _copyPath(
                                              _visibleDir ??
                                                  _customDir ??
                                                  _dirPath!,
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_lastPath != null) ...[
                                const SizedBox(height: 6),
                                _row(
                                  'Last file:',
                                  _lastPath!.split('/').last.split('\\').last,
                                  Icons.insert_drive_file,
                                  Colors.grey,
                                  small: true,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.copy, size: 12),
                                        label: const Text(
                                          'Copy file path',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        onPressed: () => _copyPath(_lastPath!),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(
                                          Icons.drive_folder_upload,
                                          size: 12,
                                        ),
                                        label: const Text(
                                          'Export to Downloads',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        onPressed: () =>
                                            _exportToVisible(_lastPath!),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  Platform.isWindows
                                      ? 'On Windows, backups are saved in the Downloads\\YeLotteryBackups folder (or Documents if Downloads is unavailable) and can be opened directly from the button above.'
                                      : 'On Android, a copy is saved to Download/YeLotteryBackups if storage is allowed, otherwise in the app folder. Choose a custom folder or use Share to keep a backup after uninstalling the app.',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // List backups with pro actions
                      Row(
                        children: [
                          const Icon(Icons.list_alt, size: 16, color: green),
                          const SizedBox(width: 6),
                          Text(
                            'Saved backups (${_backups.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: green,
                            ),
                          ),
                          const Spacer(),
                          if (_backups.isNotEmpty)
                            Text(
                              'Keep last 10',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_backups.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.cloud_off,
                                    size: 32,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No backups yet — tap "Backup Now"',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        ..._backups.take(20).map((f) {
                          final file = File(f.path);
                          final stat = file.statSync();
                          final name = f.path.split('/').last.split('\\').last;
                          final sizeKB = (stat.size / 1024).toStringAsFixed(1);
                          final isSafety = name.contains('before_restore');
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSafety
                                    ? Colors.orange.withOpacity(0.4)
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: Column(
                                children: [
                                  ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      backgroundColor: isSafety
                                          ? Colors.orange.withOpacity(0.15)
                                          : green.withOpacity(0.1),
                                      child: Icon(
                                        isSafety
                                            ? Icons.shield
                                            : Icons.backup_outlined,
                                        color: isSafety ? Colors.orange : green,
                                        size: 16,
                                      ),
                                    ),
                                    title: Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${DateFormat('yyyy-MM-dd HH:mm').format(stat.modified)} • ${sizeKB} KB${isSafety ? ' • Safety backup' : ''}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      0,
                                      8,
                                      6,
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.blue,
                                                  foregroundColor: Colors.white,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 6,
                                                      ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                ),
                                                onPressed: _restoring
                                                    ? null
                                                    : () => _confirmAndRestore(
                                                        f.path,
                                                      ),
                                                icon: const Icon(
                                                  Icons.restore,
                                                  size: 14,
                                                ),
                                                label: const Text(
                                                  'Import',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 6,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                              onPressed: () =>
                                                  _shareBackup(f.path),
                                              icon: const Icon(
                                                Icons.share,
                                                size: 14,
                                              ),
                                              label: const Text(
                                                'Share',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            IconButton(
                                              style: IconButton.styleFrom(
                                                backgroundColor: Colors.red
                                                    .withOpacity(0.08),
                                              ),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                size: 16,
                                                color: Colors.red,
                                              ),
                                              onPressed: () =>
                                                  _deleteBackup(f.path),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.info_outline,
                                                size: 16,
                                                color: Colors.grey,
                                              ),
                                              onPressed: () => showDialog(
                                                context: context,
                                                builder: (c) => AlertDialog(
                                                  title: const Text(
                                                    'Backup path',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  content: SelectableText(
                                                    _wrappablePath(f.path),
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(c),
                                                      child: const Text(
                                                        'Close',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                icon: const Icon(
                                                  Icons.copy,
                                                  size: 12,
                                                ),
                                                label: const Text(
                                                  'Copy path',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                  ),
                                                ),
                                                onPressed: () =>
                                                    _copyPath(f.path),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                icon: const Icon(
                                                  Icons.drive_folder_upload,
                                                  size: 12,
                                                ),
                                                label: const Text(
                                                  'Visible export',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                  ),
                                                ),
                                                onPressed: () =>
                                                    _exportToVisible(f.path),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 16),
                      Card(
                        color: const Color(0xFFE6F4EA),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.verified_user,
                                color: green,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Backup saves the entire database (tickets, accounts, prizes) — stored in the backups folder and can be copied manually outside the device. Import is smart: it verifies the file, creates a safety backup, and asks for double confirmation if the backup matches the current one.',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _row(
    String label,
    String value,
    IconData icon,
    Color color, {
    bool small = false,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      SizedBox(
        width: 80,
        child: Text(
          label,
          style: TextStyle(fontSize: small ? 10 : 11, color: Colors.black54),
        ),
      ),
      Expanded(
        child: SelectableText(
          _wrappablePath(value),
          style: TextStyle(
            fontSize: small ? 10 : 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ],
  );
}
