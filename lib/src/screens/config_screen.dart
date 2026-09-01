import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/database.dart';
import '../services/draw_period_service.dart';
import '../providers/app_state.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  List<Map<String, dynamic>> _configs = [];
  bool _loading = true;
  String _filter = 'all';
  String _search = '';
  List<Map<String, dynamic>> _drawConfigs = [];
  String _tz = 'America/New_York';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final c = await db.getAppConfig();
    final svc = DrawPeriodService(db);
    final dcfgs = await svc.getAllDrawConfigs();
    final tz = await svc.getTimezone();
    if (!mounted) return;
    setState(() { _configs = c; _drawConfigs = dcfgs; _tz = tz; _loading = false; });
  }

  Future<void> _editDrawConfig(Map<String, dynamic> cfg) async {
    final drawType = cfg['drawType'] as String;
    final salesCloseCtrl = TextEditingController(text: cfg['salesClose']);
    final drawTimeCtrl = TextEditingController(text: cfg['drawTime']);
    bool enabled = cfg['enabled'] as bool;
    String resultMode = cfg['resultMode'] as String;
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: Text('Configure $drawType', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: salesCloseCtrl, decoration: const InputDecoration(labelText: 'Sales Close (HH:MM)', hintText: '14:15', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 8),
        TextField(controller: drawTimeCtrl, decoration: const InputDecoration(labelText: 'Draw Time (HH:MM)', hintText: '14:30', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 8),
        SwitchListTile(value: enabled, title: const Text('Enabled', style: TextStyle(fontSize: 12)), dense: true, onChanged: (v) => setS(() => enabled = v)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(value: resultMode, decoration: const InputDecoration(labelText: 'Result Mode', border: OutlineInputBorder(), isDense: true), items: const [DropdownMenuItem(value: 'manual', child: Text('Manual')), DropdownMenuItem(value: 'auto', child: Text('Automatic'))], onChanged: (v) => setS(() => resultMode = v ?? 'manual')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0B8A3E)), onPressed: () => Navigator.pop(c, true), child: const Text('Save'))],
    )));
    if (ok != true) return;
    final svc = DrawPeriodService(context.read<AppDatabase>());
    final user = context.read<AppState>().currentUser?['username'] as String?;
    try {
      await svc.updateDrawConfig(drawType: drawType, salesClose: salesCloseCtrl.text.trim(), drawTime: drawTimeCtrl.text.trim(), enabled: enabled, resultMode: resultMode, user: user);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$drawType updated — ${salesCloseCtrl.text} / ${drawTimeCtrl.text}'), backgroundColor: const Color(0xFF0B8A3E)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    }
  }

  Future<void> _editTimezone() async {
    final ctrl = TextEditingController(text: _tz);
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Timezone', style: TextStyle(fontSize: 13)),
      content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Timezone', hintText: 'America/New_York', border: OutlineInputBorder(), isDense: true)),
      actions: [TextButton(onPressed: () => Navigator.pop(c,false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(c,true), child: const Text('Save'))],
    ));
    if (ok != true) return;
    final svc = DrawPeriodService(context.read<AppDatabase>());
    await svc.setTimezone(ctrl.text.trim());
    await _load();
  }

  Future<void> _edit(String key, String current, String scope, String desc) async {
    final ctrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(children: [const Icon(Icons.edit, color: Color(0xFF0B8A3E), size: 18), const SizedBox(width: 8), Expanded(child: Text(_title(key), style: const TextStyle(fontSize: 13)))]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(desc, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 8),
          TextField(controller: ctrl, decoration: InputDecoration(labelText: key, border: const OutlineInputBorder(), isDense: true, helperText: 'Scope: $scope — ${scope == 'local' ? 'On device only' : 'On server'}')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0B8A3E)), onPressed: () => Navigator.pop(c, true), child: const Text('Save'))],
      ),
    );
    if (ok == true) {
      await context.read<AppDatabase>().upsertConfig(key, ctrl.text.trim(), scope);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved — applied immediately'), backgroundColor: Color(0xFF0B8A3E)));
    }
  }

  String _desc(String k) {
    switch (k) {
      case 'midday_sales_close': return 'Midday sales close — default 14:15 (02:15 PM)';
      case 'midday_draw_time': return 'Midday draw time — default 14:30 (02:30 PM)';
      case 'midday_enabled': return 'Midday enabled (1/0)';
      case 'evening_sales_close': return 'Evening sales close — default 22:20 (10:20 PM)';
      case 'evening_draw_time': return 'Evening draw time — default 22:30 (10:30 PM)';
      case 'evening_enabled': return 'Evening enabled (1/0)';
      case 'draw_timezone': return 'Draw timezone — default America/New_York';
      case 'midday_result_mode': return 'Midday result mode — manual / auto';
      case 'evening_result_mode': return 'Evening result mode — manual / auto';
      case 'numbers_straight': return 'NY Pick3 Straight — 500x per \$1 (exact match)';
      case 'numbers_box_3way': return 'Pick3 Box 3-Way 112 — 160x (any order, 3 combos)';
      case 'numbers_box_6way': return 'Pick3 Box 6-Way 123 — 80x (6 combos)';
      case 'win4_straight': return 'Win4 Straight — 5000x per \$1';
      case 'win4_box_4way': return 'Win4 Box 4-Way 1112 — 1200x';
      case 'win4_box_6way': return 'Win4 Box 6-Way 1122 — 800x';
      case 'win4_box_12way': return 'Win4 Box 12-Way 1123 — 400x';
      case 'win4_box_24way': return 'Win4 Box 24-Way 1234 — 200x (any permutation)';
      case 'straight_3d_multiplier': return 'Legacy — use numbers_straight';
      case 'currency': return 'Currency (USD)';
      case 'language': return 'Language';
      case 'company_name': return 'Company name on ticket';
      case 'ticket_footer': return 'Ticket footer text';
      case 'printer_type': return 'Printer type 58/80mm';
      case 'printer_connection': return 'Printer connection Bluetooth/USB';
      default: return k;
    }
  }

  String _title(String k){
    // Format key like numbers_box_3way -> Numbers Box 3Way
    return k.replaceAll('_',' ').split(' ').map((w)=> w.isEmpty? w : w[0].toUpperCase()+w.substring(1)).join(' ');
  }

  IconData _icon(String k) {
    if (k.contains('box') || k.contains('straight') || k.contains('win4') || k.contains('numbers')) return Icons.emoji_events;
    if (k.contains('printer')) return Icons.print;
    if (k.contains('currency') || k.contains('company')) return Icons.business;
    if (k.contains('language')) return Icons.language;
    return Icons.settings;
  }

  Color _catColor(String k) {
    if (k.contains('midday') || k.contains('evening') || k.contains('draw_')) return Colors.deepPurple;
    if (k.contains('numbers') || k.contains('win4') || k.contains('straight') || k.contains('box')) return const Color(0xFF0B8A3E);
    if (k.contains('printer')) return Colors.orange;
    if (k.contains('currency') || k.contains('company')) return Colors.blue;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF0B8A3E);
    const greenLight = Color(0xFFE6F4EA);
    final filtered = _configs.where((e) {
      final k = e['key'] as String;
      final catOk = _filter == 'all' ||
          (_filter == 'draws' && (k.contains('midday') || k.contains('evening') || k.contains('draw_') || k.contains('auto_open') || k.contains('result_mode'))) ||
          (_filter == 'prizes' && (k.contains('numbers') || k.contains('win4') || k.contains('straight') || k.contains('box'))) ||
          (_filter == 'printer' && k.contains('printer')) ||
          (_filter == 'general' && !k.contains('numbers') && !k.contains('win4') && !k.contains('straight') && !k.contains('box') && !k.contains('printer') && !k.contains('midday') && !k.contains('evening') && !k.contains('draw_'));
      final searchOk = _search.isEmpty || k.toLowerCase().contains(_search.toLowerCase()) || (e['value'] as String).toLowerCase().contains(_search.toLowerCase());
      return catOk && searchOk;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        backgroundColor: green,
        foregroundColor: Colors.white,
        title: const Text('Settings — Config', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: green))
          : Column(children: [
              // Header green
              Container(
                color: green,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(children: [
                  TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'Search: e.g. box, printer...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                    SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final f in [
                        ('all', 'All'),
                        ('draws', 'Draw Schedule'),
                        ('prizes', 'Prizes NY'),
                        ('printer', 'Printer'),
                        ('general', 'General'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(f.$2, style: TextStyle(fontSize: 11, color: _filter == f.$1 ? Colors.white : green)),
                            selected: _filter == f.$1,
                            selectedColor: Colors.white.withOpacity(0.25),
                            backgroundColor: Colors.white,
                            onSelected: (_) => setState(() => _filter = f.$1),
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
              // Draw Schedule Section (Spec #2)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.schedule, size: 16, color: Colors.deepPurple),
                    const SizedBox(width: 6),
                    const Text('Draw Schedule (Spec §1-2)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepPurple)),
                    const Spacer(),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Text(_tz, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.deepPurple))),
                    IconButton(icon: const Icon(Icons.edit, size: 14, color: Colors.deepPurple), onPressed: _editTimezone),
                  ]),
                  const SizedBox(height: 8),
                  ..._drawConfigs.map((cfg) {
                    final type = cfg['drawType'] as String;
                    final enabled = cfg['enabled'] as bool;
                    return Card(
                      color: enabled ? Colors.white : Colors.grey.shade100,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: enabled ? Colors.deepPurple.withOpacity(0.15) : Colors.grey.shade300)),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: enabled ? Colors.deepPurple.withOpacity(0.1) : Colors.grey.shade200, child: Icon(type == 'MIDDAY' ? Icons.wb_sunny : Icons.nights_stay, color: enabled ? Colors.deepPurple : Colors.grey, size: 16)),
                        title: Text(type == 'MIDDAY' ? 'Midday' : 'Evening', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: enabled ? Colors.black87 : Colors.black54)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Sales Close: ${cfg['salesClose']}  •  Draw: ${cfg['drawTime']}  •  ${cfg['resultMode']}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                          Row(children: [
                            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: enabled ? Colors.green.shade50 : Colors.red.shade50, borderRadius: BorderRadius.circular(6)), child: Text(enabled ? 'ON' : 'OFF', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: enabled ? Colors.green : Colors.red))),
                            const SizedBox(width: 6),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFEDE7F6), borderRadius: BorderRadius.circular(6)), child: Text(cfg['timezone'], style: const TextStyle(fontSize: 9))),
                          ]),
                        ]),
                        trailing: IconButton(icon: const Icon(Icons.edit, size: 16, color: Colors.deepPurple), onPressed: () => _editDrawConfig(cfg)),
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                  Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFF3E8FF), borderRadius: BorderRadius.circular(8)), child: const Row(children: [Icon(Icons.info_outline, size: 12, color: Colors.deepPurple), SizedBox(width: 6), Expanded(child: Text('Defaults: Midday 14:15/14:30, Evening 22:20/22:30, TZ America/New_York. Not hard-coded — admin can change anytime. All changes are audit-logged.', style: TextStyle(fontSize: 10, color: Colors.deepPurple)))])),
                ]),
              ),
              // Info card
              Padding(
                padding: const EdgeInsets.all(12),
                child: Card(
                  color: greenLight,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      const Icon(Icons.lightbulb, color: green, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Green = NY official prizes. Change value and tap Save — applied instantly to prize calculation.', style: TextStyle(fontSize: 11))),
                      TextButton(onPressed: () => Navigator.pushNamed(context, '/admin/draw'), child: const Text('Go to Draw', style: TextStyle(color: green, fontWeight: FontWeight.bold, fontSize: 11))),
                    ]),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: [
                    ...filtered.map((e) {
                      final k = e['key'] as String;
                      final v = e['value'] as String;
                      final scope = e['scope'] as String;
                      return Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: _catColor(k).withOpacity(0.12))),
                        child: ListTile(
                          leading: CircleAvatar(radius: 18, backgroundColor: _catColor(k).withOpacity(0.12), child: Icon(_icon(k), color: _catColor(k), size: 16)),
                          title: Text(_title(k), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_desc(k), style: const TextStyle(fontSize: 10, color: Colors.black54)),
                            const SizedBox(height: 2),
                            Row(children: [
                              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: greenLight, borderRadius: BorderRadius.circular(6)), child: Text(v, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: green))),
                              const SizedBox(width: 6),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)), child: Text(scope, style: const TextStyle(fontSize: 9))),
                            ]),
                          ]),
                          trailing: IconButton(icon: const Icon(Icons.edit, size: 16, color: green), onPressed: () => _edit(k, v, scope, _desc(k))),
                        ),
                      );
                    }),
                    if (filtered.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No results', style: TextStyle(color: Colors.black54)))),
                    const SizedBox(height: 12),
                    Card(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Who can edit?', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          const Text('• Prizes: Admin only — any change instantly affects prize = amount × multiplier', style: TextStyle(fontSize: 10, color: Colors.black54)),
                          const Text('• Printer/Language: Agent can edit', style: TextStyle(fontSize: 10, color: Colors.black54)),
                          const Text('• Company/Footer: Admin (server scope)', style: TextStyle(fontSize: 10, color: Colors.black54)),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
    );
  }
}
