import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/database.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final c = await db.getAppConfig();
    if (!mounted) return;
    setState(() { _configs = c; _loading = false; });
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
          (_filter == 'prizes' && (k.contains('numbers') || k.contains('win4') || k.contains('straight') || k.contains('box'))) ||
          (_filter == 'printer' && k.contains('printer')) ||
          (_filter == 'general' && !k.contains('numbers') && !k.contains('win4') && !k.contains('straight') && !k.contains('box') && !k.contains('printer'));
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
