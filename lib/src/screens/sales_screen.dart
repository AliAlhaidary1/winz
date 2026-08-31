import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/database.dart';
import '../utils/format.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List<Map<String,dynamic>> _tickets = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final t = await db.getTickets();
    setState(() { _tickets = t; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sales — Transactions'), backgroundColor: Theme.of(context).colorScheme.inversePrimary, actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _tickets.isEmpty ? const Center(child: Text('No sales yet. Create via Numbers or Winz.')) : ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: _tickets.length,
        separatorBuilder: (_,__)=>const Divider(height: 1),
        itemBuilder: (c,i){
          final t = _tickets[i];
          return ListTile(
            leading: CircleAvatar(backgroundColor: t['gameName']=='Winz'? Colors.orange.shade100: Colors.indigo.shade100, child: Icon(t['gameName']=='Winz'? Icons.emoji_events: Icons.numbers, size: 18)),
            title: Text('${t['id']} • ${t['gameName']} • ${t['betType']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            subtitle: Text('${t['numbers']} • ${fmtMoney(t['amount'])} • ${fmtDate(t['createdAt'])} • ${t['operatorName']} • ${t['status']}', style: const TextStyle(fontSize: 10)),
            trailing: Text(fmtMoney(t['total']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            onTap: () => Navigator.pushNamed(context, '/ticket_detail', arguments: t),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(icon: const Icon(Icons.add), label: const Text('New Sale'), onPressed: ()=>Navigator.pushNamed(context, '/lottery')),
    );
  }
}
