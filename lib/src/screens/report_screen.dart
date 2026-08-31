import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../data/database.dart';
import '../utils/format.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  List<Map<String,dynamic>> _tickets = [];
  List<Map<String,dynamic>> _cash = [];
  List<Map<String,dynamic>> _moves = [];
  bool _loading = true;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    setState(()=> _loading=true);
    final t = await db.getTickets();
    final c = await db.getCashLedger();
    final m = await db.getBalanceMovements();
    // date filter
    List<Map<String,dynamic>> ft(List<Map<String,dynamic>> list){
      if (_from==null && _to==null) return list;
      return list.where((e){
        final dt = DateTime.fromMillisecondsSinceEpoch(e['createdAt']??e['openedAt']??0);
        if (_from!=null && dt.isBefore(_from!)) return false;
        if (_to!=null && dt.isAfter(_to!.add(const Duration(days:1)))) return false;
        return true;
      }).toList();
    }
    setState(() { _tickets=ft(t); _cash=ft(c); _moves=ft(m); _loading=false; });
  }

  @override
  Widget build(BuildContext context) {
    final totalSales = _tickets.fold<double>(0, (s,e)=> s + (e['total'] as num).toDouble());
    final salesByGame = <String,double>{}; for (final t in _tickets){ final g=t['gameName']; salesByGame[g]=(salesByGame[g]??0)+ (t['total'] as num).toDouble();}
    final winning = _tickets.where((e)=> e['status']=='winning' || e['status']=='paid').toList();
    final paid = _tickets.where((e)=> e['status']=='paid').fold<double>(0,(s,e)=> s+ ((e['prizeAmount'] as num?)?.toDouble() ?? 0));
    final cashIn = _cash.where((e)=> e['direction']=='in').fold<double>(0,(s,e)=> s+ (e['amount'] as num).toDouble());
    final cashOut = _cash.where((e)=> e['direction']=='out').fold<double>(0,(s,e)=> s+ (e['amount'] as num).toDouble());

    return Scaffold(
      appBar: AppBar(title: const Text('Get Report — Reporting'), backgroundColor: Theme.of(context).colorScheme.inversePrimary, actions: [
        IconButton(icon: const Icon(Icons.share), onPressed: (){
          final txt = 'YeLottery Report\nSales:${fmtMoney(totalSales)} tickets:${_tickets.length}\nWinning:${winning.length} paid:${fmtMoney(paid)}\nCash in:${fmtMoney(cashIn)} out:${fmtMoney(cashOut)} close:${fmtMoney(cashIn-cashOut)}';
          Share.share(txt);
        }),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: _loading? const Center(child: CircularProgressIndicator()): SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
          Expanded(child: Text(_from==null? 'From: —': 'From: ${dateOnlyFmt.format(_from!)}', style: const TextStyle(fontSize: 11))),
          Expanded(child: Text(_to==null? 'To: —': 'To: ${dateOnlyFmt.format(_to!)}', style: const TextStyle(fontSize: 11))),
          TextButton(onPressed: () async {
            final d = await showDatePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime(2030), initialDate: DateTime.now());
            if (d!=null) setState(()=> _from=d);
            await _load();
          }, child: const Text('From')),
          TextButton(onPressed: () async {
            final d = await showDatePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime(2030), initialDate: DateTime.now());
            if (d!=null) setState(()=> _to=d);
            await _load();
          }, child: const Text('To')),
          IconButton(icon: const Icon(Icons.clear), onPressed: (){ setState(()=> {_from=null, _to=null}); _load();}),
        ]))),
        _section('Sales', [
          'Total sales: ${fmtMoney(totalSales)}',
          'Number of tickets: ${_tickets.length}',
          ...salesByGame.entries.map((e)=> 'Sales by ${e.key}: ${fmtMoney(e.value)}'),
          'Sales by operator: ${_tickets.fold<Map<String,int>>({}, (m,e){ final o=e['operatorName']; m[o]=(m[o]??0)+1; return m;}).entries.map((e)=>'${e.key}:${e.value}').join(', ')}',
        ]),
        _section('Winning Tickets', [
          'Winning tickets: ${winning.length}',
          'Prize total: ${fmtMoney(winning.fold<double>(0,(s,e)=> s+ ((e['prizeAmount'] as num?)?.toDouble()??0)))}',
          'Paid prizes: ${fmtMoney(paid)} (${_tickets.where((e)=>e['status']=='paid').length} tickets)',
          'Unpaid: ${fmtMoney(winning.where((e)=>e['status']=='winning').fold<double>(0,(s,e)=> s+ ((e['prizeAmount'] as num?)?.toDouble()??0)))}',
        ]),
        _section('Cash', [
          'Sales in: ${fmtMoney(cashIn)}',
          'Prize payments out: ${fmtMoney(cashOut)}',
          'Deposits/withdrawals included in ledger: ${_cash.where((e)=> e['type']=='deposit'||e['type']=='withdrawal').length} rows',
          'Closing cash: ${fmtMoney(cashIn-cashOut)}',
          'Sessions: ${awaitCount()}',
        ]),
        _section('Balance', [
          'General balance: ${fmtMoney(_moves.where((e)=>e['direction']=='credit').fold<double>(0,(s,e)=>s+(e['amount'] as num).toDouble()) - _moves.where((e)=>e['direction']=='debit').fold<double>(0,(s,e)=>s+(e['amount'] as num).toDouble()))}',
          'Credits: ${fmtMoney(_moves.where((e)=>e['direction']=='credit').fold<double>(0,(s,e)=>s+(e['amount'] as num).toDouble()))}',
          'Debits: ${fmtMoney(_moves.where((e)=>e['direction']=='debit').fold<double>(0,(s,e)=>s+(e['amount'] as num).toDouble()))}',
          'Movements: ${_moves.length}',
        ]),
        const SizedBox(height: 8),
        const Text('Every report is sliceable by date/operator/game. Export via Share as text (PDF export via Print).', style: TextStyle(fontSize: 10, color: Colors.black54)),
      ])),
    );
  }

  Widget _section(String title, List<String> rows){
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      const Divider(height: 8),
      ...rows.map((r)=> Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: Text('• $r', style: const TextStyle(fontSize: 11)))),
    ])));
  }

  String awaitCount() => '${_cash.length} ledger rows';
}
