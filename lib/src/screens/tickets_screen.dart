import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/database.dart';
import '../utils/format.dart';
import '../theme/app_theme.dart';

class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});
  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  List<Map<String,dynamic>> _tickets = [];
  String _filter = 'all';
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    List<Map<String,dynamic>> t;
    if (_filter=='all') t = await db.getTickets();
    else t = await db.getTickets(status: _filter);
    if(mounted) setState(() { _tickets=t; _loading=false; });
  }

  Color _color(String s){
    switch(s){ case 'paid': return AppTheme.green; case 'winning': return Colors.orange; case 'losing': return Colors.red; case 'cancelled': return Colors.grey; default: return AppTheme.blue; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Tickets'), actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _load)]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12,10,12,10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [const Text('Filter', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), const Spacer(), Text('${_tickets.length} tickets', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted))]),
                const SizedBox(height: 8),
                SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                  for(final f in ['all','active','winning','paid','losing','cancelled'])
                    Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
                      label: Text(f.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _filter==f? Colors.white: AppTheme.textMuted)),
                      selected: _filter==f,
                      selectedColor: _filter==f? _color(f) : null,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: _filter==f? _color(f): AppTheme.cardBorder),
                      onSelected: (_)=> setState(()=> { _filter=f, _loading=true, _load()}),
                    )),
                ])),
              ]),
            ),
            Expanded(child: _loading? const Center(child: CircularProgressIndicator(color: AppTheme.green))
                : _tickets.isEmpty? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: AppTheme.cardBorder)), child: const Icon(Icons.inbox_outlined, color: AppTheme.textMuted)),
                    const SizedBox(height: 12),
                    const Text('No tickets found', style: TextStyle(fontWeight: FontWeight.w700)),
                    const Text('Try another filter or create a sale', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ])))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _tickets.length,
                    separatorBuilder: (_,__)=> const SizedBox(height: 10),
                    itemBuilder: (c,i){
                      final t=_tickets[i];
                      final col=_color(t['status']);
                      return Container(
                        decoration: AppTheme.cardDecoration(borderColor: col.withValues(alpha: 0.12)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: ()=> Navigator.pushNamed(context,'/ticket_detail', arguments: t),
                          child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                            Container(width: 4, height: 56, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(4))),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text('${t['serialNumber']??t['id']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
                                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: col.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)), child: Text(t['status'], style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: col))),
                              ]),
                              const SizedBox(height: 4),
                              Text('${t['gameName']} • ${t['betType']}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                              const SizedBox(height: 6),
                              Row(children: [
                                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppTheme.bg, borderRadius: BorderRadius.circular(8)), child: Text((t['numbers'] as String).replaceAll(',', '  '), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1))),
                                const Spacer(),
                                Text(fmtMoney(t['amount']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                              ]),
                              const SizedBox(height: 4),
                              Text('ID ${t['id']} • ${fmtDate(t['createdAt'])} • ${t['operatorName']}', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted), overflow: TextOverflow.ellipsis),
                            ])),
                          ])),
                        ),
                      );
                    },
                  )),
          ]),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(icon: const Icon(Icons.add), label: const Text('New Sale'), backgroundColor: AppTheme.green, foregroundColor: Colors.white, onPressed: ()=> Navigator.pushNamed(context,'/numbers')),
    );
  }
}
