import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/database.dart';
import '../../utils/responsive.dart';

class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});
  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  List<Map<String,dynamic>> _configs = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState(){ super.initState(); _load(); }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final c = await db.getAppConfig();
    if(!mounted) return;
    setState(()=> {_configs = c.where((e){
      final k = e['key'] as String;
      return !k.contains('numbers') && !k.contains('win4') && !k.contains('straight') && !k.contains('box') && !k.contains('midday') && !k.contains('evening') && !k.contains('draw_') && !k.contains('backup') && k!='winning_time_restricted' && k!='ticket_seq' && k!='serial_seq';
    }).toList(), _loading=false});
  }

  String _desc(String k){
    switch(k){
      case 'currency': return 'Currency (USD)';
      case 'language': return 'Language';
      case 'company_name': return 'Company name on ticket';
      case 'ticket_footer': return 'Ticket footer text';
      case 'printer_type': return 'Printer type 58/80mm';
      case 'printer_connection': return 'Printer connection Bluetooth/USB';
      default: return k;
    }
  }

  Future<void> _edit(String key, String current, String scope) async {
    final ctrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(context: context, builder: (c)=> AlertDialog(
      title: Text(key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      content: TextField(controller: ctrl, decoration: InputDecoration(labelText: key, border: const OutlineInputBorder(), isDense: true, helperText: 'Scope: $scope')),
      actions: [TextButton(onPressed: ()=> Navigator.pop(c,false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0B8A3E)), onPressed: ()=> Navigator.pop(c,true), child: const Text('Save'))],
    ));
    if(ok!=true) return;
    await context.read<AppDatabase>().upsertConfig(key, ctrl.text.trim(), scope);
    await _load();
  }

  @override
  Widget build(BuildContext context){
    const green = Color(0xFF0B8A3E);
    final filtered = _search.isEmpty ? _configs : _configs.where((e)=> (e['key'] as String).toLowerCase().contains(_search.toLowerCase())).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(backgroundColor: green, foregroundColor: Colors.white, title: const Text('General Settings')),
      body: _loading ? const Center(child: CircularProgressIndicator(color: green)) : Column(children: [
        Padding(padding: EdgeInsets.all(Responsive.horizontalPadding(context)), child: TextField(onChanged: (v)=> setState(()=> _search=v), decoration: InputDecoration(hintText: 'Search...', prefixIcon: const Icon(Icons.search, size: 18), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), isDense: true))),
        Expanded(child: ListView.separated(padding: EdgeInsets.all(Responsive.horizontalPadding(context)), itemCount: filtered.length, separatorBuilder: (_,__)=> const SizedBox(height: 8), itemBuilder: (c,i){
          final e = filtered[i];
          return Card(child: ListTile(
            leading: CircleAvatar(backgroundColor: Colors.blue.withOpacity(0.1), child: Icon(e['key'].toString().contains('printer')? Icons.print: Icons.settings, color: Colors.blue, size: 16)),
            title: Text(e['key'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            subtitle: Text(e['value'], style: const TextStyle(fontSize: 11, color: Colors.black54)),
            trailing: IconButton(icon: const Icon(Icons.edit, size: 16, color: green), onPressed: ()=> _edit(e['key'], e['value'], e['scope'])),
          ));
        })),
      ]),
    );
  }
}
