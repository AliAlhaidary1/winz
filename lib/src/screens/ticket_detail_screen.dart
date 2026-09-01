import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../data/database.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';

class TicketDetailScreen extends StatefulWidget {
  final Map<String, dynamic> ticket;
  const TicketDetailScreen({this.ticket = const {}, super.key});
  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  Map<String,dynamic>? _ticket;
  List<Map<String,dynamic>> _lines = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _ticket = widget.ticket; _refresh(); }

  Future<void> _refresh() async {
    if (_ticket == null || _ticket!['id'] == null) { setState(()=> _loading=false); return; }
    final db = context.read<AppDatabase>();
    final fresh = await db.getTicketById(_ticket!['id']);
    final lines = await db.getTicketLines(_ticket!['id']);
    if (mounted) setState((){ _ticket = fresh ?? _ticket; _lines = lines; _loading=false; });
  }

  String _period(String? name){
    if(name==null) return '-';
    if(name.contains('Morning') || name.contains('Midday')) return 'Morning';
    if(name.contains('Evening')) return 'Evening';
    if(name.contains('Night')) return 'Night';
    return 'Standard';
  }

  Future<void> _share() async {
    final t = _ticket!;
    String numbersPart;
    if(_lines.isNotEmpty) numbersPart = _lines.map((l)=> '${l['numbers'].toString().replaceAll(',', ' ')}(${l['betType']}) ${fmtMoney(l['amount'])}').join(' | ');
    else numbersPart = t['numbers'].toString().replaceAll(',', ' ');
    final txt = 'NY Lottery Ticket\nID:${t['id']}\nSerial:${t['serialNumber']}\nGame:${t['gameName']} ${t['betType']}\nPlays:${_lines.isNotEmpty ? _lines.length : 1}\nNumbers:$numbersPart\nDraw:${t['drawName']} (${_period(t['drawName'])})\nTotal:${fmtMoney(t['total'] ?? t['amount'])}\nDate:${fmtDate(t['createdAt'])}\nOperator:${t['operatorName']}\nStatus:${t['status']}${t['prizeAmount']!=null ? ' Prize:${fmtMoney(t['prizeAmount'])}' : ''}\nBarcode:${t['barcode']}';
    await Share.share(txt);
  }

  Future<void> _cancel() async {
    if (_ticket!['status'] != 'active') return;
    final ok = await showDialog<bool>(context: context, builder: (c)=> AlertDialog(title: const Text('Cancel Ticket'), content: const Text('Cancel this ticket? This will cancel the whole invoice (all plays).'), actions: [TextButton(onPressed: ()=> Navigator.pop(c,false), child: const Text('Keep')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: ()=> Navigator.pop(c,true), child: const Text('Cancel Ticket'))]));
    if(ok!=true) return;
    final db = context.read<AppDatabase>();
    await db.updateTicketStatus(_ticket!['id'], 'cancelled');
    await _refresh();
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ticket cancelled')));
  }

  Future<void> _replay() async {
    final id = _ticket!['id'] as String;
    try{
      final count = await context.read<AppState>().replayTicketToCart(id);
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $count plays to cart — now SALE to create new ticket'), backgroundColor: const Color(0xFF0B8A3E)));
      // Navigate to Numbers if Numbers game else Winz — stay on this screen but offer to go
      showDialog(context: context, builder: (c)=> AlertDialog(
        title: const Text('Re-play Ticket'),
        content: Text('$count plays copied to cart.\nGo to SALE screen?'),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(c), child: const Text('Stay')),
          ElevatedButton(onPressed: (){ Navigator.pop(c); Navigator.pushNamed(context,'/numbers'); }, child: const Text('Go to Numbers')),
          ElevatedButton(onPressed: (){ Navigator.pop(c); Navigator.pushNamed(context,'/winz'); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8E00)), child: const Text('Go to Win 4')),
        ],
      ));
    }catch(e){
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ','')), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _ticket ?? widget.ticket;
    if(t.isEmpty) return Scaffold(appBar: AppBar(title: const Text('Ticket Detail')), body: const Center(child: Text('No ticket')));
    final isWinning = t['status'] == 'winning';
    final isPaid = t['status'] == 'paid';
    final isCancelled = t['status'] == 'cancelled';
    final isActive = t['status'] == 'active';
    const green = Color(0xFF0B8A3E);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(backgroundColor: green, foregroundColor: Colors.white, title: const Text('Ticket Detail'), actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _refresh)]),
      body: _loading ? const Center(child: CircularProgressIndicator(color: green)) : Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Card(color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: isPaid ? Colors.green.shade50 : isWinning ? Colors.orange.shade50 : isCancelled ? Colors.red.shade50 : Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(20)), child: Text(t['status'].toString().toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isPaid ? Colors.green.shade700 : isWinning ? Colors.orange.shade700 : isCancelled ? Colors.red : Colors.black54))),
                  const Spacer(),
                  if(t['isQuickPick']==1) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(20)), child: const Text('QUICK PICK', style: TextStyle(fontSize: 9, color: Colors.indigo, fontWeight: FontWeight.bold))),
                  if(_lines.length>1) Container(margin: const EdgeInsets.only(left:6), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: green.withValues(alpha:0.1), borderRadius: BorderRadius.circular(20)), child: Text('${_lines.length} PLAYS', style: const TextStyle(fontSize: 9, color: green, fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 12),
                const Text('NY LOTTERY POS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                Text('${t['gameName']} • ${t['betType']} ${_lines.length>1 ? '• ${_lines.length} plays' : ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text('${t['drawName'] ?? '-'}  •  Period: ${_period(t['drawName'])}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                const Divider(height: 16),
                if(_lines.isNotEmpty && _lines.length>1)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(border: Border.all(color: Colors.black87, width: 1.0), borderRadius: BorderRadius.circular(8)),
                    child: Column(children: [
                      for(int i=0;i<_lines.length;i++)
                        Container(
                          margin: EdgeInsets.only(bottom: i==_lines.length-1?0:6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(6), color: i%2==0? Colors.white: Colors.grey.shade50),
                          child: Row(children: [
                            Text('${i+1}.', style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Text((_lines[i]['numbers'] as String).replaceAll(',', ' '), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2)),
                            const Spacer(),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)), child: Text(_lines[i]['betType'], style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600))),
                            const SizedBox(width: 6),
                            Text(fmtMoney(_lines[i]['amount']), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ]),
                        ),
                      const Divider(height: 12),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), Text(fmtMoney(t['total'] ?? t['amount']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: green))]),
                    ]),
                  )
                else
                  Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(border: Border.all(color: Colors.black87, width: 1.2), borderRadius: BorderRadius.circular(8)), child: Column(children: [
                    Text((t['numbers'] as String).replaceAll(',', '  '), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 4)),
                    const SizedBox(height: 4),
                    Text('${t['betType']} • ${fmtMoney(t['amount'])}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                    if(isWinning || isPaid) Padding(padding: const EdgeInsets.only(top: 6), child: Text(isPaid ? 'PAID • ${fmtMoney(t['prizeAmount'] ?? 0)}' : 'WINNER • ${fmtMoney(t['prizeAmount'] ?? 0)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isPaid ? Colors.green.shade700 : Colors.orange.shade700))),
                  ]))),
                const SizedBox(height: 12),
                _row('Ticket ID', t['id']),
                _row('Serial', t['serialNumber'] ?? '-'),
                _row('Game', t['gameName']),
                _row('Bet Type', t['betType']),
                _row('Plays', _lines.isNotEmpty ? '${_lines.length}' : '1'),
                _row('Numbers', _lines.isNotEmpty && _lines.length>1 ? _lines.map((l)=> (l['numbers'] as String).replaceAll(',', '')).join(' | ') : (t['numbers'] as String).replaceAll(',', ', ')),
                _row('Total', fmtMoney(t['total'] ?? t['amount'])),
                _row('Draw', t['drawName'] ?? '-'),
                _row('Date', fmtDate(t['createdAt'])),
                _row('Operator', t['operatorName']),
                _row('Barcode', t['barcode'] ?? t['id']),
                if(t['prizeAmount']!=null) _row('Prize', fmtMoney(t['prizeAmount']), bold:true, color: green),
                if(t['paidBy']!=null) _row('Paid By', t['paidBy']),
              ]))),
              const SizedBox(height: 12),
              Card(color: Colors.white, child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                QrImageView(data: t['barcode']??t['id'], size: 140),
                const SizedBox(height: 6),
                Text(t['barcode']??t['id'], style: const TextStyle(fontSize: 10, letterSpacing: 1)),
                const SizedBox(height: 6),
                const Text('Show QR at validation counter — scan to validate', style: TextStyle(fontSize: 10, color: Colors.black45)),
              ]))),
              if(isWinning) Card(color: Colors.green.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Icon(Icons.emoji_events, color: green), const SizedBox(width: 8), Expanded(child: Text('Winning ticket — go to Winning Tickets to collect ${fmtMoney(t['prizeAmount'])}', style: const TextStyle(fontSize: 11)))]))),
              if(isActive) Card(color: Colors.blue.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Icon(Icons.info_outline, color: Colors.blue), const SizedBox(width: 8), const Expanded(child: Text('Active ticket — will be evaluated after draw. You can cancel before cutoff (5 min before draw).', style: TextStyle(fontSize: 11)))]))),
              const SizedBox(height: 12),
              // Action buttons row 1
              Row(children: [
                Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.print, size: 16), label: const Text('Print'), style: ElevatedButton.styleFrom(backgroundColor: green, foregroundColor: Colors.white), onPressed: ()=> Navigator.pushNamed(context, '/print', arguments: t))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.share, size: 16), label: const Text('Share'), onPressed: _share)),
              ]),
              const SizedBox(height: 8),
              // Replay full ticket
              SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.copy, size: 16), label: Text('Copy & Re-play  (${_lines.isNotEmpty? _lines.length : 1} plays)'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0), foregroundColor: Colors.white), onPressed: _replay)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.verified, size: 16), label: const Text('Validate'), onPressed: ()=> Navigator.pushNamed(context, '/winning'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(icon: Icon(Icons.cancel, size: 16, color: isActive ? Colors.red : Colors.grey), label: Text('Cancel', style: TextStyle(color: isActive ? Colors.red : Colors.grey)), onPressed: isActive ? _cancel : null)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _row(String k, dynamic v, {bool bold=false, Color? color}){
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
      SizedBox(width: 90, child: Text(k, style: const TextStyle(fontSize: 11, color: Colors.black54))),
      Expanded(child: Text(v.toString(), style: TextStyle(fontSize: 11, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color ?? Colors.black87))),
    ]));
  }
}
