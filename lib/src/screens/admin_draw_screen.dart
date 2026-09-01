import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/database.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';

class AdminDrawScreen extends StatefulWidget {
  const AdminDrawScreen({super.key, required this.drawId});
  final String drawId;

  @override
  State<AdminDrawScreen> createState() => _AdminDrawScreenState();
}

class _AdminDrawScreenState extends State<AdminDrawScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String _gameId = 'g_numbers';
  String? _selectedDrawId;
  List<Map<String, dynamic>> _draws = []; // all draws for selected game
  List<Map<String, dynamic>> _periodsCache = [];
  List<Map<String, dynamic>> get _pendingDraws {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // فقط الفترة الحالية التي حان وقت سحبها (نافذة الإدخال: من salesClose حتى drawTime+2h)
    // لا يعرض أي خيارات إضافية — خيار واحد فقط للفترة التي وقت السحب لها الآن
    return _draws.where((d) {
      final win = d['winningNumbers'] as String?;
      if (win != null && win.trim().isNotEmpty) return false;
      final dt = d['drawTime'] as int;
      final name = d['name'] as String;
      final isMidday = name.contains('Midday')||name.contains('Morning');
      final type = isMidday ? 'MIDDAY' : 'EVENING';
      final drawDt = DateTime.fromMillisecondsSinceEpoch(dt);
      final dateStr = '${drawDt.year}-${drawDt.month.toString().padLeft(2,'0')}-${drawDt.day.toString().padLeft(2,'0')}';
      final pid = '$dateStr-$type';
      final p = _periodsCache.where((e)=> e['id']==pid).firstOrNull;
      if (p == null) return false;
      final salesClose = p['salesCloseTime'] as int;
      final drawTime = p['drawTime'] as int;
      const windowMs = 2*3600*1000; // ساعتان بعد السحب للسماح بالإدخال
      // يسمح فقط إذا الآن داخل [salesClose, drawTime+2h]
      return nowMs >= salesClose && nowMs <= drawTime + windowMs;
    }).toList()..sort((a,b)=> (a['drawTime'] as int).compareTo(b['drawTime'] as int));
  }
  final _winCtrl = TextEditingController();
  bool _processing = false;
  String? _error;
  String? _success;
  Map<String, dynamic>? _lastResult;
  List<Map<String, dynamic>> _winningTickets = [];
  bool _autoPay = false;

  // --- History tab filters ---
  String _historyGame = 'all'; // all / g_numbers / g_winz
  String _historyStatus = 'all'; // all / pending / done
  DateTime? _historyDate; // null = all dates
  String _historySearch = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    if (widget.drawId.isNotEmpty && widget.drawId.startsWith('g_')) {
      _gameId = widget.drawId;
    }
    _loadDraws();
  }

  @override
  void dispose() {
    _winCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDraws() async {
    final db = context.read<AppDatabase>();
    await db.seedDrawPeriods();
    await db.refreshPeriodStatuses();
    _periodsCache = await db.getAllPeriods();
    List<Map<String, dynamic>> draws;
    if (_gameId == 'all') {
      draws = await db.getAllDraws();
    } else {
      draws = await db.getDrawsByGame(_gameId);
    }
    // Ensure sorted by drawTime ascending for pending tab (soonest first)
    draws.sort((a, b) => (a['drawTime'] as int).compareTo(b['drawTime'] as int));
    if (!mounted) return;
    setState(() {
      _draws = draws;
      // Auto-select first pending if current selection is null or now not pending
      final pending = _pendingDraws;
      final currentStillPending = _selectedDrawId != null && pending.any((d) => d['id'] == _selectedDrawId);
      if (_selectedDrawId == null || !currentStillPending) {
        if (pending.isNotEmpty) {
          _selectedDrawId = pending.first['id'] as String;
          _fillWinCtrlFromDraw();
        } else {
          // No pending: keep selection null to force empty state (prompt to go to history)
          _selectedDrawId = null;
          _winCtrl.clear();
        }
      } else {
        _fillWinCtrlFromDraw();
      }
    });
    await _loadWinningPreview();
  }

  void _fillWinCtrlFromDraw() {
    if (_selectedDrawId == null) {
      _winCtrl.clear();
      return;
    }
    final d = _draws.where((e) => e['id'] == _selectedDrawId).firstOrNull;
    if (d != null && d['winningNumbers'] != null && (d['winningNumbers'] as String).trim().isNotEmpty) {
      final s = (d['winningNumbers'] as String).replaceAll(',', '');
      _winCtrl.text = s;
    } else {
      if (_success == null) _winCtrl.clear();
    }
  }

  Future<void> _loadWinningPreview() async {
    if (_selectedDrawId == null) {
      if (mounted) setState(() => _winningTickets = []);
      return;
    }
    final db = context.read<AppDatabase>();
    final tickets = await db.getTickets();
    final draw = _draws.where((e) => e['id'] == _selectedDrawId).firstOrNull;
    final winStr = draw?['winningNumbers'] as String?;
    if (winStr == null || winStr.isEmpty) {
      if (mounted) setState(() => _winningTickets = []);
      return;
    }
    // Show already winning tickets for this draw (including multi-line via ticket_lines)
    final winning = tickets.where((t) => t['drawId'] == _selectedDrawId && (t['status'] == 'winning' || t['status'] == 'paid')).toList();
    // Also include multi-line tickets where draw appears only in lines
    if (winning.isEmpty) {
      final allLines = await db.getAllTicketLines();
      final ids = allLines.where((l) => l['drawId'] == _selectedDrawId).map((l) => l['ticketId'] as String).toSet();
      final extra = tickets.where((t) => ids.contains(t['id']) && (t['status'] == 'winning' || t['status'] == 'paid')).toList();
      winning.addAll(extra);
    }
    if (mounted) setState(() => _winningTickets = winning);
  }

  Future<void> _submit() async {
    setState(() { _error = null; _success = null; _lastResult = null; });
    if (_selectedDrawId == null) {
      setState(() => _error = 'لا يوجد سحب معلق — انتقل إلى سجل السحوبات لعرض الكل');
      return;
    }
    final raw = _winCtrl.text.trim().replaceAll(',', '').replaceAll(' ', '');
    if (raw.isEmpty) {
      setState(() => _error = 'أدخل الرقم الفائز (مثال 123 أو 1234)');
      return;
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(raw)) {
      setState(() => _error = 'الرقم الفائز يجب أن يكون أرقام 0-9 فقط');
      return;
    }
    if (_gameId == 'g_numbers' && raw.length != 3 && raw.length != 4) {
      setState(() => _error = 'Numbers يحتاج 3 أو 4 أرقام (مثال 123 أو 0123)');
      return;
    }
    if (_gameId == 'g_winz' && raw.length != 4) {
      setState(() => _error = 'Win 4 يحتاج 4 أرقام بالضبط');
      return;
    }
    final draw = _draws.where((e) => e['id'] == _selectedDrawId).firstOrNull;
    if (draw != null && draw['winningNumbers'] != null && (draw['winningNumbers'] as String).trim().isNotEmpty) {
      final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: const Text('تأكيد استبدال النتيجة'),
        content: Text('السحب $_selectedDrawId لديه نتيجة سابقة: ${draw['winningNumbers']}. هل تريد الاستبدال بـ $raw وإعادة حساب الفائزين؟'),
        actions: [TextButton(onPressed: () => Navigator.pop(c,false), child: const Text('إلغاء')), ElevatedButton(onPressed: () => Navigator.pop(c,true), child: const Text('استبدال'))],
      ));
      if (confirm != true) return;
    }

    setState(() => _processing = true);
    try {
      final digits = raw.split('');
      final app = context.read<AppState>();
      final res = await app.processDrawResult(drawId: _selectedDrawId!, winningNumbers: digits, autoPay: _autoPay);
      await _loadDraws();
      await _loadWinningPreview();
      if (!mounted) return;
      setState(() {
        _success = 'تم حفظ $raw — الفائزون: ${res['winningCount']} • الخاسرون: ${res['losingCount']} • الجوائز: ${fmtMoney(res['totalPrize'])}';
        _lastResult = res;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_success!)));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _editWinnerForDraw(Map<String, dynamic> draw) async {
    final ctrl = TextEditingController(text: (draw['winningNumbers'] as String?)?.replaceAll(',', '') ?? '');
    final gid = draw['gameId'] as String;
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('تعديل الفائز — ${draw['name']}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ID: ${draw['id']}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
        const SizedBox(height: 8),
        TextField(controller: ctrl, keyboardType: TextInputType.number, maxLength: gid=='g_numbers'?4:4, decoration: InputDecoration(labelText: 'الرقم الفائز', hintText: gid=='g_winz'?'0123':'123', border: const OutlineInputBorder(), counterText: '')),
        const SizedBox(height: 6),
        Text(gid=='g_numbers' ? '3 أو 4 أرقام' : '4 أرقام بالضبط', style: const TextStyle(fontSize: 10, color: Colors.black54)),
        const SizedBox(height: 8),
        StatefulBuilder(builder: (ctx, setS){
          return CheckboxListTile(value: _autoPay, dense: true, contentPadding: EdgeInsets.zero, title: const Text('دفع تلقائي', style: TextStyle(fontSize: 11)), onChanged: (v){ setState(()=> _autoPay=v??false); setS((){}); });
        }),
      ]),
      actions: [TextButton(onPressed: ()=> Navigator.pop(c,false), child: const Text('إلغاء')), ElevatedButton(onPressed: ()=> Navigator.pop(c,true), child: const Text('حفظ'))],
    ));
    if(ok!=true) return;
    final raw = ctrl.text.trim().replaceAll(',', '').replaceAll(' ', '');
    if(raw.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(raw)){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رقم غير صالح'))); return; }
    if(gid=='g_winz' && raw.length!=4){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Win 4 يحتاج 4 أرقام'))); return; }
    if(gid=='g_numbers' && raw.length!=3 && raw.length!=4){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numbers 3 أو 4 أرقام'))); return; }
    setState(()=> _processing=true);
    try{
      final res = await context.read<AppState>().processDrawResult(drawId: draw['id'], winningNumbers: raw.split(''), autoPay: _autoPay);
      await _loadDraws();
      await _loadWinningPreview();
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم التحديث $raw — ${res['winningCount']} فائز')));
    }catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
    finally{ if(mounted) setState(()=> _processing=false); }
  }

  List<Map<String,dynamic>> get _filteredHistory {
    List<Map<String,dynamic>> list = List.from(_draws);
    // Need to fetch all draws for history when _gameId filter is 'all' already loaded. For history game filter, apply separate.
    if(_historyGame != 'all'){
      list = list.where((d)=> d['gameId']==_historyGame).toList();
    }
    if(_historyStatus == 'pending'){
      list = list.where((d){
        final win = d['winningNumbers'] as String?;
        return win==null || win.trim().isEmpty;
      }).toList();
    } else if(_historyStatus == 'done'){
      list = list.where((d){
        final win = d['winningNumbers'] as String?;
        return win!=null && win.trim().isNotEmpty;
      }).toList();
    }
    if(_historyDate != null){
      final y=_historyDate!.year, m=_historyDate!.month, d=_historyDate!.day;
      list = list.where((e){
        final dt = DateTime.fromMillisecondsSinceEpoch(e['drawTime'] as int);
        return dt.year==y && dt.month==m && dt.day==d;
      }).toList();
    }
    if(_historySearch.trim().isNotEmpty){
      final q=_historySearch.trim().toLowerCase();
      list = list.where((e)=> (e['name'] as String).toLowerCase().contains(q) || (e['id'] as String).toLowerCase().contains(q) || ((e['winningNumbers'] as String?)??'').contains(q)).toList();
    }
    list.sort((a,b)=> (b['drawTime'] as int).compareTo(a['drawTime'] as int));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingDraws;
    return Scaffold(
      appBar: AppBar(
        title: const Text('نتيجة السحب — NY Lottery'),
        backgroundColor: const Color(0xFF0B8A3E),
        foregroundColor: Colors.white,
        bottom: TabBar(controller: _tabCtrl, labelColor: Colors.white, unselectedLabelColor: Colors.white70, indicatorColor: Colors.white, tabs: const [
          Tab(icon: Icon(Icons.edit), text: 'إدخال الفائز'),
          Tab(icon: Icon(Icons.history), text: 'سجل السحوبات'),
        ]),
      ),
      body: TabBarView(controller: _tabCtrl, children: [
        // TAB 1: إدخال الفائز — فقط المعلق
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: DropdownButtonFormField<String>(
                    value: _gameId,
                    decoration: const InputDecoration(labelText: 'اللعبة', border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'g_numbers', child: Text('Numbers (Pick 3/4)')),
                      DropdownMenuItem(value: 'g_winz', child: Text('Win 4 (Pick 4)')),
                      DropdownMenuItem(value: 'all', child: Text('الكل')),
                    ],
                    onChanged: (v) async { setState(() { _gameId = v!; _selectedDrawId = null; _winCtrl.clear(); }); await _loadDraws(); },
                  )),
                  const SizedBox(width: 12),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDraws),
                ]),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF0B8A3E).withValues(alpha: 0.2))),
                  child: Row(children: [
                    const Icon(Icons.info_outline, size: 16, color: Color(0xFF0B8A3E)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('يُعرض فقط السحوبات التي لم يُكتب لها فائز بعد (${pending.length} معلق) — للتعديل انتقل إلى تبويب سجل السحوبات', style: const TextStyle(fontSize: 11, color: Color(0xFF0B8A3E)))),
                    TextButton(onPressed: ()=> _tabCtrl.animateTo(1), child: const Text('عرض الكل', style: TextStyle(fontSize: 11))),
                  ]),
                ),
                const SizedBox(height: 12),
                if(pending.isEmpty)
                  Card(color: Colors.orange.shade50, child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                    const Icon(Icons.check_circle, color: Colors.orange, size: 28),
                    const SizedBox(height: 8),
                    const Text('لا يوجد سحوبات معلقة', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Text('كل السحوبات الحالية لها فائز — راجع سجل السحوبات للتعديل أو الاستعراض', style: TextStyle(fontSize: 11, color: Colors.black54), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(icon: const Icon(Icons.history), label: const Text('فتح سجل السحوبات'), onPressed: ()=> _tabCtrl.animateTo(1)),
                  ])))
                else ...[
                  DropdownButtonFormField<String>(
                    value: _selectedDrawId,
                    decoration: const InputDecoration(labelText: 'السحب (معلق فقط)', border: OutlineInputBorder(), isDense: true),
                    isExpanded: true,
                    items: pending.map((d) {
                      final label = '${d['name']} • ${d['status']}';
                      return DropdownMenuItem<String>(value: d['id'] as String, child: Text(label, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis));
                    }).toList(),
                    onChanged: (v) {
                      setState(() { _selectedDrawId = v; _error=null; _success=null; _lastResult=null; });
                      _fillWinCtrlFromDraw();
                      _loadWinningPreview();
                    },
                  ),
                  const SizedBox(height: 12),
                  Builder(builder: (_){
                    final draw = _selectedDrawId == null ? null : _draws.where((e)=> e['id']==_selectedDrawId).firstOrNull;
                    if(draw==null) return const SizedBox();
                    return Card(color: Colors.blue.shade50, child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('السحب: ${draw['name']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('ID: ${draw['id']}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                      Text('الوقت: ${fmtDate(draw['drawTime'])} • الحالة: ${draw['status']}', style: const TextStyle(fontSize: 11)),
                    ])));
                  }),
                  const SizedBox(height: 16),
                  const Text('الرقم الفائز', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(_gameId == 'g_numbers' ? 'أدخل 3 أو 4 أرقام (0-9)' : 'أدخل 4 أرقام (0-9)', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _winCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: InputDecoration(
                      labelText: 'الرقم الفائز',
                      hintText: _gameId == 'g_numbers' ? 'مثال 123' : 'مثال 0123',
                      border: const OutlineInputBorder(),
                      counterText: '',
                      suffixIcon: _winCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _winCtrl.clear())) : null,
                    ),
                    onChanged: (_) => setState(() { _error=null; }),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _autoPay,
                    onChanged: (v) => setState(() => _autoPay = v ?? false),
                    title: const Text('دفع تلقائي للفائزين', style: TextStyle(fontSize: 12)),
                    subtitle: const Text('إذا لم يُحدد: تُعلّم التذاكر كفائزة فقط بدون خصم من الصندوق', style: TextStyle(fontSize: 10, color: Colors.black54)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_error != null) Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [const Icon(Icons.error, color: Colors.red, size: 18), const SizedBox(width: 8), Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)))]))),
                  if (_success != null) Card(color: Colors.green.shade50, child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [const Icon(Icons.check_circle, color: Colors.green, size: 18), const SizedBox(width: 8), Expanded(child: Text(_success!, style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600)))]))),
                  if (_processing) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, height: 46, child: ElevatedButton.icon(
                    icon: _processing ? const SizedBox(width: 16, height:16, child: CircularProgressIndicator(strokeWidth:2, color: Colors.white)) : const Icon(Icons.save),
                    label: Text(_processing ? 'جاري الحفظ...' : 'حفظ النتيجة وتقييم الفائزين'),
                    onPressed: _processing ? null : _submit,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                  )),
                ],
                const SizedBox(height: 16),
                if (_lastResult != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('نتيجة المعالجة + المحاسبة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text('إجمالي التذاكر: ${_lastResult!['totalTickets']}', style: const TextStyle(fontSize: 12)),
                  Text('الفائزون: ${_lastResult!['winningCount']} • الخاسرون: ${_lastResult!['losingCount']}', style: const TextStyle(fontSize: 12)),
                  Text('المبيعات: ${fmtMoney(_lastResult!['totalSales'] ?? 0)}', style: const TextStyle(fontSize: 12)),
                  Text('الجوائز: ${fmtMoney(_lastResult!['totalPrize'])}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green)),
                ]))),
                if (_winningTickets.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('التذاكر الفائزة في هذا السحب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  ..._winningTickets.map((t) => Card(child: ListTile(
                    dense: true,
                    title: Text('${t['id']} • ${t['numbers'].toString().replaceAll(',', ' ')} • ${t['betType']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    subtitle: Text('${t['gameName']} • ${fmtMoney(t['amount'])} → ${fmtMoney(t['prizeAmount'] ?? 0)} • ${t['status']}', style: const TextStyle(fontSize: 11)),
                    trailing: t['status']=='paid' ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.emoji_events, color: Colors.orange),
                    onTap: () => Navigator.pushNamed(context, '/ticket_detail', arguments: t),
                  ))),
                ],
              ]),
            ),
          ),
        ),
        // TAB 2: سجل السحوبات — عرض الكل مع فلترة حسب التاريخ
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(12,12,12,8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('فلترة السجل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const Spacer(),
                    Text('${_filteredHistory.length}/${_draws.length} سحب', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  ]),
                  const SizedBox(height: 8),
                  SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                    ChoiceChip(label: const Text('الكل'), selected: _historyGame=='all', onSelected: (_)=> setState(()=> _historyGame='all')),
                    const SizedBox(width: 6),
                    ChoiceChip(label: const Text('Numbers'), selected: _historyGame=='g_numbers', onSelected: (_)=> setState(()=> _historyGame='g_numbers')),
                    const SizedBox(width: 6),
                    ChoiceChip(label: const Text('Win 4'), selected: _historyGame=='g_winz', onSelected: (_)=> setState(()=> _historyGame='g_winz')),
                    const SizedBox(width: 12),
                    Container(width: 1, height: 24, color: Colors.grey.shade300),
                    const SizedBox(width: 12),
                    ChoiceChip(label: const Text('الكل'), selected: _historyStatus=='all', onSelected: (_)=> setState(()=> _historyStatus='all')),
                    const SizedBox(width: 6),
                    ChoiceChip(label: const Text('معلق'), selected: _historyStatus=='pending', onSelected: (_)=> setState(()=> _historyStatus='pending')),
                    const SizedBox(width: 6),
                    ChoiceChip(label: const Text('مُعلن'), selected: _historyStatus=='done', onSelected: (_)=> setState(()=> _historyStatus='done')),
                  ])),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(
                      decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 16), hintText: 'بحث بالاسم أو ID أو الرقم الفائز', border: OutlineInputBorder(), hintStyle: TextStyle(fontSize: 11)),
                      style: const TextStyle(fontSize: 12),
                      onChanged: (v)=> setState(()=> _historySearch=v),
                    )),
                  ]),
                  const SizedBox(height: 8),
                  SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                    OutlinedButton.icon(icon: const Icon(Icons.calendar_today, size: 14), label: Text(_historyDate==null ? 'كل التواريخ' : '${_historyDate!.year}/${_historyDate!.month.toString().padLeft(2,'0')}/${_historyDate!.day.toString().padLeft(2,'0')}', style: const TextStyle(fontSize: 11)), onPressed: () async {
                      final picked = await showDatePicker(context: context, initialDate: _historyDate ?? DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2030));
                      if(picked!=null) setState(()=> _historyDate=picked);
                    }),
                    if(_historyDate!=null) ...[
                      const SizedBox(width: 6),
                      IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: ()=> setState(()=> _historyDate=null)),
                    ],
                    const SizedBox(width: 6),
                    OutlinedButton.icon(icon: const Icon(Icons.today, size: 14), label: const Text('اليوم', style: TextStyle(fontSize: 11)), onPressed: ()=> setState(()=> _historyDate=DateTime.now())),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(icon: const Icon(Icons.history, size: 14), label: const Text('أمس', style: TextStyle(fontSize: 11)), onPressed: ()=> setState(()=> _historyDate=DateTime.now().subtract(const Duration(days:1)))),
                  ])),
                ]),
              ),
              const Divider(height: 1),
              Expanded(child: _filteredHistory.isEmpty ? const Center(child: Text('لا يوجد سحوبات مطابقة للفلتر', style: TextStyle(color: Colors.black54))) : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _filteredHistory.length,
                separatorBuilder: (_,__)=> const SizedBox(height: 8),
                itemBuilder: (c,i){
                  final d=_filteredHistory[i];
                  final win = d['winningNumbers'] as String?;
                  final hasWinner = win!=null && win.trim().isNotEmpty;
                  final dt = DateTime.fromMillisecondsSinceEpoch(d['drawTime'] as int);
                  final statusColor = hasWinner ? Colors.green : Colors.orange;
                  return Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: statusColor.withValues(alpha:0.2))),
                    child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: statusColor.withValues(alpha:0.1), borderRadius: BorderRadius.circular(20)), child: Text(hasWinner ? 'مُعلن' : 'معلق', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor))),
                        const SizedBox(width: 6),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)), child: Text(d['gameId']=='g_winz'?'Win 4':'Numbers', style: const TextStyle(fontSize: 10))),
                        const Spacer(),
                        Text('${dt.year}/${dt.month.toString().padLeft(2,'0')}/${dt.day.toString().padLeft(2,'0')} • ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                      ]),
                      const SizedBox(height: 6),
                      Text(d['name'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('ID: ${d['id']}', style: const TextStyle(fontSize: 10, color: Colors.black45)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: hasWinner? Colors.green.shade50: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('الرقم الفائز', style: TextStyle(fontSize: 10, color: Colors.black54)),
                          Text(hasWinner ? win.replaceAll(',', ' ') : '— لم يُعلن بعد —', style: TextStyle(fontSize: hasWinner?16:12, fontWeight: hasWinner? FontWeight.w900: FontWeight.w500, letterSpacing: hasWinner?2:0, color: hasWinner? Colors.green.shade700: Colors.black45)),
                        ]))),
                        const SizedBox(width: 8),
                        Column(children: [
                          ElevatedButton.icon(icon: Icon(hasWinner? Icons.edit: Icons.add, size: 14), label: Text(hasWinner? 'تعديل':'إدخال', style: const TextStyle(fontSize: 11)), style: ElevatedButton.styleFrom(backgroundColor: hasWinner? Colors.orange: const Color(0xFF0B8A3E), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)), onPressed: ()=> _editWinnerForDraw(d)),
                          const SizedBox(height: 4),
                          if(hasWinner) Text('Tap لتعديل', style: TextStyle(fontSize: 9, color: Colors.black45)),
                        ]),
                      ]),
                    ])),
                  );
                },
              )),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _profitRow(String label, String mult, String ex) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(6)), child: Text(mult, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepPurple))),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        Text(ex, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ])),
    ]));
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
