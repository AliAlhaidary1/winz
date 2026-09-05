import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/database.dart';
import '../../services/backup_service.dart';
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
  List<FileSystemEntity> _backups = [];
  bool _backingUp = false;
  bool _restoring = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(()=> _loading=true);
    final db = context.read<AppDatabase>();
    final svc = BackupService(db);
    final cfg = await svc.getBackupConfig();
    final dir = await svc.getBackupDirPath();
    final list = await svc.listBackups();
    if(!mounted) return;
    setState((){
      _enabled = cfg['enabled'] as bool;
      _interval = cfg['interval'] as String;
      _lastAt = cfg['lastAt'] as int?;
      _lastPath = cfg['lastPath'] as String?;
      _nextAt = cfg['nextAt'] as DateTime?;
      _dirPath = dir;
      _backups = list;
      _loading=false;
    });
  }

  Future<void> _toggleEnabled(bool v) async {
    final svc = BackupService(context.read<AppDatabase>());
    await svc.setEnabled(v);
    setState(()=> _enabled=v);
    await _load();
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(v? 'تم تفعيل النسخ التلقائي' : 'تم إيقاف النسخ التلقائي'), backgroundColor: const Color(0xFF0B8A3E)));
  }

  Future<void> _changeInterval(String? v) async {
    if(v==null) return;
    final svc = BackupService(context.read<AppDatabase>());
    await svc.setInterval(v);
    await _load();
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تغيير الفترة إلى: ${BackupService.intervals[v]}'), backgroundColor: const Color(0xFF0B8A3E)));
  }

  Future<void> _doBackup() async {
    setState(()=> _backingUp=true);
    try{
      final svc = BackupService(context.read<AppDatabase>());
      final path = await svc.performBackup(reason: 'manual');
      await _load();
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم النسخ بنجاح ✅\n$path'), backgroundColor: const Color(0xFF0B8A3E), duration: const Duration(seconds: 4)));
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل النسخ: $e'), backgroundColor: Colors.red));
    }finally{
      if(mounted) setState(()=> _backingUp=false);
    }
  }

  // ============ RESTORE ============
  Future<void> _pickAndRestore() async {
    try{
      final res = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
      if(res==null || res.files.single.path==null) return;
      final path = res.files.single.path!;
      await _confirmAndRestore(path);
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل اختيار الملف: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _confirmAndRestore(String backupPath) async {
    final svc = BackupService(context.read<AppDatabase>());
    Map<String,dynamic>? info;
    try{
      // show loading
      showDialog(context: context, barrierDismissible: false, builder: (c)=> const Center(child: CircularProgressIndicator(color: Color(0xFF0B8A3E))));
      info = await svc.prepareRestore(backupPath);
      if(mounted) Navigator.pop(context);
    }catch(e){
      if(mounted) Navigator.pop(context);
      if(mounted) await showDialog(context: context, builder: (c)=> AlertDialog(
        title: const Row(children: [Icon(Icons.error, color: Colors.red), SizedBox(width:6), Text('ملف غير صالح', style: TextStyle(fontSize:13, fontWeight: FontWeight.bold))]),
        content: Text(e.toString(), style: const TextStyle(fontSize:12)),
        actions: [TextButton(onPressed: ()=> Navigator.pop(c), child: const Text('حسناً'))],
      ));
      return;
    }

    final cur = info['current'] as Map<String,dynamic>;
    final bak = info['backup'] as Map<String,dynamic>;
    final isSame = info['isSameAsLastBackup'] as bool;
    final isIdentical = info['isIdenticalContent'] as bool;
    final hasData = info['hasCurrentData'] as bool;

    // Professional confirmation dialog — fix: vars outside StatefulBuilder so they persist
    bool checked=false;
    bool understoodDumb=false;
    final confirmed = await showDialog<bool>(context: context, builder: (c)=> StatefulBuilder(builder: (ctx,setS){
      return AlertDialog(
        title: Row(children: [Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size:18)), const SizedBox(width:8), const Expanded(child: Text('تأكيد الاستيراد — سيتم استبدال البيانات', style: TextStyle(fontSize:13, fontWeight: FontWeight.bold, color: Colors.red)))]),
        content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Stats comparison
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)), child: Column(children: [
            Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('البيانات الحالية', style: TextStyle(fontSize:11, fontWeight: FontWeight.bold, color: Colors.blue)), const SizedBox(height:4), Text('تذاكر: ${cur['tickets']}  •  أسطر: ${cur['lines']}  •  حسابات: ${cur['accounts']}', style: const TextStyle(fontSize:11)), Text('حجم: ${(cur['size'] as int)/1024>0? ((cur['size'] as int)/1024).toStringAsFixed(1):'0'} KB', style: TextStyle(fontSize:10, color: Colors.grey.shade600))])), Container(width:1, height:40, color: Colors.grey.shade300), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('النسخة المختارة', style: TextStyle(fontSize:11, fontWeight: FontWeight.bold, color: Color(0xFF0B8A3E))), const SizedBox(height:4), Text('تذاكر: ${bak['tickets']}  •  أسطر: ${bak['lines']}  •  حسابات: ${bak['accounts']}', style: const TextStyle(fontSize:11)), Text('حجم: ${(bak['size'] as int)/1024>0? ((bak['size'] as int)/1024).toStringAsFixed(1):'0'} KB', style: TextStyle(fontSize:10, color: Colors.grey.shade600))]))]),
          ])),
          const SizedBox(height:10),
          if(hasData) Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.withOpacity(0.3))), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.shield_outlined, size:16, color: Colors.orange), SizedBox(width:6), Expanded(child: Text('يوجد بيانات حالية — سيتم إنشاء نسخة أمان تلقائية (before_restore) قبل الاستبدال حتى لا تفقد أي شيء.', style: TextStyle(fontSize:11, color: Colors.black87)))])),
          if(isSame || isIdentical) Container(margin: const EdgeInsets.only(top:8), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.amber.withOpacity(0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.lightbulb, size:16, color: Colors.deepOrange), const SizedBox(width:6), Expanded(child: Text(isSame? 'تنبيه ذكي: هذه هي نفس النسخة التي أنشأتها للتو (آخر نسخ) — استيرادها لن يغير شيئاً وقد يكون بلا فائدة. هل أنت متأكد أنك تريد المتابعة؟' : 'تنبيه ذكي: محتوى النسخة مطابق تقريباً للبيانات الحالية — الاستيراد قد لا يكون ضرورياً.', style: const TextStyle(fontSize:11, fontWeight: FontWeight.bold, color: Colors.deepOrange)))])),
          const SizedBox(height:10),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.withOpacity(0.06), borderRadius: BorderRadius.circular(8)), child: const Text('⚠️ بعد الاستيراد سيتم إغلاق قاعدة البيانات ويجب إعادة تشغيل التطبيق. البيانات الحالية سيتم استبدالها بالكامل.', style: TextStyle(fontSize:11, color: Colors.red, fontWeight: FontWeight.bold))),
          const SizedBox(height:8),
          SelectableText(backupPath, style: TextStyle(fontSize:9, color: Colors.grey.shade600)),
          const SizedBox(height:8),
          CheckboxListTile(value: checked, dense: true, contentPadding: EdgeInsets.zero, title: const Text('أفهم أن البيانات الحالية سيتم استبدالها', style: TextStyle(fontSize:11, fontWeight: FontWeight.bold)), controlAffinity: ListTileControlAffinity.leading, onChanged: (v)=> setS(()=> checked=v??false)),
          if(isSame || isIdentical) CheckboxListTile(value: understoodDumb, dense: true, contentPadding: EdgeInsets.zero, title: const Text('أفهم أن هذه نفس النسخة وقد لا يكون الاستيراد ضرورياً', style: TextStyle(fontSize:11)), controlAffinity: ListTileControlAffinity.leading, onChanged: (v)=> setS(()=> understoodDumb=v??false)),
          // hidden confirm button logic uses checked
          Builder(builder: (_){
            // store in dialog state via setS closure — we need to pass back via Navigator
            // Use WillPop to inject logic — simpler: use outer variable
            return const SizedBox.shrink();
          }),
        ])),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(c,false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: (){
              final needSecond = isSame || isIdentical;
              if(!checked || (needSecond && !understoodDumb)){
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('يجب تأكيد الفهم قبل المتابعة'), backgroundColor: Colors.orange));
                return;
              }
              Navigator.pop(c,true);
            },
            child: const Text('استيراد الآن'),
          ),
        ],
      );
    }));
    if(confirmed!=true) return;
    // Execute restore
    setState(()=> _restoring=true);
    try{
      showDialog(context: context, barrierDismissible: false, builder: (c)=> AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(color: Color(0xFF0B8A3E)), const SizedBox(height:12), const Text('جاري الاستيراد...', style: TextStyle(fontSize:12, fontWeight: FontWeight.bold)), const SizedBox(height:4), Text(backupPath.split('/').last.split('\\').last, style: TextStyle(fontSize:10, color: Colors.grey.shade600), textAlign: TextAlign.center)]),
      ));
      final safety = await svc.executeRestore(backupPath, createSafety: hasData);
      if(mounted) Navigator.pop(context); // close loading
      if(!mounted) return;
      await showDialog(context: context, barrierDismissible: false, builder: (c)=> AlertDialog(
        title: const Row(children: [Icon(Icons.check_circle, color: Color(0xFF0B8A3E)), SizedBox(width:6), Text('تم الاستيراد بنجاح ✅', style: TextStyle(fontSize:13, fontWeight: FontWeight.bold, color: Color(0xFF0B8A3E)))]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('تم استبدال قاعدة البيانات بالنسخة المختارة.', style: TextStyle(fontSize:12)),
          const SizedBox(height:8),
          if(safety!=null) Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.green.withOpacity(0.08), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.shield, size:14, color: Color(0xFF0B8A3E)), const SizedBox(width:6), Expanded(child: Text('نسخة الأمان محفوظة:\n${safety.split('/').last.split('\\').last}', style: const TextStyle(fontSize:10)))])),
          const SizedBox(height:8),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(8)), child: const Text('يجب إعادة تشغيل التطبيق الآن لتطبيق التغييرات.', style: TextStyle(fontSize:11, fontWeight: FontWeight.bold, color: Colors.red))),
        ]),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(c), child: const Text('إغلاق (أعد التشغيل يدوياً)')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0B8A3E)), onPressed: (){
            // Try to exit app — user must restart
            SystemNavigator.pop();
            Future.delayed(const Duration(milliseconds: 300), ()=> exit(0));
          }, child: const Text('إنهاء التطبيق الآن')),
        ],
      ));
    }catch(e){
      if(mounted) Navigator.pop(context);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الاستيراد: $e'), backgroundColor: Colors.red, duration: const Duration(seconds:5)));
    }finally{
      if(mounted) setState(()=> _restoring=false);
    }
  }

  Future<void> _shareBackup(String path) async {
    try{
      await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: 'نسخة احتياطية YeLottery — ${path.split('/').last.split('\\').last}'));
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل المشاركة: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ المسار'), backgroundColor: Color(0xFF0B8A3E)));
  }

  Future<void> _openFolder(String dir) async {
    try{
      final d = Directory(dir);
      if(!await d.exists()){
        await d.create(recursive: true);
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم إنشاء المجلد: $dir'), backgroundColor: Colors.orange));
      }
      if(Platform.isWindows){
        // استخدم explorer مع مسار مقتبس
        final res = await Process.run('explorer', [dir]);
        if(res.exitCode!=0){
          throw Exception('explorer exit ${res.exitCode}: ${res.stderr}');
        }
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم فتح المجلد: $dir'), backgroundColor: const Color(0xFF0B8A3E)));
        return;
      } else if(Platform.isAndroid){
        await _copyPath(dir);
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('المسار: $dir — تم النسخ، استخدم مدير ملفات'), backgroundColor: Colors.blue));
        return;
      } else {
        await _copyPath(dir);
        return;
      }
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر فتح المجلد: $e — تم نسخ المسار'), backgroundColor: Colors.orange));
      await _copyPath(dir);
    }
  }

  Future<void> _exportToVisible(String path) async {
    try{
      final svc = BackupService(context.read<AppDatabase>());
      final destDir = await svc.getVisibleExportDir();
      if(destDir==null) throw Exception('لا يوجد مجلد تصدير');
      final name = path.split('/').last.split('\\').last;
      final dest = File('${destDir.path}/$name');
      await File(path).copy(dest.path);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم التصدير إلى: ${dest.path}'), backgroundColor: const Color(0xFF0B8A3E), duration: const Duration(seconds: 4)));
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التصدير: $e — استخدم مشاركة'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteBackup(String path) async {
    final ok = await showDialog<bool>(context: context, builder: (c)=> AlertDialog(
      title: const Text('حذف النسخة؟', style: TextStyle(fontSize:13, fontWeight: FontWeight.bold)),
      content: Text('هل تريد حذف ${path.split('/').last.split('\\').last} ؟', style: const TextStyle(fontSize:12)),
      actions: [TextButton(onPressed: ()=> Navigator.pop(c,false), child: const Text('إلغاء')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: ()=> Navigator.pop(c,true), child: const Text('حذف'))],
    ));
    if(ok!=true) return;
    try{
      final svc = BackupService(context.read<AppDatabase>());
      await svc.deleteBackup(path);
      await _load();
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحذف'), backgroundColor: Color(0xFF0B8A3E)));
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: Colors.red));
    }
  }

  String _fmt(int? ms){
    if(ms==null) return 'لم يتم بعد';
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(ms));
  }
  String _fmtDt(DateTime? dt){
    if(dt==null) return '—';
    return DateFormat('yyyy-MM-dd HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context){
    const green = Color(0xFF0B8A3E);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(backgroundColor: green, foregroundColor: Colors.white, title: const Text('النسخ الاحتياطي — Backup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _load)]),
      body: _loading ? const Center(child: CircularProgressIndicator(color: green)) : SingleChildScrollView(
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        child: Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: Responsive.contentMaxWidth(context)), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Manual backup card
          Card(
            color: green,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              const Icon(Icons.backup, color: Colors.white, size: 32),
              const SizedBox(height: 8),
              const Text('نسخ احتياطي يدوي', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('اضغط للنسخ في أي وقت — سيتم حفظ قاعدة البيانات كاملة', style: TextStyle(color: Colors.white70, fontSize: 11), textAlign: TextAlign.center),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: green, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: _backingUp || _restoring ? null : _doBackup,
                icon: _backingUp ? const SizedBox(width:16,height:16, child: CircularProgressIndicator(strokeWidth: 2, color: green)) : const Icon(Icons.cloud_upload),
                label: Text(_backingUp? 'جاري النسخ...' : 'نسخ الآن — Backup Now', style: const TextStyle(fontWeight: FontWeight.bold)),
              )),
            ])),
          ),
          const SizedBox(height: 14),
          // Import card — professional
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.blue.withOpacity(0.15))),
            child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.restore, color: Colors.blue, size: 18)),
                const SizedBox(width: 8),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('استيراد نسخة احتياطية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), Text('استعادة البيانات المحذوفة', style: TextStyle(fontSize:10, color: Colors.black54))])),
                if(_restoring) const SizedBox(width:16,height:16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue)),
              ]),
              const SizedBox(height:10),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.blue, side: const BorderSide(color: Colors.blue), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: _restoring ? null : _pickAndRestore,
                icon: const Icon(Icons.file_open, size:18),
                label: const Text('استيراد من ملف خارجي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              )),
              const SizedBox(height:6),
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.06), borderRadius: BorderRadius.circular(8)), child: const Text('• يدعم استيراد أي ملف ‎.sqlite صالح — سيتم التحقق تلقائياً وفحص السلامة. • إذا كانت هناك بيانات حالية سيتم إنشاء نسخة أمان قبل الاستبدال. • بعد الاستيراد يجب إعادة تشغيل التطبيق.', style: TextStyle(fontSize:10, color: Colors.black87))),
            ])),
          ),
          const SizedBox(height: 14),
          // Auto config
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: green.withOpacity(0.12))),
            child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.schedule, color: green, size: 18)),
                const SizedBox(width: 8),
                const Expanded(child: Text('النسخ التلقائي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                Switch(value: _enabled, activeColor: green, onChanged: _restoring? null : _toggleEnabled),
              ]),
              const Divider(height: 16),
              const Text('الفترة — كل كم يتم النسخ', style: TextStyle(fontSize: 11, color: Colors.black54)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _interval,
                decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, filled: true, fillColor: Colors.grey.shade50),
                items: BackupService.intervals.entries.map((e)=> DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (_enabled && !_restoring) ? _changeInterval : null,
              ),
              const SizedBox(height: 6),
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.amber.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.withOpacity(0.2))), child: Row(children: [const Icon(Icons.info_outline, size: 14, color: Colors.deepOrange), const SizedBox(width: 6), Expanded(child: Text(_interval=='never' || !_enabled ? 'النسخ التلقائي متوقف — استخدم الزر أعلاه للنسخ اليدوي' : 'الافتراضي: يومياً — سيتم النسخ تلقائياً عند فتح التطبيق وبشكل دوري', style: const TextStyle(fontSize: 11, color: Colors.black87)))])),
            ])),
          ),
          const SizedBox(height: 14),
          // Status
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('الحالة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 8),
              _row('آخر نسخ:', _fmt(_lastAt), Icons.history, Colors.blue),
              const SizedBox(height: 6),
              _row('النسخ القادم:', _enabled && _interval!='never' ? _fmtDt(_nextAt) : 'متوقف', Icons.timer, Colors.orange),
              const SizedBox(height: 6),
              _row('مجلد النسخ:', _dirPath?? '—', Icons.folder, Colors.green, small: true),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.folder_open, size:14), label: const Text('فتح المجلد', style: TextStyle(fontSize:11)), onPressed: _dirPath==null? null: ()=> _openFolder(_dirPath!))),
                const SizedBox(width:6),
                Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.copy, size:14), label: const Text('نسخ المسار', style: TextStyle(fontSize:11)), onPressed: _dirPath==null? null: ()=> _copyPath(_dirPath!))),
              ]),
              if(_lastPath!=null) ...[
                const SizedBox(height: 6),
                _row('آخر ملف:', _lastPath!.split('/').last.split('\\').last, Icons.insert_drive_file, Colors.grey, small: true),
                const SizedBox(height:4),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.copy, size:12), label: const Text('نسخ مسار الملف', style: TextStyle(fontSize:10)), onPressed: ()=> _copyPath(_lastPath!))),
                  const SizedBox(width:6),
                  Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.drive_folder_upload, size:12), label: const Text('تصدير للـ Downloads', style: TextStyle(fontSize:10)), onPressed: ()=> _exportToVisible(_lastPath!))),
                ]),
              ],
              const SizedBox(height:6),
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.06), borderRadius: BorderRadius.circular(8)), child: const Text('ملاحظة: على Android المجلد داخلي ولا يظهر في مدير الملفات — استخدم "تصدير للـ Downloads" أو "مشاركة" لحفظ نسخة مرئية في Download/YeLotteryBackups', style: TextStyle(fontSize:10, color: Colors.black54))),
            ])),
          ),
          const SizedBox(height: 14),
          // List backups with pro actions
          Row(children: [
            const Icon(Icons.list_alt, size: 16, color: green),
            const SizedBox(width: 6),
            Text('النسخ المحفوظة (${_backups.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: green)),
            const Spacer(),
            if(_backups.isNotEmpty) Text('الاحتفاظ بآخر 10', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ]),
          const SizedBox(height: 8),
          if(_backups.isEmpty)
            Card(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Column(children: [Icon(Icons.cloud_off, size: 32, color: Colors.grey.shade400), const SizedBox(height: 8), Text('لا يوجد نسخ بعد — اضغط "نسخ الآن"', style: TextStyle(color: Colors.grey.shade600, fontSize: 12))]))))
          else
            ..._backups.take(20).map((f){
              final file = File(f.path);
              final stat = file.statSync();
              final name = f.path.split('/').last.split('\\').last;
              final sizeKB = (stat.size/1024).toStringAsFixed(1);
              final isSafety = name.contains('before_restore');
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isSafety? Colors.orange.withOpacity(0.4) : Colors.grey.shade200)),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: Column(children: [
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(backgroundColor: isSafety? Colors.orange.withOpacity(0.15): green.withOpacity(0.1), child: Icon(isSafety? Icons.shield: Icons.backup_outlined, color: isSafety? Colors.orange: green, size: 16)),
                    title: Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${DateFormat('yyyy-MM-dd HH:mm').format(stat.modified)} • ${sizeKB} KB${isSafety?' • نسخة أمان':''}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                  ),
                  Padding(padding: const EdgeInsets.fromLTRB(8,0,8,6), child: Column(children: [
                    Row(children: [
                      Expanded(child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical:6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: _restoring? null : ()=> _confirmAndRestore(f.path), icon: const Icon(Icons.restore, size:14), label: const Text('استيراد', style: TextStyle(fontSize:11, fontWeight: FontWeight.bold)))),
                      const SizedBox(width:6),
                      OutlinedButton.icon(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal:8, vertical:6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: ()=> _shareBackup(f.path), icon: const Icon(Icons.share, size:14), label: const Text('مشاركة', style: TextStyle(fontSize:11))),
                      const SizedBox(width:6),
                      IconButton(style: IconButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.08)), icon: const Icon(Icons.delete_outline, size:16, color: Colors.red), onPressed: ()=> _deleteBackup(f.path)),
                      IconButton(icon: const Icon(Icons.info_outline, size:16, color: Colors.grey), onPressed: ()=> showDialog(context: context, builder: (c)=> AlertDialog(title: const Text('مسار النسخة', style: TextStyle(fontSize:13)), content: SelectableText(f.path, style: const TextStyle(fontSize:11)), actions: [TextButton(onPressed: ()=> Navigator.pop(c), child: const Text('إغلاق'))]))),
                    ]),
                    const SizedBox(height:4),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.copy, size:12), label: const Text('نسخ المسار', style: TextStyle(fontSize:10)), onPressed: ()=> _copyPath(f.path))),
                      const SizedBox(width:6),
                      Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.drive_folder_upload, size:12), label: const Text('تصدير مرئي', style: TextStyle(fontSize:10)), onPressed: ()=> _exportToVisible(f.path))),
                    ]),
                  ])),
                ])),
              );
            }),
          const SizedBox(height: 16),
          Card(color: const Color(0xFFE6F4EA), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Icon(Icons.verified_user, color: green, size: 16), const SizedBox(width: 8), const Expanded(child: Text('النسخ يحفظ قاعدة البيانات كاملة (تذاكر، حسابات، جوائز) — يُحفظ في مجلد backups ويمكن نسخه يدوياً إلى خارج الجهاز. الاستيراد ذكي: يتحقق من الملف، ينشئ نسخة أمان، ويطلب تأكيداً مزدوجاً إذا كانت النسخة مطابقة للحالية.', style: TextStyle(fontSize: 11)))]))),
        ])))),
    );
  }

  Widget _row(String label, String value, IconData icon, Color color, {bool small=false})=> Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 14, color: color), const SizedBox(width: 6), SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: small?10:11, color: Colors.black54))), Expanded(child: SelectableText(value, style: TextStyle(fontSize: small?10:11, fontWeight: FontWeight.bold)))]);
}
