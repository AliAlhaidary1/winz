import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/draw_period_choice.dart';
import 'barcode_scanner_screen.dart';

class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});
  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _allTickets = [];
  String _filter = 'all';
  bool _loading = true;
  DateTime? _from;
  DateTime? _to;
  String _datePreset = 'today';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _from = today;
    _to = today;
    _datePreset = 'today';
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    List<Map<String, dynamic>> t;
    if (_filter == 'all')
      t = await db.getTickets();
    else
      t = await db.getTickets(status: _filter);
    _allTickets = t;
    _applyDateFilter();
  }

  void _applyDateFilter() {
    if (_from == null && _to == null) {
      if (mounted)
        setState(() {
          _tickets = List.from(_allTickets);
          _loading = false;
        });
      return;
    }
    final filtered = _allTickets.where((e) {
      final dt = DateTime.fromMillisecondsSinceEpoch(asInt(e['createdAt']));
      final d = DateTime(dt.year, dt.month, dt.day);
      if (_from != null &&
          d.isBefore(DateTime(_from!.year, _from!.month, _from!.day)))
        return false;
      if (_to != null && d.isAfter(DateTime(_to!.year, _to!.month, _to!.day)))
        return false;
      return true;
    }).toList();
    if (mounted)
      setState(() {
        _tickets = filtered;
        _loading = false;
      });
  }

  void _applyPreset(String p) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _datePreset = p;
      if (p == 'today') {
        _from = today;
        _to = today;
      } else if (p == 'yesterday') {
        final y = today.subtract(const Duration(days: 1));
        _from = y;
        _to = y;
      } else if (p == 'week') {
        _from = today.subtract(const Duration(days: 6));
        _to = today;
      } else if (p == 'all') {
        _from = null;
        _to = null;
      }
    });
    _applyDateFilter();
  }

  String _fmtShort(DateTime? d) => d == null
      ? '--'
      : '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  String _dispBet(String raw) {
    final n = raw
        .trim()
        .toLowerCase()
        .replaceAll('-', '/')
        .replaceAll('_', '/')
        .replaceAll(' ', '');
    if (n == 'all' ||
        n == 'all/box' ||
        n == 'all/straight' ||
        n == 'straightbox' ||
        n == 'str/box' ||
        n == 'strbox' ||
        n == 'st/box' ||
        n == 'stbox' ||
        (n.contains('straight') && n.contains('box')))
      return 'ST/BOX';
    return raw;
  }

  Color _color(String s) {
    switch (s) {
      case 'paid':
        return AppTheme.green;
      case 'winning':
        return Colors.orange;
      case 'losing':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return AppTheme.blue;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchAndOpen(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a ticket ID, serial, or barcode')),
      );
      return;
    }
    // Same cleaning path as the barcode scanner (first token that resolves).
    final cleaned = await cleanTicketCode(code, context.read<AppDatabase>());
    if (!mounted) return;
    final res = await context.read<AppState>().validateTicket(cleaned);
    if (res['found'] == false) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ticket not found: $code'),
            backgroundColor: Colors.red,
          ),
        );
      return;
    }
    final t = res['ticket'] as Map<String, dynamic>;
    if (mounted) Navigator.pushNamed(context, '/ticket_detail', arguments: t);
  }

  Future<void> _copyWithChoice(String ticketId) async {
    // Never silently re-sell a paid or cancelled ticket.
    final db0 = context.read<AppDatabase>();
    final src =
        await db0.getTicketById(ticketId) ??
        await db0.getTicketByBarcode(ticketId);
    final st = (src?['status'] as String? ?? '').toLowerCase();
    if (st == 'paid' || st == 'cancelled') {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot re-sell a ${st.toUpperCase()} ticket'),
            backgroundColor: Colors.red,
          ),
        );
      return;
    }
    final choice = await showDrawPeriodChoice(context);
    if (choice == null) return;
    try {
      final app = context.read<AppState>();
      final res = await app.replayTicketToCartWithChoice(ticketId, choice);
      if (!mounted) return;
      final count = asInt(res['added']);
      final skipped = (res['skipped'] as List).cast<String>();
      final trimmed = (res['trimmed'] as List).cast<String>();
      final label = choice == 'BOTH'
          ? 'Both (×2)'
          : choice == 'MIDDAY'
          ? 'Midday'
          : 'Evening';
      String detail = '';
      if (skipped.isNotEmpty)
        detail += '\nDeleted (sold out): ${skipped.length}';
      if (trimmed.isNotEmpty)
        detail += '\nTrimmed to remaining: ${trimmed.length}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied $count play(s) → $label — tap SALE$detail'),
          backgroundColor: AppTheme.green,
          duration: Duration(seconds: detail.isNotEmpty ? 5 : 3),
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
                    'Added $count play(s) → $label',
                    style: const TextStyle(fontSize: 11),
                  ),
                  if (skipped.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '⚠️ Deleted (reached limit):',
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
                      '✂️ Trimmed:',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Tickets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, size: 20, color: Colors.white),
            tooltip: 'Search by Ticket Number',
            onPressed: () async {
              final ctrl = TextEditingController();
              final code = await showDialog<String>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text(
                    'Search by Ticket Number',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Enter ID or Serial — e.g. 000001',
                        style: TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: ctrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Ticket ID / Serial',
                          isDense: true,
                        ),
                        onSubmitted: (v) => Navigator.pop(c, v),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(c, ctrl.text.trim()),
                      child: const Text('Search'),
                    ),
                  ],
                ),
              );
              if (code != null && code.trim().isNotEmpty) {
                final db = context.read<AppDatabase>();
                final cleaned = await cleanTicketCode(code, db);
                final t = await db.getTicketByBarcode(cleaned);
                if (t == null) {
                  if (context.mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Ticket not found: $code'),
                        backgroundColor: Colors.red,
                      ),
                    );
                } else {
                  await _copyWithChoice(t['id'] as String);
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
            tooltip: 'Scan barcode',
            onPressed: () async {
              final code = await Navigator.push<String>(
                context,
                MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
              );
              if (code != null && code.isNotEmpty) {
                final db = context.read<AppDatabase>();
                final t = await db.getTicketByBarcode(code);
                if (t != null && context.mounted)
                  Navigator.pushNamed(context, '/ticket_detail', arguments: t);
                else if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ticket not found for $code'),
                      backgroundColor: Colors.red,
                    ),
                  );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: Column(
            children: [
              Container(
                color: Colors.white,
                padding: EdgeInsets.fromLTRB(
                  Responsive.horizontalPadding(context),
                  8,
                  Responsive.horizontalPadding(context),
                  8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search ticket ID / serial / barcode...',
                          hintStyle: const TextStyle(fontSize: 11),
                          isDense: true,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.qr_code_scanner,
                                  size: 18,
                                  color: AppTheme.green,
                                ),
                                tooltip: 'Scan',
                                onPressed: () async {
                                  final code = await Navigator.push<String>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const BarcodeScannerScreen(),
                                    ),
                                  );
                                  if (code != null && code.isNotEmpty) {
                                    _searchCtrl.text = code;
                                    _searchAndOpen(code);
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () => _searchCtrl.clear(),
                              ),
                            ],
                          ),
                        ),
                        onSubmitted: _searchAndOpen,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _searchAndOpen(_searchCtrl.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                      child: const Text(
                        'Search',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                color: Colors.white,
                padding: EdgeInsets.fromLTRB(
                  Responsive.horizontalPadding(context),
                  10,
                  Responsive.horizontalPadding(context),
                  10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Filter',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_tickets.length} tickets',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final f in [
                            'all',
                            'active',
                            'winning',
                            'paid',
                            'losing',
                            'cancelled',
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(
                                  f.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _filter == f
                                        ? Colors.white
                                        : AppTheme.textMuted,
                                  ),
                                ),
                                selected: _filter == f,
                                selectedColor: _filter == f ? _color(f) : null,
                                backgroundColor: Colors.white,
                                side: BorderSide(
                                  color: _filter == f
                                      ? _color(f)
                                      : AppTheme.cardBorder,
                                ),
                                onSelected: (_) => setState(() {
                                  _filter = f;
                                  _loading = true;
                                  _load();
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          'Date',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_allTickets.length} total • ${_tickets.length} shown',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: Text(
                              'All',
                              style: TextStyle(
                                color: _datePreset == 'all'
                                    ? Colors.white
                                    : Colors.black87,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            selected: _datePreset == 'all',
                            selectedColor: AppTheme.green,
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: _datePreset == 'all'
                                  ? AppTheme.green
                                  : Colors.grey.shade300,
                            ),
                            onSelected: (_) => _applyPreset('all'),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: Text(
                              'Today',
                              style: TextStyle(
                                color: _datePreset == 'today'
                                    ? Colors.white
                                    : Colors.black87,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            selected: _datePreset == 'today',
                            selectedColor: AppTheme.green,
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: _datePreset == 'today'
                                  ? AppTheme.green
                                  : Colors.grey.shade300,
                            ),
                            onSelected: (_) => _applyPreset('today'),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: Text(
                              'Yesterday',
                              style: TextStyle(
                                color: _datePreset == 'yesterday'
                                    ? Colors.white
                                    : Colors.black87,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            selected: _datePreset == 'yesterday',
                            selectedColor: AppTheme.green,
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: _datePreset == 'yesterday'
                                  ? AppTheme.green
                                  : Colors.grey.shade300,
                            ),
                            onSelected: (_) => _applyPreset('yesterday'),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: Text(
                              'Week',
                              style: TextStyle(
                                color: _datePreset == 'week'
                                    ? Colors.white
                                    : Colors.black87,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            selected: _datePreset == 'week',
                            selectedColor: AppTheme.green,
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: _datePreset == 'week'
                                  ? AppTheme.green
                                  : Colors.grey.shade300,
                            ),
                            onSelected: (_) => _applyPreset('week'),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: Text(
                              'Custom',
                              style: TextStyle(
                                color: _datePreset == 'custom'
                                    ? Colors.white
                                    : Colors.black87,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            selected: _datePreset == 'custom',
                            selectedColor: AppTheme.green,
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: _datePreset == 'custom'
                                  ? AppTheme.green
                                  : Colors.grey.shade300,
                            ),
                            onSelected: (_) =>
                                setState(() => _datePreset = 'custom'),
                          ),
                        ],
                      ),
                    ),
                    if (_datePreset == 'custom') ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_today, size: 14),
                              label: Text(
                                'From: ${_fmtShort(_from)}',
                                style: const TextStyle(fontSize: 10),
                              ),
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  firstDate: DateTime(2024),
                                  lastDate: DateTime(2030),
                                  initialDate: _from ?? DateTime.now(),
                                );
                                if (d != null) {
                                  setState(() => _from = d);
                                  _applyDateFilter();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_today, size: 14),
                              label: Text(
                                'To: ${_fmtShort(_to)}',
                                style: const TextStyle(fontSize: 10),
                              ),
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  firstDate: DateTime(2024),
                                  lastDate: DateTime(2030),
                                  initialDate: _to ?? DateTime.now(),
                                );
                                if (d != null) {
                                  setState(() => _to = d);
                                  _applyDateFilter();
                                }
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              setState(() {
                                _from = null;
                                _to = null;
                                _datePreset = 'all';
                              });
                              _applyDateFilter();
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.green),
                      )
                    : _tickets.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.cardBorder,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.inbox_outlined,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No tickets found',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const Text(
                                'Try another filter or create a sale',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.all(
                          Responsive.horizontalPadding(context),
                        ),
                        itemCount: _tickets.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (c, i) {
                          final t = _tickets[i];
                          final col = _color(t['status']);
                          final customerRaw = t['customerName'];
                          final customerName =
                              (customerRaw is String &&
                                  customerRaw.trim().isNotEmpty)
                              ? customerRaw.trim()
                              : 'Cash Customer';
                          return Container(
                            decoration: AppTheme.cardDecoration(
                              borderColor: col.withValues(alpha: 0.12),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/ticket_detail',
                                arguments: t,
                              ),
                              onLongPress: () =>
                                  _copyWithChoice(t['id'] as String),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: col,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${t['serialNumber'] ?? t['id']}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: col.withValues(
                                                    alpha: 0.08,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  t['status'],
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: col,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${t['gameName']} • ${_dispBet(t['betType'])}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.textMuted,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Customer: $customerName',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: AppTheme.textMuted,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              // Long number lists must shrink
                                              // instead of pushing the amount
                                              // off narrow phone screens.
                                              Flexible(
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.bg,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    (t['numbers'] as String)
                                                        .replaceAll(',', '  '),
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      letterSpacing: 1,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              if ((t['numbers'] as String)
                                                  .contains(';'))
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.greenLight,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '${(t['numbers'] as String).split(';').length} plays',
                                                    style: const TextStyle(
                                                      fontSize: 9,
                                                      color: AppTheme.green,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              const Spacer(),
                                              Flexible(
                                                child: Text(
                                                  fmtMoney(
                                                    t['total'] ?? t['amount'],
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                  textAlign: TextAlign.right,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'ID ${t['id']} • ${fmtDate(t['createdAt'])} • ${t['operatorName']}',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: AppTheme.textMuted,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              InkWell(
                                                onTap: () => _copyWithChoice(
                                                  t['id'] as String,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.greenLight,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.copy,
                                                        size: 10,
                                                        color: AppTheme.green,
                                                      ),
                                                      SizedBox(width: 3),
                                                      Text(
                                                        'Copy',
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          color: AppTheme.green,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Sale'),
        backgroundColor: AppTheme.green,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.pushNamed(context, '/numbers'),
      ),
    );
  }
}
