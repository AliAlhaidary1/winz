import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/database.dart';
import '../providers/app_state.dart';

class WorkersScreen extends StatefulWidget {
  const WorkersScreen({super.key});
  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  List<Map<String,dynamic>> _workers = [];
  bool _loading = true;

  @override
  void initState(){ super.initState(); _load(); }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final all = await db.getAccounts();
    if(!mounted) return;
    setState((){ _workers = all.where((e)=> e['role']=='worker').toList(); _loading=false; });
  }

  Future<void> _addWorker() async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final commCtrl = TextEditingController(text: '5.0');
    final ok = await showDialog<bool>(context: context, builder: (c)=> AlertDialog(
      title: const Text('Add Worker'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: userCtrl, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 8),
        TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 8),
        TextField(controller: commCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Commission %', hintText: '5.0', border: OutlineInputBorder(), isDense: true)),
      ]),
      actions: [TextButton(onPressed: ()=> Navigator.pop(c,false), child: const Text('Cancel')), ElevatedButton(onPressed: ()=> Navigator.pop(c,true), child: const Text('Add'))],
    ));
    if(ok!=true) return;
    if(userCtrl.text.trim().isEmpty || passCtrl.text.isEmpty) return;
    final comm = double.tryParse(commCtrl.text) ?? 5.0;
    final db = context.read<AppDatabase>();
    final id = 'acc_${DateTime.now().millisecondsSinceEpoch}';
    try{
      await db.customStatement("INSERT INTO accounts (id, username, password, role, status, createdAt, commission) VALUES (?, ?, ?, 'worker', 'active', ?, ?)", [id, userCtrl.text.trim(), passCtrl.text, DateTime.now().millisecondsSinceEpoch, comm]);
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
      return;
    }
    await _load();
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Worker added'), backgroundColor: Color(0xFF0B8A3E)));
  }

  Future<void> _editCommission(Map<String,dynamic> w) async {
    final ctrl = TextEditingController(text: (w['commission'] as num?)?.toString() ?? '5.0');
    final ok = await showDialog<bool>(context: context, builder: (c)=> AlertDialog(
      title: Text('Commission for ${w['username']}'),
      content: TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Commission %', border: OutlineInputBorder(), isDense: true)),
      actions: [TextButton(onPressed: ()=> Navigator.pop(c,false), child: const Text('Cancel')), ElevatedButton(onPressed: ()=> Navigator.pop(c,true), child: const Text('Save'))],
    ));
    if(ok!=true) return;
    final v = double.tryParse(ctrl.text) ?? 0;
    final db = context.read<AppDatabase>();
    await db.customStatement("UPDATE accounts SET commission=? WHERE id=?", [v, w['id']]);
    await _load();
  }

  Future<void> _deleteWorker(Map<String,dynamic> w) async {
    final ok = await showDialog<bool>(context: context, builder: (c)=> AlertDialog(
      title: const Text('Delete Worker'),
      content: Text('Delete ${w['username']}?'),
      actions: [TextButton(onPressed: ()=> Navigator.pop(c,false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: ()=> Navigator.pop(c,true), child: const Text('Delete'))],
    ));
    if(ok!=true) return;
    final db = context.read<AppDatabase>();
    await db.customStatement("DELETE FROM accounts WHERE id=?", [w['id']]);
    await _load();
  }

  @override
  Widget build(BuildContext context){
    final isAdmin = context.watch<AppState>().isAdmin;
    if(!isAdmin){
      return Scaffold(appBar: AppBar(title: const Text('Workers'), backgroundColor: const Color(0xFF0B8A3E), foregroundColor: Colors.white), body: const Center(child: Text('Admin only')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Workers - Manage'), backgroundColor: const Color(0xFF0B8A3E), foregroundColor: Colors.white, actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      floatingActionButton: FloatingActionButton.extended(icon: const Icon(Icons.person_add), label: const Text('Add Worker'), backgroundColor: const Color(0xFF0B8A3E), onPressed: _addWorker),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _workers.isEmpty ? const Center(child: Text('No workers')) : ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _workers.length,
        separatorBuilder: (_,__)=> const SizedBox(height: 8),
        itemBuilder: (c,i){
          final w = _workers[i];
          return Card(child: ListTile(
            leading: CircleAvatar(backgroundColor: Colors.blue.shade50, child: Text((w['username'] as String)[0].toUpperCase(), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
            title: Text(w['username'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text('Commission ${w["commission"] ?? 0}% - ${w["status"]}', style: const TextStyle(fontSize: 11)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit, size: 18, color: Colors.blue), onPressed: ()=> _editCommission(w)),
              IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: ()=> _deleteWorker(w)),
            ]),
          ));
        },
      ),
    );
  }
}
