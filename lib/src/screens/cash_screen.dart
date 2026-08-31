import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../data/database.dart';

class CashScreen extends StatefulWidget {
  const CashScreen({super.key});
  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  List<Map<String, dynamic>> _ledger = [];
  double _cash = 0;
  Map<String, dynamic>? _session;
  bool _loading = true;
  final _openCtrl = TextEditingController();
  final _adjCtrl = TextEditingController();
  String _adjType = 'deposit';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final app = context.read<AppState>();
    if (app.isSessionExpired && app.isLoggedIn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired — please login again')));
        app.logout();
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        return;
      }
    }
    final opId = app.currentUser?['id'] as String?;
    final l = opId != null ? await db.getCashLedgerByOperator(opId) : await db.getCashLedger();
    final c = await app.computeCashBalance();
    final s = app.currentUser != null ? await db.getOpenCashSession(app.currentUser!['id']) : null;
    setState(() { _ledger = l; _cash = c; _session = s; _loading = false; });
  }

  Future<void> _openSession() async {
    final amt = double.tryParse(_openCtrl.text);
    if (amt == null) return;
    await context.read<AppState>().openCashSession(amt);
    _openCtrl.clear();
    await _load();
  }

  Future<void> _closeSession() async {
    await context.read<AppState>().closeCashSession();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session closed')));
    await _load();
  }

  Future<void> _adjust() async {
    final amt = double.tryParse(_adjCtrl.text);
    if (amt == null || amt <= 0) return;
    final db = context.read<AppDatabase>();
    final app = context.read<AppState>();
    final dir = (_adjType == 'deposit' || _adjType == 'adjustment_in') ? 'in' : 'out';
    await db.insertCashLedger({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'type': _adjType,
      'amount': amt,
      'direction': dir,
      'description': _adjType,
      'operatorId': app.currentUser!['id'],
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'ticketId': null,
    });
    await db.insertBalanceMovement({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'type': _adjType,
      'amount': amt,
      'direction': dir == 'in' ? 'credit' : 'debit',
      'description': _adjType,
      'operatorId': app.currentUser!['id'],
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'ticketId': null,
    });
    _adjCtrl.clear();
    await _load();
  }

  String _fmt(double? v) => v != null ? v.toStringAsFixed(2) : '0.00';

  String _fmtDate(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${d.month}/${d.day}/${d.year}';
  }

  String _fmtDir(String dir) {
    if (dir == 'in') return '+${_fmt(_cash)}';
    return '-${_fmt(_cash)}';
  }

  Color _fmtDirColor(String dir) {
    if (dir == 'in') return Colors.green;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: color.surface,
        elevation: 0,
        title: const Text('Cash'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Cash summary card
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(children: [
                        const Icon(Icons.payments, color: Colors.green, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                  'Cash on Hand',
                                  style:
                                      TextStyle(color: Colors.black45, fontSize: 12)),
                              Text(
                                  _fmt(_cash),
                                  style:
                                      TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (_session != null) ...[
                          Text(
                              'Session: Opening ${_fmt(_session!['openingAmount'])}',
                              style: TextStyle(color: Colors.black45, fontSize: 11)),
                          const SizedBox(height: 4),
                          ElevatedButton(
                              onPressed: _closeSession,
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                              child: const Text('Close Session')),
                        ] else ...[
                          ElevatedButton(
                              onPressed: _openSession,
                              child: const Text('Open Session')),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Transactions ledger
                  const Text(
                      'Transactions',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                  const SizedBox(height: 8),
                  ..._ledger.map((e) => Card(
                    child: ListTile(
                      title: Text(
                          '${e['type']} • ${_fmt(e['amount'])} • ${e['direction']}'),
                      subtitle:
                          Text('${e['description'] ?? ''} • ${_fmtDate(e['createdAt'])}'),
                      trailing: Text(
                          _fmtDir(e['direction']),
                          style:
                              TextStyle(fontWeight: FontWeight.bold, color: _fmtDirColor(e['direction']))),
                    ),
                  )),
                  if (_ledger.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                              'No transactions yet',
                              style: TextStyle(color: Colors.black45))),
                  const SizedBox(height: 20),

                  // Adjustment form card
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                              'Deposit / Withdrawal / Adjustment',
                              style:
                                  TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(child: DropdownButton<String>(
                              value: _adjType,
                              items: const [
                                DropdownMenuItem(value: 'deposit', child: Text('Deposit')),
                                DropdownMenuItem(value: 'withdrawal', child: Text('Withdrawal')),
                                DropdownMenuItem(value: 'adjustment_in', child: Text('Adj +')),
                                DropdownMenuItem(value: 'adjustment_out', child: Text('Adj -')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _adjType = v!)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                                child: TextField(
                                    controller: _adjCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration:
                                        const InputDecoration(labelText: 'Amount'))),
                            const SizedBox(width: 8),
                            ElevatedButton(onPressed: _adjust, child: const Text('Add')),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Balance movements
                  const Text(
                      'Balance Movements',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                  const SizedBox(height: 8),
                  ..._ledger.map((e) => Card(
                    child: ListTile(
                      title: Text(
                          '${e['type']} • ${_fmt(e['amount'])}'),
                      subtitle:
                          Text('${e['description'] ?? ''} • ${_fmtDate(e['createdAt'])}'),
                    ),
                  )),
                  if (_ledger.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                              'No movements yet — create a sale to see activity',
                              style: TextStyle(color: Colors.black45))),
                ],
              ),
            ),
    );
  }
}