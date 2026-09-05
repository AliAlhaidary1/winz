import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../data/database.dart';
import '../utils/responsive.dart';

class BalanceScreen extends StatefulWidget {
  const BalanceScreen({super.key});
  @override
  State<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends State<BalanceScreen> {
  List<Map<String, dynamic>> _moves = [];
  List<Map<String, dynamic>> _movesAll = [];
  double _balance = 0;
  double _cash = 0;
  bool _loading = true;
  DateTime? _from;
  DateTime? _to;
  String _preset='all';
  void _applyPreset(String p){
    final now=DateTime.now();
    final today=DateTime(now.year, now.month, now.day);
    setState((){
      _preset=p;
      if(p=='today'){ _from=today; _to=today; }
      else if(p=='yesterday'){ final y=today.subtract(const Duration(days:1)); _from=y; _to=y; }
      else if(p=='week'){ _from=today.subtract(const Duration(days:6)); _to=today; }
      else if(p=='all'){ _from=null; _to=null; }
    });
    _filter();
  }
  void _filter(){
    if(_from==null && _to==null){ setState(()=> _moves=List.from(_movesAll)); return; }
    final filtered=_movesAll.where((e){
      final dt=DateTime.fromMillisecondsSinceEpoch(e['createdAt'] as int);
      final d=DateTime(dt.year,dt.month,dt.day);
      if(_from!=null && d.isBefore(DateTime(_from!.year,_from!.month,_from!.day))) return false;
      if(_to!=null && d.isAfter(DateTime(_to!.year,_to!.month,_to!.day))) return false;
      return true;
    }).toList();
    setState(()=> _moves=filtered);
  }
  String _fmtShort(DateTime? d)=> d==null? '--': '${d.year}/${d.month.toString().padLeft(2,'0')}/${d.day.toString().padLeft(2,'0')}';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final app = context.read<AppState>();
    final b = await app.computeGeneralBalance();
    final c = await app.computeCashBalance();
    final opId = app.currentUser?['id'] as String?;
    final m = opId != null ? await db.getBalanceMovementsByOperator(opId) : await db.getBalanceMovements();
    final movesToShow = m.isNotEmpty ? m : await db.getBalanceMovements();
    setState(() { _movesAll = movesToShow; _balance = b; _cash = c; _loading = false; });
    _filter();
  }

  String _fmt(double? v) => v != null ? v.toStringAsFixed(2) : '0.00';

  String _fmtDate(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${d.month}/${d.day}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: color.surface,
        elevation: 0,
        title: const Text('General Balance'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
              child: Center(
                child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: Responsive.contentMaxWidth(context)),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Balance',
                                  style:
                                      TextStyle(color: Colors.black45, fontSize: 12)),
                              Text(_fmt(_balance),
                                  style:
                                      TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Cash (Physical)',
                                  style:
                                      TextStyle(color: Colors.black45, fontSize: 12)),
                              Text(_fmt(_cash),
                                  style:
                                      TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.green)),
                            ],
                          ),
                        ),
                      ])),
                  ),
                  const SizedBox(height: 20),

                  Card(child: Padding(padding: EdgeInsets.all(Responsive.horizontalPadding(context)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Filter by Period', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 8),
                    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                      ChoiceChip(label: Text('All', style: TextStyle(color: _preset=='all'? Colors.white: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)), selected: _preset=='all', selectedColor: const Color(0xFF0B8A3E), backgroundColor: Colors.white, side: BorderSide(color: _preset=='all'? const Color(0xFF0B8A3E): Colors.grey.shade300), onSelected: (_)=> _applyPreset('all')),
                      const SizedBox(width: 6),
                      ChoiceChip(label: Text('Today', style: TextStyle(color: _preset=='today'? Colors.white: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)), selected: _preset=='today', selectedColor: const Color(0xFF0B8A3E), backgroundColor: Colors.white, side: BorderSide(color: _preset=='today'? const Color(0xFF0B8A3E): Colors.grey.shade300), onSelected: (_)=> _applyPreset('today')),
                      const SizedBox(width: 6),
                      ChoiceChip(label: Text('Yesterday', style: TextStyle(color: _preset=='yesterday'? Colors.white: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)), selected: _preset=='yesterday', selectedColor: const Color(0xFF0B8A3E), backgroundColor: Colors.white, side: BorderSide(color: _preset=='yesterday'? const Color(0xFF0B8A3E): Colors.grey.shade300), onSelected: (_)=> _applyPreset('yesterday')),
                      const SizedBox(width: 6),
                      ChoiceChip(label: Text('Week', style: TextStyle(color: _preset=='week'? Colors.white: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)), selected: _preset=='week', selectedColor: const Color(0xFF0B8A3E), backgroundColor: Colors.white, side: BorderSide(color: _preset=='week'? const Color(0xFF0B8A3E): Colors.grey.shade300), onSelected: (_)=> _applyPreset('week')),
                      const SizedBox(width: 6),
                      ChoiceChip(label: Text('Custom', style: TextStyle(color: _preset=='custom'? Colors.white: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)), selected: _preset=='custom', selectedColor: const Color(0xFF0B8A3E), backgroundColor: Colors.white, side: BorderSide(color: _preset=='custom'? const Color(0xFF0B8A3E): Colors.grey.shade300), onSelected: (_)=> setState(()=> _preset='custom')),
                    ])),
                    if(_preset=='custom') ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.calendar_today, size: 14), label: Text('From: ${_fmtShort(_from)}', style: const TextStyle(fontSize: 11)), onPressed: () async {
                          final d = await showDatePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime(2030), initialDate: _from??DateTime.now());
                          if(d!=null){ setState(()=> _from=d); _filter(); }
                        })),
                        const SizedBox(width: 8),
                        Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.calendar_today, size: 14), label: Text('To: ${_fmtShort(_to)}', style: const TextStyle(fontSize: 11)), onPressed: () async {
                          final d = await showDatePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime(2030), initialDate: _to??DateTime.now());
                          if(d!=null){ setState(()=> _to=d); _filter(); }
                        })),
                        IconButton(icon: const Icon(Icons.clear), onPressed: (){ setState((){ _from=null; _to=null; _preset='all';}); _filter(); }),
                      ]),
                    ],
                    const SizedBox(height: 6),
                    Text('Showing: ${_moves.length} of ${_movesAll.length} records', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  ]))),
                  const SizedBox(height: 12),

                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('How It Works',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          const Text(
                              'Cash = physical money on hand\nBalance = account position with system (sales - payouts ± adjustments)\nEvery sale → Cash in + Balance credit\nEvery payout → Cash out + Balance debit'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Net Position',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text('Net = Sales - Payouts ± Adjustments = ${_fmt(_balance)}',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text('Balance Movements',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                  const SizedBox(height: 8),
                  ..._moves.map((e) => Card(
                    child: ListTile(
                      title: Text('${e['type']} • ${_fmt(e['amount'])}'),
                      subtitle: Text('${e['description'] ?? ''} • ${_fmtDate(e['createdAt'])}'),
                    ),
                  )),
                  if (_moves.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No movements yet — create a sale to see activity',
                              style: TextStyle(color: Colors.black45))),
                ],
              ),
                ),
              ),
            ),
    );
  }
}
