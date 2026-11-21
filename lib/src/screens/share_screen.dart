import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../utils/format.dart';

class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key});
  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  List<Map<String, dynamic>> _tickets = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final t = await db.getTickets();
    setState(() => _tickets = t.take(20).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'What can be shared',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      'Operator can share: Ticket (text/image/PDF), Receipt, Report, Result. Determined by ticket/report screens.',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    const Divider(),
                    const Text(
                      'Try sharing a ticket',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._tickets.map(
                      (t) => ListTile(
                        dense: true,
                        title: Text(
                          '${t['id']} • ${t['gameName']}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${t['numbers']} • ${fmtMoney(t['amount'])}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.share, size: 18),
                          onPressed: () {
                            Share.share(
                              'YeLottery Ticket\nID:${t['id']}\nSN:${t['serialNumber']}\nGame:${t['gameName']} ${t['betType']}\nNumbers:${t['numbers']}\nAmount:${fmtMoney(t['amount'])}\nDate:${fmtDate(t['createdAt'])}\nBarcode:${t['barcode']}\nStatus:${t['status']}',
                            );
                          },
                        ),
                      ),
                    ),
                    if (_tickets.isEmpty)
                      const Text(
                        'No tickets yet',
                        style: TextStyle(color: Colors.black54, fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),
            Card(
              color: Colors.cyan.shade50,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Share targets',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'Text — via share_plus (WhatsApp, etc.)\nImage — QR screenshot (manual)\nPDF — via Print → Share PDF\nLink — not applicable offline POS',
                      style: TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
