import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/database.dart';
import '../../utils/responsive.dart';

class PrizeSettingsScreen extends StatefulWidget {
  const PrizeSettingsScreen({super.key});
  @override
  State<PrizeSettingsScreen> createState() => _PrizeSettingsScreenState();
}

class _PrizeSettingsScreenState extends State<PrizeSettingsScreen> {
  List<Map<String,dynamic>> _configs = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState(){ super.initState(); _load(); }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final c = await db.getAppConfig();
    if(!mounted) return;
    setState(()=> {_configs = c.where((e)=> (e['key'] as String).contains('numbers') || (e['key'] as String).contains('win4') || (e['key'] as String).contains('straight') || (e['key'] as String).contains('box')).toList(), _loading=false});
  }

  String _desc(String k){
    switch(k){
      case 'numbers_straight': return 'NY Pick3 Straight — 500x per \$1';
      case 'numbers_box_3way': return 'Pick3 Box 3-Way — 160x';
      case 'numbers_box_6way': return 'Pick3 Box 6-Way — 80x';
      case 'win4_straight': return 'Win4 Straight — 5000x';
      case 'win4_box_4way': return 'Win4 Box 4-Way — 1200x';
      case 'win4_box_6way': return 'Win4 Box 6-Way — 800x';
      case 'win4_box_12way': return 'Win4 Box 12-Way — 400x';
      case 'win4_box_24way': return 'Win4 Box 24-Way — 200x';
      default: return k;
    }
  }

  Future<void> _edit(String key, String current) async {
    final ctrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(context: context, builder: (c)=> AlertDialog(
      title: Text(key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_desc(key), style: const TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 8),
        TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: key, border: const OutlineInputBorder(), isDense: true)),
      ]),
      actions: [TextButton(onPressed: ()=> Navigator.pop(c,false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0B8A3E)), onPressed: ()=> Navigator.pop(c,true), child: const Text('Save'))],
    ));
    if(ok!=true) return;
    await context.read<AppDatabase>().upsertConfig(key, ctrl.text.trim(), 'local');
    await _load();
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved'), backgroundColor: Color(0xFF0B8A3E)));
  }

  @override
  Widget build(BuildContext context){
    const green = Color(0xFF0B8A3E);
    final filtered = _search.isEmpty ? _configs : _configs.where((e)=> (e['key'] as String).toLowerCase().contains(_search.toLowerCase())).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(backgroundColor: green, foregroundColor: Colors.white, title: const Text('Prize Settings')),
      body: _loading ? const Center(child: CircularProgressIndicator(color: green)) : ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        children: [
          TextField(onChanged: (v)=> setState(()=> _search=v), decoration: InputDecoration(hintText: 'Search prize...', prefixIcon: const Icon(Icons.search, size: 18), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), isDense: true)),
          const SizedBox(height: 10),
          ...filtered.map((e) {
            final k = e['key'] as String; final v = e['value'] as String;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(child: ListTile(
                leading: const CircleAvatar(backgroundColor: Color(0xFFE6F4EA), child: Icon(Icons.emoji_events, color: green, size: 16)),
                title: Text(k, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text(_desc(k), style: const TextStyle(fontSize: 10, color: Colors.black54)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFE6F4EA), borderRadius: BorderRadius.circular(6)), child: Text(v, style: const TextStyle(fontWeight: FontWeight.bold, color: green, fontSize: 12))),
                  IconButton(icon: const Icon(Icons.edit, size: 16, color: green), onPressed: ()=> _edit(k, v)),
                ]),
              )),
            );
          }),
        ],
      ),
    );
  }
}
