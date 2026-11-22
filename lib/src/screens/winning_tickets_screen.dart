import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';
import '../widgets/draw_period_choice.dart';
import 'barcode_scanner_screen.dart';

class WinningTicketsScreen extends StatefulWidget {
  const WinningTicketsScreen({super.key});
  @override
  State<WinningTicketsScreen> createState() => _WinningTicketsScreenState();
}

class _WinningTicketsScreenState extends State<WinningTicketsScreen> {
  final _codeCtrl = TextEditingController();
  Map<String, dynamic>? _result;
  bool _loading = false;
  List<Map<String, dynamic>> _winningList = [];
  bool _loadingList = true;

  @override
  void initState() {
    super.initState();
    _loadWinningList();
  }

  Future<void> _loadWinningList() async {
    setState(() => _loadingList = true);
    final db = context.read<AppDatabase>();
    final all = await db.getTickets();
    // NY: Winner  winning + paid (after draw)
    final winning =
        all
            .where((t) => t['status'] == 'winning' || t['status'] == 'paid')
            .toList()
          ..sort(
            (a, b) => (asInt(b['createdAt'])).compareTo(asInt(a['createdAt'])),
          );
    if (mounted)
      setState(() {
        _winningList = winning;
        _loadingList = false;
      });
  }

  Future<void> _validate() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter ticket number / barcode')),
      );
      return;
    }
    setState(() => _loading = true);
    final res = await context.read<AppState>().validateTicket(code);
    setState(() => _loading = false);
    if (res['found'] == false) {
      setState(
        () => _result = {
          'error':
              'Ticket not found — check number or try the winners list below',
        },
      );
    } else {
      setState(() => _result = res);
      _loadWinningList();
    }
  }

  Future<void> _copyWithChoice() async {
    if (_result == null || _result!['found'] != true) return;
    final ticket = _result!['ticket'] as Map<String, dynamic>;
    final choice = await showDrawPeriodChoice(context);
    if (choice == null) return;
    try {
      final app = context.read<AppState>();
      final res = await app.replayTicketToCartWithChoice(
        ticket['id'] as String,
        choice,
      );
      if (!mounted) return;
      final count = asInt(res['added']);
      final skipped = (res['skipped'] as List).cast<String>();
      final trimmed = (res['trimmed'] as List).cast<String>();
      final label = choice == 'BOTH'
          ? 'Both (×2)'
          : choice == 'MIDDAY'
          ? 'Midday'
          : 'Evening';
      String extra = '';
      if (skipped.isNotEmpty) extra += ' — ${skipped.length} deleted';
      if (trimmed.isNotEmpty) extra += ' — ${trimmed.length} trimmed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Copied $count play(s) → $label — go to Numbers to sell$extra',
          ),
          backgroundColor: const Color(0xFF0B8A3E),
          duration: Duration(seconds: extra.isNotEmpty ? 5 : 3),
        ),
      );
      if (skipped.isNotEmpty || trimmed.isNotEmpty) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text(
              'Copied with adjustments',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Added $count → $label',
                    style: const TextStyle(fontSize: 11),
                  ),
                  if (skipped.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '⚠️ Deleted (sold out):',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    ...skipped.map(
                      (s) => Text('• $s', style: const TextStyle(fontSize: 10)),
                    ),
                  ],
                  if (trimmed.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '✂️ Trimmed to remaining:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    ...trimmed.map(
                      (s) => Text('• $s', style: const TextStyle(fontSize: 10)),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('OK'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(c);
                  Navigator.pushNamed(context, '/numbers');
                },
                child: const Text('Go SALE'),
              ),
            ],
          ),
        );
      } else {
        Navigator.pushNamed(context, '/numbers');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _pay() async {
    if (_result == null || _result!['isWinning'] != true) return;
    final ticket = _result!['ticket'] as Map<String, dynamic>;
    // Re-validate immediately before paying — the last Check result may be stale.
    setState(() => _loading = true);
    Map<String, dynamic> fresh;
    try {
      fresh = await context.read<AppState>().validateTicket(
        (ticket['barcode'] ?? ticket['id']).toString(),
      );
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      return;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (fresh['found'] != true || fresh['isWinning'] != true) {
      setState(() => _result = fresh);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ticket is no longer a validated winner — payment blocked',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final freshTicket = fresh['ticket'] as Map<String, dynamic>;
    if (fresh['alreadyPaid'] == true || freshTicket['status'] == 'paid') {
      setState(() => _result = fresh);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already paid — duplicate payout blocked'),
        ),
      );
      return;
    }
    final prize = asDouble(fresh['prize']);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(
          'Confirm prize payment',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Pay ${fmtMoney(prize)} in cash to ticket ${freshTicket['id']}? This will deduct the amount from the cash drawer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0B8A3E),
            ),
            onPressed: () => Navigator.pop(c, true),
            child: Text('Pay ${fmtMoney(prize)}'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await context.read<AppState>().payWinningTicket(
      freshTicket['id'],
      prize,
    );
    if (!mounted) return;
    if (ok) {
      fresh['alreadyPaid'] = true;
      setState(() => _result = fresh);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Paid ${fmtMoney(prize)} for ticket ${freshTicket['id']} — cash deducted',
          ),
          backgroundColor: const Color(0xFF0B8A3E),
        ),
      );
      _loadWinningList();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment failed — may already be paid')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF0B8A3E);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        title: const Text('Winning Tickets'),
        backgroundColor: green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadWinningList,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner,
                            color: green,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Scan Ticket by Barcode',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.qr_code_scanner, size: 16),
                          label: const Text(
                            'Scan',
                            style: TextStyle(fontSize: 11),
                          ),
                          onPressed: () async {
                            final code = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const BarcodeScannerScreen(),
                              ),
                            );
                            if (code != null && code.isNotEmpty) {
                              _codeCtrl.text = code;
                              _validate();
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _codeCtrl,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'Ticket Number / Serial / Barcode',
                        isDense: true,
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.qr_code_scanner,
                                color: green,
                              ),
                              tooltip: 'Scan barcode',
                              onPressed: () async {
                                final code = await Navigator.push<String>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const BarcodeScannerScreen(),
                                  ),
                                );
                                if (code != null) {
                                  _codeCtrl.text = code;
                                  _validate();
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.search, color: green),
                              onPressed: _validate,
                            ),
                          ],
                        ),
                      ),
                      onSubmitted: (_) => _validate(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: green,
                              foregroundColor: Colors.white,
                            ),
                            icon: _loading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.search, size: 16),
                            label: Text(
                              _loading ? 'Checking...' : 'Check',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: _loading ? null : _validate,
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan'),
                          onPressed: () async {
                            final c = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const BarcodeScannerScreen(),
                              ),
                            );
                            if (c != null) {
                              _codeCtrl.text = c;
                              _validate();
                            }
                          },
                        ),
                      ],
                    ),
                    if (_result != null) ...[
                      const SizedBox(height: 10),
                      if (_result!.containsKey('error'))
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error,
                                color: Colors.red,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _result!['error'],
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_result!['found'] == true)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _result!['isWinning'] == true
                                ? const Color(0xFFE6F4EA)
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _result!['isWinning'] == true
                                  ? green
                                  : Colors.red,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _result!['isWinning'] == true
                                        ? Icons.emoji_events
                                        : Icons.cancel,
                                    color: _result!['isWinning'] == true
                                        ? green
                                        : Colors.red,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _result!['isWinning'] == true
                                        ? 'Winner ✓'
                                        : 'Loser',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: _result!['isWinning'] == true
                                          ? green
                                          : Colors.red,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_result!['alreadyPaid'] == true)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'Paid',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  if (_result!['pending'] == true)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'Pending',
                                        style: TextStyle(fontSize: 9),
                                      ),
                                    ),
                                ],
                              ),
                              const Divider(height: 12),
                              Builder(
                                builder: (_) {
                                  final t =
                                      _result!['ticket']
                                          as Map<String, dynamic>;
                                  final lines =
                                      _result!['lines']
                                          as List<Map<String, dynamic>>?;
                                  final lineDetails =
                                      _result!['lineDetails'] as List?;
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Ticket: ${t['id']} • ${t['serialNumber']}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (lines != null &&
                                          lines.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        for (int i = 0; i < lines.length; i++)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 2,
                                            ),
                                            child: Row(
                                              children: [
                                                Text(
                                                  '${i + 1}.',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    (lines[i]['numbers']
                                                            as String)
                                                        .replaceAll(',', ' '),
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 1,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      border: Border.all(
                                                        color: Colors
                                                            .grey
                                                            .shade300,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      lines[i]['betType'],
                                                      style: const TextStyle(
                                                        fontSize: 9,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                                const Spacer(),
                                                Flexible(
                                                  child: Text(
                                                    fmtMoney(
                                                      lines[i]['amount'],
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    textAlign: TextAlign.right,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (lineDetails != null) ...[
                                                  const SizedBox(width: 6),
                                                  Icon(
                                                    (lineDetails[i]['isWinning'] ==
                                                            true)
                                                        ? Icons.check_circle
                                                        : (lineDetails[i]['pending'] ==
                                                                  true
                                                              ? Icons
                                                                    .hourglass_empty
                                                              : Icons.cancel),
                                                    size: 12,
                                                    color:
                                                        (lineDetails[i]['isWinning'] ==
                                                            true)
                                                        ? green
                                                        : (lineDetails[i]['pending'] ==
                                                                  true
                                                              ? Colors.orange
                                                              : Colors.red),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                      ] else
                                        Text(
                                          'Game: ${t['gameName']} • ${t['betType']} • ${t['numbers'].toString().replaceAll(',', ' ')}',
                                          style: const TextStyle(fontSize: 11),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      Text(
                                        'Total: ${fmtMoney(t['total'] ?? t['amount'])} • Date: ${fmtDate(t['createdAt'])}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      Text(
                                        'Status: ${t['status']}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      if (_result!['isWinning'] == true)
                                        Text(
                                          'Total Prize: ${fmtMoney(_result!['prize'])}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: green,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      if (_result!['pending'] == true)
                                        const Text(
                                          'Draw not yet completed — set winning number in Admin Draw first',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.orange,
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              if (_result!['isWinning'] == true &&
                                  _result!['alreadyPaid'] != true &&
                                  _result!['pending'] != true)
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.payments, size: 16),
                                    label: Text(
                                      'Pay Prize ${fmtMoney(_result!['prize'])}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: green,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: _pay,
                                  ),
                                ),
                              if (_result!['isWinning'] == true &&
                                  _result!['alreadyPaid'] == true)
                                const Text(
                                  'Duplicate payout blocked',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.red,
                                  ),
                                ),
                              if (_result!['found'] == true) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.copy, size: 14),
                                    label: const Text(
                                      'Copy ticket to play again — choose period',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    onPressed: _copyWithChoice,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'You can copy by ticket number (ID), serial, or barcode — you will choose: Midday / Evening / Both',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.black45,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.emoji_events, color: green, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Winners List (${_winningList.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                if (_winningList.isNotEmpty)
                  Text(
                    'Tap to pay',
                    style: TextStyle(fontSize: 10, color: Colors.black45),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _loadingList
                ? const Center(child: CircularProgressIndicator(color: green))
                : _winningList.isEmpty
                ? Center(
                    child: Card(
                      margin: const EdgeInsets.all(24),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inbox,
                              color: Colors.grey.shade400,
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'No winners yet',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Set the winning number in Admin Draw → winners appear here in green',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: green,
                              ),
                              icon: const Icon(
                                Icons.admin_panel_settings,
                                size: 16,
                              ),
                              label: const Text(
                                'Set Winning Number',
                                style: TextStyle(fontSize: 11),
                              ),
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/admin/draw'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: _winningList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (c, i) {
                      final t = _winningList[i];
                      final isPaid = t['status'] == 'paid';
                      return Card(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isPaid
                                ? Colors.grey.shade300
                                : green.withOpacity(0.3),
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: isPaid
                                ? Colors.grey.shade100
                                : green.withOpacity(0.12),
                            child: Icon(
                              isPaid ? Icons.check_circle : Icons.emoji_events,
                              color: isPaid ? Colors.grey : green,
                              size: 16,
                            ),
                          ),
                          title: Text(
                            '${t['id']} • ${t['numbers'].toString().replaceAll(',', ' ')}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            '${t['gameName']} • ${t['betType']} • ${fmtMoney(t['amount'])} → ${fmtMoney(t['prizeAmount'] ?? 0)} • ${fmtDate(t['createdAt'])}',
                            style: const TextStyle(fontSize: 10),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isPaid
                                      ? Colors.grey.shade200
                                      : green.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  t['status'],
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: isPaid
                                        ? Colors.grey.shade700
                                        : green,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                fmtMoney(t['prizeAmount'] ?? 0),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: green,
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            _codeCtrl.text = t['id'] as String;
                            _validate();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
