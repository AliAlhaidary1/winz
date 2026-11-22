import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../providers/app_state.dart';
import '../../utils/responsive.dart';
import '../../utils/format.dart';
import '../../utils/timezone.dart';

class WinnerSettingsScreen extends StatefulWidget {
  const WinnerSettingsScreen({super.key});
  @override
  State<WinnerSettingsScreen> createState() => _WinnerSettingsScreenState();
}

class _WinnerSettingsScreenState extends State<WinnerSettingsScreen> {
  List<Map<String, dynamic>> _periods = [];
  bool _winningRestricted = true;
  String _tz = MarketTimezone.defaultTimezone;
  bool _loading = true;
  DateTime _selectedDate = DateTime.now();
  final Map<String, TextEditingController> _ctrl3 = {};
  final Map<String, TextEditingController> _ctrl4 = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = context.read<AppDatabase>();
    await db.seedDrawPeriods();
    await db.refreshPeriodStatuses();
    final all = await db.getAllPeriods();
    // Get winning restriction
    final cfg = await db.getAppConfig();
    final wr = cfg
        .where((e) => e['key'] == 'winning_time_restricted')
        .firstOrNull;
    final restricted = wr == null ? true : wr['value'] == '1';
    final tzEntry = cfg.where((e) => e['key'] == 'draw_timezone').firstOrNull;
    final tz = tzEntry == null
        ? MarketTimezone.defaultTimezone
        : tzEntry['value'] as String;
    // Filter for selected date ± 7 days
    final periods =
        all.where((p) {
          final d = DateTime.parse(p['drawDate'] as String);
          final sel = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
          );
          final diff = d.difference(sel).inDays;
          return diff >= -1 && diff <= 7;
        }).toList()..sort(
          (a, b) =>
              (asInt(a['salesCloseTime']))
                  .compareTo(asInt(b['salesCloseTime'])),
        );
    if (!mounted) return;
    setState(() {
      _periods = periods;
      _winningRestricted = restricted;
      _tz = tz;
      _loading = false;
    });
    // init controllers
    for (final p in periods) {
      final id = p['id'] as String;
      if (!_ctrl3.containsKey(id)) {
        _ctrl3[id] = TextEditingController(
          text: (p['result3'] as String?) ?? '',
        );
        _ctrl4[id] = TextEditingController(
          text: (p['result4'] as String?) ?? '',
        );
      } else {
        // update if changed externally
        final v3 = (p['result3'] as String?) ?? '';
        final v4 = (p['result4'] as String?) ?? '';
        if (_ctrl3[id]!.text != v3) _ctrl3[id]!.text = v3;
        if (_ctrl4[id]!.text != v4) _ctrl4[id]!.text = v4;
      }
    }
  }

  String _fmt12FromMs(int ms) => MarketTimezone.format12FromEpoch(ms, _tz);

  bool _canEnter(Map<String, dynamic> p) {
    if (!_winningRestricted) return true;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sc = asInt(p['salesCloseTime']);
    final dr = asInt(p['drawTime']);
    const window = 2 * 3600 * 1000;
    return now >= sc && now <= dr + window;
  }

  String _windowLabel(Map<String, dynamic> p) {
    final sc = _fmt12FromMs(asInt(p['salesCloseTime']));
    final dr = _fmt12FromMs(asInt(p['drawTime']));
    // +2h
    final dr2Str = _fmt12FromMs((asInt(p['drawTime'])) + 2 * 3600 * 1000);
    return '$sc — $dr (window till $dr2Str)';
  }

  Future<void> _save3(String periodId) async {
    final raw = _ctrl3[periodId]!.text
        .trim()
        .replaceAll(',', '')
        .replaceAll(' ', '');
    if (!RegExp(r'^[0-9]{3}$').hasMatch(raw)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('3-digit winner must be 3 digits (0-9)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final can = _canEnter(_periods.firstWhere((e) => e['id'] == periodId));
    if (_winningRestricted && !can) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Not allowed now — only during the window ${_windowLabel(_periods.firstWhere((e) => e['id'] == periodId))}',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    try {
      final existing =
          (_periods.firstWhere((e) => e['id'] == periodId)['result3']
              as String?);
      final isCorrection = existing != null && existing.isNotEmpty;
      // Single call handles DB publish + prize calc (12h aware)
      final app = context.read<AppState>();
      final res = await app.processPeriodResult(
        periodId: periodId,
        winningNumbers: raw.split(''),
        isCorrection: isCorrection,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '3-digit winner $raw saved — Winners: ${res['winningCount']} • Prizes: ${fmtMoney(res['totalPrize'])}',
          ),
          backgroundColor: const Color(0xFF0B8A3E),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _save4(String periodId) async {
    final raw = _ctrl4[periodId]!.text
        .trim()
        .replaceAll(',', '')
        .replaceAll(' ', '');
    if (!RegExp(r'^[0-9]{4}$').hasMatch(raw)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('4-digit winner must be 4 digits (0-9)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final can = _canEnter(_periods.firstWhere((e) => e['id'] == periodId));
    if (_winningRestricted && !can) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Not allowed now — only during the window ${_windowLabel(_periods.firstWhere((e) => e['id'] == periodId))}',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    try {
      final existing =
          (_periods.firstWhere((e) => e['id'] == periodId)['result4']
              as String?);
      final isCorrection = existing != null && existing.isNotEmpty;
      final app = context.read<AppState>();
      final res = await app.processPeriodResult(
        periodId: periodId,
        winningNumbers: raw.split(''),
        isCorrection: isCorrection,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '4-digit winner $raw saved — Winners: ${res['winningCount']} • Prizes: ${fmtMoney(res['totalPrize'])}',
          ),
          backgroundColor: const Color(0xFF0B8A3E),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl3.values) c.dispose();
    for (final c in _ctrl4.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF0B8A3E);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        backgroundColor: green,
        foregroundColor: Colors.white,
        title: const Text(
          'Winner Settings',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: green))
          : SingleChildScrollView(
              padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: Responsive.contentMaxWidth(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header explainer
                      Card(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: green.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: green.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.emoji_events,
                                      color: green,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'The only place to enter winners',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Here you enter the 3-digit and 4-digit winners for each period (Morning / Evening). The system follows the time settings in Draw Schedule and displays the clock in 12-hour AM/PM format.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _winningRestricted
                                      ? Colors.orange.shade50
                                      : Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _winningRestricted
                                          ? Icons.timer
                                          : Icons.check_circle,
                                      size: 16,
                                      color: _winningRestricted
                                          ? Colors.orange
                                          : green,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _winningRestricted
                                            ? 'Time-restricted: entry is only allowed during [Sales Close — Draw + 2 hours]'
                                            : 'Unrestricted: entry is allowed at any time, and the period closes immediately after entry',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _winningRestricted
                                              ? Colors.orange.shade700
                                              : green,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Change the time via: Settings → Draw Schedule → Sales Close / Draw Time (12h). Any change is applied automatically to future periods.',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Date selector
                      Card(
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today,
                                    size: 16,
                                    color: Colors.deepPurple,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${_selectedDate.year}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.day.toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.arrow_back_ios,
                                      size: 12,
                                    ),
                                    label: const Text(
                                      'Yesterday',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => _selectedDate = _selectedDate
                                            .subtract(const Duration(days: 1)),
                                      );
                                      _load();
                                    },
                                  ),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.today, size: 12),
                                    label: const Text(
                                      'Today',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => _selectedDate = DateTime.now(),
                                      );
                                      _load();
                                    },
                                  ),
                                  OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.arrow_forward_ios,
                                      size: 12,
                                    ),
                                    label: const Text(
                                      'Tomorrow',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => _selectedDate = _selectedDate.add(
                                          const Duration(days: 1),
                                        ),
                                      );
                                      _load();
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._periods.map((p) {
                        final id = p['id'] as String;
                        final type = p['drawType'] as String;
                        final sc12 = _fmt12FromMs(asInt(p['salesCloseTime']));
                        final dr12 = _fmt12FromMs(asInt(p['drawTime']));
                        final status = p['status'] as String;
                        final can = _canEnter(p);
                        final r3 = p['result3'] as String?;
                        final r4 = p['result4'] as String?;
                        final statusColor = status == 'OPEN'
                            ? green
                            : status == 'RESULT_PENDING'
                            ? Colors.orange
                            : status == 'COMPLETED' ||
                                  status == 'RESULT_PUBLISHED'
                            ? Colors.blue
                            : Colors.grey;
                        return Card(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: statusColor.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: type == 'MIDDAY'
                                          ? Colors.orange.withValues(
                                              alpha: 0.15,
                                            )
                                          : Colors.indigo.withValues(
                                              alpha: 0.15,
                                            ),
                                      child: Icon(
                                        type == 'MIDDAY'
                                            ? Icons.wb_sunny
                                            : Icons.nights_stay,
                                        size: 16,
                                        color: type == 'MIDDAY'
                                            ? Colors.orange
                                            : Colors.indigo,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${type == 'MIDDAY' ? 'Morning' : 'Evening'}  •  ${p['drawDate']}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            'Sales Close: $sc12  •  Draw: $dr12  •  $status',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.black54,
                                            ),
                                          ),
                                          Text(
                                            'Window: ${_windowLabel(p)}',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: can ? green : Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: statusColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),
                                // 3-digit
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        '3',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        '3-digit Winner',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    if (r3 != null && r3.isNotEmpty)
                                      Flexible(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            'Current: $r3',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.green,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _ctrl3[id],
                                        keyboardType: TextInputType.number,
                                        maxLength: 3,
                                        enabled: can,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          border: const OutlineInputBorder(),
                                          labelText: '3 digits (e.g. 123)',
                                          counterText: '',
                                          suffixIcon:
                                              _ctrl3[id]!.text.isNotEmpty
                                              ? IconButton(
                                                  icon: const Icon(
                                                    Icons.clear,
                                                    size: 16,
                                                  ),
                                                  onPressed: () => setState(
                                                    () => _ctrl3[id]!.clear(),
                                                  ),
                                                )
                                              : null,
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.save, size: 14),
                                      label: Text(
                                        (r3 != null && r3.isNotEmpty)
                                            ? 'Correct'
                                            : 'Save',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: green,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: can ? () => _save3(id) : null,
                                    ),
                                  ],
                                ),
                                if (_winningRestricted && !can)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Locked — opens at $sc12',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                // 4-digit
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        '4',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        '4-digit Winner',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    if (r4 != null && r4.isNotEmpty)
                                      Flexible(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.indigo.shade50,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            'Current: $r4',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.indigo,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _ctrl4[id],
                                        keyboardType: TextInputType.number,
                                        maxLength: 4,
                                        enabled: can,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          border: const OutlineInputBorder(),
                                          labelText: '4 digits (e.g. 1234)',
                                          counterText: '',
                                          suffixIcon:
                                              _ctrl4[id]!.text.isNotEmpty
                                              ? IconButton(
                                                  icon: const Icon(
                                                    Icons.clear,
                                                    size: 16,
                                                  ),
                                                  onPressed: () => setState(
                                                    () => _ctrl4[id]!.clear(),
                                                  ),
                                                )
                                              : null,
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.save, size: 14),
                                      label: Text(
                                        (r4 != null && r4.isNotEmpty)
                                            ? 'Correct'
                                            : 'Save',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.indigo,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: can ? () => _save4(id) : null,
                                    ),
                                  ],
                                ),
                                if (_winningRestricted && !can)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Locked — opens at $sc12',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                      Card(
                        color: const Color(0xFFE8F5E9),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.lightbulb,
                                color: green,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Tip: Change the close time in Draw Schedule and it will apply to all future periods automatically. The Winner screen is the only place to enter winners.',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

extension _FirstOrNull2<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
