import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/database.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';

class AdminDrawScreen extends StatefulWidget {
  const AdminDrawScreen({super.key, required this.drawId});
  final String drawId;

  @override
  State<AdminDrawScreen> createState() => _AdminDrawScreenState();
}

class _AdminDrawScreenState extends State<AdminDrawScreen> {
  String _gameId = 'g_numbers';
  String? _selectedDrawId;
  List<Map<String, dynamic>> _draws = [];
  final _winCtrl = TextEditingController();
  bool _processing = false;
  String? _error;
  String? _success;
  Map<String, dynamic>? _lastResult;
  List<Map<String, dynamic>> _winningTickets = [];
  bool _autoPay = false;

  @override
  void initState() {
    super.initState();
    // widget.drawId may be empty or specific game id passed via route /admin/draw
    if (widget.drawId.isNotEmpty && widget.drawId.startsWith('g_')) {
      _gameId = widget.drawId;
    }
    _loadDraws();
  }

  @override
  void dispose() {
    _winCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDraws() async {
    final db = context.read<AppDatabase>();
    List<Map<String, dynamic>> draws;
    if (_gameId == 'all') {
      draws = await db.getAllDraws();
    } else {
      draws = await db.getDrawsByGame(_gameId);
    }
    if (!mounted) return;
    setState(() {
      _draws = draws;
      if (_selectedDrawId == null && draws.isNotEmpty) {
        // Prefer open draws first, otherwise first
        final open = draws.where((d) => d['status'] == 'open').toList();
        _selectedDrawId = (open.isNotEmpty ? open.first : draws.first)['id'] as String;
        _fillWinCtrlFromDraw();
      } else if (_selectedDrawId != null) {
        _fillWinCtrlFromDraw();
      }
    });
    await _loadWinningPreview();
  }

  void _fillWinCtrlFromDraw() {
    if (_selectedDrawId == null) return;
    final d = _draws.where((e) => e['id'] == _selectedDrawId).firstOrNull;
    if (d != null && d['winningNumbers'] != null) {
      final s = (d['winningNumbers'] as String).replaceAll(',', '');
      _winCtrl.text = s;
    } else {
      // keep empty if no winning yet, don't overwrite user's typing if already set
      if (_success == null) _winCtrl.text = '';
    }
  }

  Future<void> _loadWinningPreview() async {
    if (_selectedDrawId == null) return;
    final db = context.read<AppDatabase>();
    final tickets = await db.getTickets();
    final draw = _draws.where((e) => e['id'] == _selectedDrawId).firstOrNull;
    final winStr = draw?['winningNumbers'] as String?;
    if (winStr == null || winStr.isEmpty) {
      if (mounted) setState(() => _winningTickets = []);
      return;
    }
    // Show already winning tickets for this draw
    final winning = tickets.where((t) => t['drawId'] == _selectedDrawId && (t['status'] == 'winning' || t['status'] == 'paid')).toList();
    if (mounted) setState(() => _winningTickets = winning);
  }

  Future<void> _submit() async {
    setState(() { _error = null; _success = null; _lastResult = null; });
    if (_selectedDrawId == null) {
      setState(() => _error = 'Please select a draw first');
      return;
    }
    final raw = _winCtrl.text.trim().replaceAll(',', '').replaceAll(' ', '');
    if (raw.isEmpty) {
      setState(() => _error = 'Enter winning number (e.g. 123 or 1234)');
      return;
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(raw)) {
      setState(() => _error = 'Winning number must be digits 0-9 only');
      return;
    }
    // validation per game — NY official
    if (_gameId == 'g_numbers' && raw.length != 3 && raw.length != 4) {
      setState(() => _error = 'Numbers requires 3 or 4 digits (e.g. 123 or 0123) — 0 allowed');
      return;
    }
    if (_gameId == 'g_winz' && raw.length != 4) {
      setState(() => _error = 'Win 4 requires exactly 4 digits (e.g. 0123) — 0 allowed');
      return;
    }
    final draw = _draws.where((e) => e['id'] == _selectedDrawId).firstOrNull;
    if (draw != null && draw['winningNumbers'] != null && (draw['winningNumbers'] as String).isNotEmpty) {
      final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: const Text('Confirm Replace Result'),
        content: Text('Draw $_selectedDrawId already has result: ${draw['winningNumbers']}. Replace with $raw and recalculate winners?'),
        actions: [TextButton(onPressed: () => Navigator.pop(c,false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(c,true), child: const Text('Replace'))],
      ));
      if (confirm != true) return;
    }

    setState(() => _processing = true);
    try {
      final digits = raw.split('');
      final app = context.read<AppState>();
      final res = await app.processDrawResult(drawId: _selectedDrawId!, winningNumbers: digits, autoPay: _autoPay);
      await _loadDraws();
      await _loadWinningPreview();
      if (!mounted) return;
      setState(() {
        _success = 'Winning number $raw saved — Winners: ${res['winningCount']} • Losers: ${res['losingCount']} • Total prizes: ${fmtMoney(res['totalPrize'])}';
        _lastResult = res;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_success!)));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draw = _selectedDrawId == null ? null : _draws.where((e) => e['id'] == _selectedDrawId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Draw Result — NY Lottery'), backgroundColor: const Color(0xFF0B8A3E), foregroundColor: Colors.white),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Game picker
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              value: _gameId,
              decoration: const InputDecoration(labelText: 'Game', border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'g_numbers', child: Text('Numbers (Pick 3/4)')),
                DropdownMenuItem(value: 'g_winz', child: Text('Win 4 (Pick 4)')),
                DropdownMenuItem(value: 'all', child: Text('All')),
              ],
              onChanged: (v) async {
                setState(() { _gameId = v!; _selectedDrawId = null; _winCtrl.clear(); });
                await _loadDraws();
              },
            )),
            const SizedBox(width: 12),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDraws),
          ]),
          const SizedBox(height: 12),
          // Draw picker
          DropdownButtonFormField<String>(
            value: _selectedDrawId,
            decoration: const InputDecoration(labelText: 'Draw', border: OutlineInputBorder(), isDense: true),
            isExpanded: true,
            items: _draws.map((d) {
              final win = d['winningNumbers'] as String?;
              final status = d['status'] as String;
              final label = win != null && win.isNotEmpty ? '${d['name']} • $status • Winner: ${win.replaceAll(',', '')}' : '${d['name']} • $status';
              return DropdownMenuItem<String>(value: d['id'] as String, child: Text(label, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis));
            }).toList(),
            onChanged: (v) {
              setState(() { _selectedDrawId = v; _error=null; _success=null; _lastResult=null; });
              _fillWinCtrlFromDraw();
              _loadWinningPreview();
            },
          ),
          if (draw != null) ...[
            const SizedBox(height: 8),
            Card(color: draw['status']=='closed'? Colors.green.shade50: Colors.blue.shade50, child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Draw status: ${draw['status']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              if (draw['winningNumbers'] != null) Text('Current winning number: ${(draw['winningNumbers'] as String).replaceAll(',', ' ')}', style: const TextStyle(fontSize: 12)),
              Text('ID: ${draw['id']}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
            ]))),
          ],
          const SizedBox(height: 16),
          const Text('Enter Winning Number', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(_gameId == 'g_numbers' ? 'Enter 3 or 4 digits (0-9) — e.g. 527 or 1948 or 012' : 'Enter 4 digits (0-9) — e.g. 0123 or 8472 (Win 4)',
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 8),
          TextField(
            controller: _winCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: InputDecoration(
              labelText: 'Winning Number',
              hintText: _gameId == 'g_numbers' ? 'e.g. 123' : 'e.g. 0123',
              border: const OutlineInputBorder(),
              counterText: '',
              suffixIcon: _winCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _winCtrl.clear())) : null,
            ),
            onChanged: (_) => setState(() { _error=null; }),
          ),
          const SizedBox(height: 8),
          // AutoPay checkbox
          CheckboxListTile(
            value: _autoPay,
            onChanged: (v) => setState(() => _autoPay = v ?? false),
            title: const Text('Auto-pay winners (deduct from cash immediately)', style: TextStyle(fontSize: 12)),
            subtitle: const Text('If unchecked: tickets are marked as winning and prize saved without cash deduction — pay via Winning Tickets screen', style: TextStyle(fontSize: 10, color: Colors.black54)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          if (_error != null) Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [const Icon(Icons.error, color: Colors.red, size: 18), const SizedBox(width: 8), Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)))]))),
          if (_success != null) Card(color: Colors.green.shade50, child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [const Icon(Icons.check_circle, color: Colors.green, size: 18), const SizedBox(width: 8), Expanded(child: Text(_success!, style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600)))]))),
          if (_processing) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 46, child: ElevatedButton.icon(
            icon: _processing ? const SizedBox(width: 16, height:16, child: CircularProgressIndicator(strokeWidth:2, color: Colors.white)) : const Icon(Icons.save),
            label: Text(_processing ? 'Processing...' : 'Save Result & Evaluate Winners'),
            onPressed: _processing ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
          )),
          const SizedBox(height: 16),
          // NY Official — Full Payout Table
          Card(
            elevation: 1,
            child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('NY Lottery — Official Payout Table (Exact Clone)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepPurple)),
              const SizedBox(height: 4),
              const Text('Pick 3 = Numbers (3 digits 0-9) — Two draws daily', style: TextStyle(fontSize: 11, color: Colors.black54)),
              const Divider(),
              const Text('— Numbers Straight (exact order only — no permutation)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              _profitRow('Straight 3 digits', '500x (\$500/\$1)', 'Pick 123, winner 123 → win. Winner 321 → lose'),
              const SizedBox(height: 6),
              const Text('— Numbers Box (any order — permutation, payout by duplication)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              _profitRow('Box 3-Way (pair 112)', '160x (\$160/\$1)', 'Pick 112 → win with 112,121,211 (3 combos)'),
              _profitRow('Box 6-Way (distinct 123)', '80x (\$80/\$1)', 'Pick 123 → win with 6 combos: 123,132,213,231,312,321'),
              _profitRow('Box 111 (triple)', '0x', 'No Box — Straight only'),
              const SizedBox(height: 6),
              const Text('— Numbers Combo (like Box but pays Straight for all combos)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              _profitRow('Combo 3-Way', '(amount/3)x500', 'Pick 112 cost \$3 (\$1x3) → any order wins \$500'),
              _profitRow('Combo 6-Way', '(amount/6)x500', 'Pick 123 cost \$6 (\$1x6) → any order wins \$500'),
              const SizedBox(height: 6),
              const Text('— Numbers Straight/Box (half Straight + half Box for \$1)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              _profitRow('Str/Box 3-Way exact', '330x (\$330/\$1)', 'Exact: \$250 Straight(0.5x500)+\$80 Box(0.5x160) = \$330'),
              _profitRow('Str/Box 3-Way permutation', '80x', 'Perm only: \$80 Box half wager'),
              _profitRow('Str/Box 6-Way exact', '290x (\$290/\$1)', 'Exact: \$250+\$40 = \$290'),
              _profitRow('Str/Box 6-Way permutation', '40x', 'Perm: \$40'),
              const SizedBox(height: 6),
              const Text('— Win 4 (4 digits 0-9)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              _profitRow('Straight 4', '5000x (\$5000/\$1)', 'Exact match 1234==1234 only'),
              _profitRow('Box 4-Way (1112)', '1200x', '3 identical — 4 combos'),
              _profitRow('Box 6-Way (1122)', '800x', 'Two pairs — 6 combos'),
              _profitRow('Box 12-Way (1123)', '400x', 'One pair — 12 combos'),
              _profitRow('Box 24-Way (1234)', '200x', 'All distinct — 24 combos — any permutation wins'),
              _profitRow('Box 1111', '0x', '4 identical — no Box'),
              const SizedBox(height: 6),
              const Text('— Combo Win4: same as Box but (amount/combos)x5000', style: TextStyle(fontSize: 10, color: Colors.black54)),
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Golden Rules Summary:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('• Straight = never allows permutation — must be exact order', style: TextStyle(fontSize: 10)),
                Text('• Box / Combo = allows permutation — any order wins, payout varies by duplication (3-Way > 6-Way)', style: TextStyle(fontSize: 10)),
                Text('• If digit repeats (112): Box wins 3 combos, 123 wins 6 combos', style: TextStyle(fontSize: 10)),
                Text('• Combo costs more (3/6/12/24 x wager) but always pays full Straight', style: TextStyle(fontSize: 10)),
              ])),
              const SizedBox(height: 8),
              const Text('Accounting: Every sale → Cash +, Balance +. Every payout → Cash -, Balance -. Net (point profit) = total sales - total prizes paid. Shown in Balance screen and Draw report.', style: TextStyle(fontSize: 10, color: Colors.black54)),
            ])),
          ),
          const SizedBox(height: 16),
          if (_lastResult != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Last Processing Result + Accounting', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            Text('Total tickets in draw: ${_lastResult!['totalTickets']}', style: const TextStyle(fontSize: 12)),
            Text('Winners: ${_lastResult!['winningCount']} • Losers: ${_lastResult!['losingCount']}', style: const TextStyle(fontSize: 12)),
            Text('Total sales (this draw): ${fmtMoney(_lastResult!['totalSales'] ?? 0)}', style: const TextStyle(fontSize: 12)),
            Text('Total prizes reserved: ${fmtMoney(_lastResult!['totalPrize'])}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green)),
            Builder(builder: (_) {
              final sales = (_lastResult!['totalSales'] as num?)?.toDouble() ?? 0;
              final prize = (_lastResult!['totalPrize'] as num).toDouble();
              final diff = sales - prize;
              final isProfit = diff >= 0;
              return Text('Net (Sales - Prizes) = ${fmtMoney(diff)} ${isProfit ? '✓ Profit' : '✗ Loss'}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isProfit ? Colors.green.shade700 : Colors.red.shade700));
            }),
            const SizedBox(height: 4),
            Text(_autoPay ? 'Auto-paid — cash and balance deducted' : 'Not auto-paid — prizes reserved as winning, pay via Winning Tickets to deduct cash', style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ]))),
          const SizedBox(height: 12),
          if (_winningTickets.isNotEmpty) ...[
            const Text('Winning Tickets in This Draw', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            ..._winningTickets.map((t) => Card(child: ListTile(
              dense: true,
              title: Text('${t['id']} • ${t['numbers'].toString().replaceAll(',', ' ')} • ${t['betType']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              subtitle: Text('${t['gameName']} • ${fmtMoney(t['amount'])} → Prize ${fmtMoney(t['prizeAmount'] ?? 0)} • ${t['status']}', style: const TextStyle(fontSize: 11)),
              trailing: t['status']=='paid' ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.emoji_events, color: Colors.orange),
              onTap: () => Navigator.pushNamed(context, '/ticket_detail', arguments: t),
            ))),
          ] else if (draw != null && draw['winningNumbers'] != null) ...[
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Center(child: Text('No winners for this draw', style: TextStyle(color: Colors.black54))))),
          ],
        ]),
          ),
        ),
      ),
    );
  }

  Widget _profitRow(String label, String mult, String ex) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(6)), child: Text(mult, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepPurple))),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        Text(ex, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ])),
    ]));
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
