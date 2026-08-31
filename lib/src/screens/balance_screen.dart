import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../data/database.dart';

class BalanceScreen extends StatefulWidget {
  const BalanceScreen({super.key});
  @override
  State<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends State<BalanceScreen> {
  List<Map<String, dynamic>> _moves = [];
  double _balance = 0;
  double _cash = 0;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final app = context.read<AppState>();
    final b = await app.computeGeneralBalance(); // per-operator
    final c = await app.computeCashBalance(); // per-operator
    final opId = app.currentUser?['id'] as String?;
    final m = opId != null ? await db.getBalanceMovementsByOperator(opId) : await db.getBalanceMovements();
    // Show global for report compatibility: also load global if empty
    final movesToShow = m.isNotEmpty ? m : await db.getBalanceMovements();
    setState(() { _moves = movesToShow; _balance = b; _cash = c; _loading = false; });
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
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Balance summary cards
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
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

                  // How it works card
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
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

                  // Net calculation card
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
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

                  // Balance movements list
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
    );
  }
}