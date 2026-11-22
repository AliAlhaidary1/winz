import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';
import '../utils/timezone.dart';

class AdminDrawScreen extends StatefulWidget {
  const AdminDrawScreen({super.key, required this.drawId});
  final String drawId;

  @override
  State<AdminDrawScreen> createState() => _AdminDrawScreenState();
}

class _AdminDrawScreenState extends State<AdminDrawScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String _gameId = 'g_numbers';
  String? _selectedDrawId;
  List<Map<String, dynamic>> _draws = []; // all draws for selected game
  List<Map<String, dynamic>> _periodsCache = [];
  bool _winningRestricted = true;
  List<Map<String, dynamic>> get _pendingDraws {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return _draws.where((d) {
      final win = d['winningNumbers'] as String?;
      if (win != null && win.trim().isNotEmpty) return false;
      if (!_winningRestricted) {
        // Unrestricted: show all pending draws regardless of time
        return true;
      }
      final dt = asInt(d['drawTime']);
      final name = d['name'] as String;
      final isMidday = name.contains('Midday') || name.contains('Morning');
      final type = isMidday ? 'MIDDAY' : 'EVENING';
      final drawDt = MarketTimezone.wallTimeFromEpoch(dt, _tz);
      final dateStr =
          '${drawDt.year}-${drawDt.month.toString().padLeft(2, '0')}-${drawDt.day.toString().padLeft(2, '0')}';
      final pid = '$dateStr-$type';
      final p = _periodsCache.where((e) => e['id'] == pid).firstOrNull;
      if (p == null) return false;
      final salesClose = asInt(p['salesCloseTime']);
      final drawTime = asInt(p['drawTime']);
      const windowMs = 2 * 3600 * 1000;
      return nowMs >= salesClose && nowMs <= drawTime + windowMs;
    }).toList()..sort(
      (a, b) => (asInt(a['drawTime'])).compareTo(asInt(b['drawTime'])),
    );
  }

  final _winCtrl = TextEditingController();
  final Map<String, TextEditingController> _ctrl3 = {};
  final Map<String, TextEditingController> _ctrl4 = {};
  bool _processing = false;
  String? _error;
  String? _success;
  Map<String, dynamic>? _lastResult;
  List<Map<String, dynamic>> _winningTickets = [];
  bool _autoPay = false;
  String _tz = MarketTimezone.defaultTimezone;

  String _fmt12FromMs(int ms) => MarketTimezone.format12FromEpoch(ms, _tz);
  bool _canEnterPeriod(Map<String, dynamic> p) {
    if (!_winningRestricted) return true;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sc = asInt(p['salesCloseTime']);
    final dr = asInt(p['drawTime']);
    const window = 2 * 3600 * 1000;
    return now >= sc && now <= dr + window;
  }

  String _windowLabelPeriod(Map<String, dynamic> p) {
    final sc = _fmt12FromMs(asInt(p['salesCloseTime']));
    final dr = _fmt12FromMs(asInt(p['drawTime']));
    final dr2Str = _fmt12FromMs((asInt(p['drawTime'])) + 2 * 3600 * 1000);
    return '$sc — $dr (window till $dr2Str)';
  }

  List<Map<String, dynamic>> get _availablePeriods {
    // Only periods where at least one of result3/4 is pending AND window open (if restricted)
    return _periodsCache.where((p) {
      if (p['status'] == 'CANCELLED' ||
          p['status'] == 'POSTPONED' ||
          p['status'] == 'SUSPENDED')
        return false;
      final r3 = p['result3'] as String?;
      final r4 = p['result4'] as String?;
      final hasPending3 = r3 == null || r3.trim().isEmpty;
      final hasPending4 = r4 == null || r4.trim().isEmpty;
      if (!hasPending3 && !hasPending4) return false; // both already published
      if (_winningRestricted && !_canEnterPeriod(p)) return false;
      // Only for this day — as requested by the client: do not show four for different dates
      try {
        final d = DateTime.parse(p['drawDate'] as String);
        final nowWall = MarketTimezone.wallTimeFromEpoch(
          DateTime.now().millisecondsSinceEpoch,
          _tz,
        );
        final today = DateTime(nowWall.year, nowWall.month, nowWall.day);
        final diff = d.difference(today).inDays;
        if (diff != 0) return false; // today only
      } catch (_) {}
      return true;
    }).toList()..sort(
      (a, b) =>
          (asInt(a['salesCloseTime'])).compareTo(asInt(b['salesCloseTime'])),
    );
  }

  Widget _buildExclusiveWinnerTab() {
    final available = _availablePeriods;
    // init controllers for available periods if missing
    for (final p in available) {
      final id = p['id'] as String;
      _ctrl3.putIfAbsent(
        id,
        () => TextEditingController(text: (p['result3'] as String?) ?? ''),
      );
      _ctrl4.putIfAbsent(
        id,
        () => TextEditingController(text: (p['result4'] as String?) ?? ''),
      );
      // sync existing values
      final v3 = (p['result3'] as String?) ?? '';
      final v4 = (p['result4'] as String?) ?? '';
      if (_ctrl3[id]!.text != v3) _ctrl3[id]!.text = v3;
      if (_ctrl4[id]!.text != v4) _ctrl4[id]!.text = v4;
    }
    if (available.isEmpty) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final now12 = MarketTimezone.format12FromEpoch(nowMs, _tz);
      final nowWall = MarketTimezone.wallTimeFromEpoch(nowMs, _tz);
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Card(
                  color: Colors.orange.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.timer_off,
                          color: Colors.orange,
                          size: 36,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No period available now',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Current time $now12 — the window opens only during [Sales Close — Draw + 2 hours]',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Builder(
                          builder: (_) {
                            final todayStr =
                                '${nowWall.year}-${nowWall.month.toString().padLeft(2, '0')}-${nowWall.day.toString().padLeft(2, '0')}';
                            final todayPeriods =
                                _periodsCache
                                    .where((p) => p['drawDate'] == todayStr)
                                    .toList()
                                  ..sort(
                                    (a, b) => (asInt(a['salesCloseTime']))
                                        .compareTo(asInt(b['salesCloseTime'])),
                                  );
                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    "Today's periods (12h):",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (todayPeriods.isEmpty)
                                    const Text(
                                      'No periods for today',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ...todayPeriods.map((p) {
                                    final sc = _fmt12FromMs(
                                      asInt(p['salesCloseTime']),
                                    );
                                    final dr = _fmt12FromMs(
                                      asInt(p['drawTime']),
                                    );
                                    final type = p['drawType'] as String;
                                    final r3 = (p['result3'] as String?) ?? '';
                                    final r4 = (p['result4'] as String?) ?? '';
                                    final done = r3.isNotEmpty && r4.isNotEmpty;
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: done
                                                  ? Colors.blue
                                                  : p['status'] == 'OPEN'
                                                  ? Colors.green
                                                  : Colors.grey,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '${type == 'MIDDAY' ? 'Midday' : 'Evening'} — $sc → $dr • ${p['status']}${done ? ' • Done' : ' • Available ${r3.isEmpty ? '3' : ''}${r3.isEmpty && r4.isEmpty ? ' & ' : ''}${r4.isEmpty ? '4' : ''}'}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Refresh'),
                          onPressed: _loadDraws,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0B8A3E),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.info_outline,
                            color: Color(0xFF0B8A3E),
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Editing is allowed while the window is open. Once [Draw + 2 hours] ends, editing closes automatically.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black87,
                            ),
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
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                color: Colors.green.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.emoji_events,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Winner Entry — Exclusively Here (12h)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Only the currently available period is shown. Other periods are hidden to simplify the user experience.',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.black54,
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${available.length} available',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...available.map((p) {
                final id = p['id'] as String;
                final type = p['drawType'] as String;
                final sc12 = _fmt12FromMs(asInt(p['salesCloseTime']));
                final dr12 = _fmt12FromMs(asInt(p['drawTime']));
                final status = p['status'] as String;
                final can = _canEnterPeriod(p);
                final r3 = p['result3'] as String?;
                final r4 = p['result4'] as String?;
                final hasPending3 = r3 == null || r3.isEmpty;
                final hasPending4 = r4 == null || r4.isEmpty;
                final statusColor = status == 'OPEN'
                    ? const Color(0xFF0B8A3E)
                    : status == 'RESULT_PENDING'
                    ? Colors.orange
                    : Colors.blue;
                final isLocked = !can;
                return Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: isLocked
                          ? Colors.grey.shade300
                          : statusColor.withValues(alpha: 0.2),
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
                                  ? Colors.orange.withValues(alpha: 0.15)
                                  : Colors.indigo.withValues(alpha: 0.15),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${type == 'MIDDAY' ? 'Morning' : 'Evening'} • ${p['drawDate']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    'Close: $sc12 • Draw: $dr12',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Window: ${_windowLabelPeriod(p)}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: isLocked
                                          ? Colors.red
                                          : const Color(0xFF0B8A3E),
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
                                color: isLocked
                                    ? Colors.grey.shade200
                                    : statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                isLocked ? 'Locked' : status,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: isLocked ? Colors.grey : statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (isLocked)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.lock,
                                  size: 14,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Entry period ended — editing is locked until the next period',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Divider(height: 16),
                        // 3-digit
                        Opacity(
                          opacity: hasPending3 && !isLocked
                              ? 1
                              : (hasPending3 ? 0.5 : 1),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(
                                        alpha: 0.12,
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
                                  const Text(
                                    '3-digit Winner',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (r3 != null && r3.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Current: $r3',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ),
                                  if (!hasPending3)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 6),
                                      child: Icon(
                                        Icons.check_circle,
                                        size: 14,
                                        color: Colors.green,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _ctrl3[id]!,
                                      keyboardType: TextInputType.number,
                                      maxLength: 3,
                                      enabled: !isLocked,
                                      decoration: InputDecoration(
                                        isDense: true,
                                        border: const OutlineInputBorder(),
                                        labelText: '3 digits (e.g. 123)',
                                        counterText: '',
                                        suffixIcon:
                                            _ctrl3[id]!.text.isNotEmpty &&
                                                !isLocked
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
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    icon: Icon(
                                      (r3 != null && r3.isNotEmpty)
                                          ? Icons.edit
                                          : Icons.save,
                                      size: 14,
                                    ),
                                    label: Text(
                                      (r3 != null && r3.isNotEmpty)
                                          ? 'Correct'
                                          : 'Save',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: isLocked
                                        ? null
                                        : () => _savePeriod3(id),
                                  ),
                                ],
                              ),
                              if (isLocked && hasPending3)
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
                        const SizedBox(height: 12),
                        // 4-digit
                        Opacity(
                          opacity: hasPending4 && !isLocked
                              ? 1
                              : (hasPending4 ? 0.5 : 1),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.withValues(
                                        alpha: 0.12,
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
                                  const Text(
                                    '4-digit Winner',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (r4 != null && r4.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Current: $r4',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                    ),
                                  if (!hasPending4)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 6),
                                      child: Icon(
                                        Icons.check_circle,
                                        size: 14,
                                        color: Colors.indigo,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _ctrl4[id]!,
                                      keyboardType: TextInputType.number,
                                      maxLength: 4,
                                      enabled: !isLocked,
                                      decoration: InputDecoration(
                                        isDense: true,
                                        border: const OutlineInputBorder(),
                                        labelText: '4 digits (e.g. 1234)',
                                        counterText: '',
                                        suffixIcon:
                                            _ctrl4[id]!.text.isNotEmpty &&
                                                !isLocked
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
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    icon: Icon(
                                      (r4 != null && r4.isNotEmpty)
                                          ? Icons.edit
                                          : Icons.save,
                                      size: 14,
                                    ),
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
                                    onPressed: isLocked
                                        ? null
                                        : () => _savePeriod4(id),
                                  ),
                                ],
                              ),
                              if (isLocked && hasPending4)
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
                        if (_processing)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: const LinearProgressIndicator(),
                          ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              Card(
                color: const Color(0xFFE8F5E9),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lightbulb,
                        color: Color(0xFF0B8A3E),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Editing is allowed while the window is open. After [Draw + 2 hours] ends, it closes automatically and the period disappears from here and appears in the history.',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: const Color(0xFFE8F5E9),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lightbulb,
                        color: Color(0xFF0B8A3E),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Editing is allowed while the window is open. After [Draw + 2 hours] ends, it closes automatically and the period disappears from here and appears in the history.',
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
    );
  }

  // --- History tab filters ---
  String _historyGame = 'all'; // all / g_numbers / g_winz
  String _historyStatus = 'all'; // all / pending / done
  DateTime? _historyDate; // null = all dates
  String _historySearch = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    if (widget.drawId.isNotEmpty && widget.drawId.startsWith('g_')) {
      _gameId = widget.drawId;
    }
    _loadDraws();
  }

  Future<void> _savePeriod3(String periodId) async {
    final raw =
        _ctrl3[periodId]?.text.trim().replaceAll(',', '').replaceAll(' ', '') ??
        '';
    if (!RegExp(r'^[0-9]{3}$').hasMatch(raw)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('3-digit winner must be 3 digits (0-9)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final period = _periodsCache.firstWhere(
      (e) => e['id'] == periodId,
      orElse: () => {},
    );
    if (period.isEmpty) return;
    if (_winningRestricted && !_canEnterPeriod(period)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Entry window ended — ${_windowLabelPeriod(period)}'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final existing = period['result3'] as String?;
    final isCorrection = existing != null && existing.isNotEmpty;
    setState(() => _processing = true);
    try {
      final app = context.read<AppState>();
      final res = await app.processPeriodResult(
        periodId: periodId,
        winningNumbers: raw.split(''),
        isCorrection: isCorrection,
      );
      await _loadDraws();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '3-digit winner $raw saved — Winners: ${res['winningCount']} • Prizes: ${fmtMoney(res['totalPrize'])}',
          ),
          backgroundColor: const Color(0xFF0B8A3E),
        ),
      );
      setState(() => _success = '3-digit $raw saved');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _savePeriod4(String periodId) async {
    final raw =
        _ctrl4[periodId]?.text.trim().replaceAll(',', '').replaceAll(' ', '') ??
        '';
    if (!RegExp(r'^[0-9]{4}$').hasMatch(raw)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('4-digit winner must be 4 digits (0-9)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final period = _periodsCache.firstWhere(
      (e) => e['id'] == periodId,
      orElse: () => {},
    );
    if (period.isEmpty) return;
    if (_winningRestricted && !_canEnterPeriod(period)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Entry window ended — ${_windowLabelPeriod(period)}'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final existing = period['result4'] as String?;
    final isCorrection = existing != null && existing.isNotEmpty;
    setState(() => _processing = true);
    try {
      final app = context.read<AppState>();
      final res = await app.processPeriodResult(
        periodId: periodId,
        winningNumbers: raw.split(''),
        isCorrection: isCorrection,
      );
      await _loadDraws();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '4-digit winner $raw saved — Winners: ${res['winningCount']} • Prizes: ${fmtMoney(res['totalPrize'])}',
          ),
          backgroundColor: Colors.indigo,
        ),
      );
      setState(() => _success = '4-digit $raw saved');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  void dispose() {
    _winCtrl.dispose();
    for (final c in _ctrl3.values) c.dispose();
    for (final c in _ctrl4.values) c.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDraws() async {
    final db = context.read<AppDatabase>();
    await db.seedDrawPeriods();
    await db.refreshPeriodStatuses();
    _periodsCache = await db.getAllPeriods();
    // Load winning restriction setting
    final cfg = await db.getAppConfig();
    final wr = cfg
        .where((e) => e['key'] == 'winning_time_restricted')
        .firstOrNull;
    final restricted = wr == null ? true : wr['value'] == '1';
    final tzEntry = cfg.where((e) => e['key'] == 'draw_timezone').firstOrNull;
    final tz = tzEntry == null
        ? MarketTimezone.defaultTimezone
        : tzEntry['value'] as String;
    if (mounted)
      setState(() {
        _winningRestricted = restricted;
        _tz = tz;
      });
    List<Map<String, dynamic>> draws;
    if (_gameId == 'all') {
      draws = await db.getAllDraws();
    } else {
      draws = await db.getDrawsByGame(_gameId);
    }
    // Ensure sorted by drawTime ascending for pending tab (soonest first)
    draws.sort(
      (a, b) => (asInt(a['drawTime'])).compareTo(asInt(b['drawTime'])),
    );
    if (!mounted) return;
    setState(() {
      _draws = draws;
      // Auto-select first pending if current selection is null or now not pending
      final pending = _pendingDraws;
      final currentStillPending =
          _selectedDrawId != null &&
          pending.any((d) => d['id'] == _selectedDrawId);
      if (_selectedDrawId == null || !currentStillPending) {
        if (pending.isNotEmpty) {
          _selectedDrawId = pending.first['id'] as String;
          _fillWinCtrlFromDraw();
        } else {
          // No pending: keep selection null to force empty state (prompt to go to history)
          _selectedDrawId = null;
          _winCtrl.clear();
        }
      } else {
        _fillWinCtrlFromDraw();
      }
    });
    await _loadWinningPreview();
  }

  void _fillWinCtrlFromDraw() {
    if (_selectedDrawId == null) {
      _winCtrl.clear();
      return;
    }
    final d = _draws.where((e) => e['id'] == _selectedDrawId).firstOrNull;
    if (d != null &&
        d['winningNumbers'] != null &&
        (d['winningNumbers'] as String).trim().isNotEmpty) {
      final s = (d['winningNumbers'] as String).replaceAll(',', '');
      _winCtrl.text = s;
    } else {
      if (_success == null) _winCtrl.clear();
    }
  }

  Future<void> _loadWinningPreview() async {
    if (_selectedDrawId == null) {
      if (mounted) setState(() => _winningTickets = []);
      return;
    }
    final db = context.read<AppDatabase>();
    final tickets = await db.getTickets();
    final draw = _draws.where((e) => e['id'] == _selectedDrawId).firstOrNull;
    final winStr = draw?['winningNumbers'] as String?;
    if (winStr == null || winStr.isEmpty) {
      if (mounted) setState(() => _winningTickets = []);
      return;
    }
    // Show already winning tickets for this draw (including multi-line via ticket_lines)
    final winning = tickets
        .where(
          (t) =>
              t['drawId'] == _selectedDrawId &&
              (t['status'] == 'winning' || t['status'] == 'paid'),
        )
        .toList();
    // Also include multi-line tickets where draw appears only in lines
    if (winning.isEmpty) {
      final allLines = await db.getAllTicketLines();
      final ids = allLines
          .where((l) => l['drawId'] == _selectedDrawId)
          .map((l) => l['ticketId'] as String)
          .toSet();
      final extra = tickets
          .where(
            (t) =>
                ids.contains(t['id']) &&
                (t['status'] == 'winning' || t['status'] == 'paid'),
          )
          .toList();
      winning.addAll(extra);
    }
    if (mounted) setState(() => _winningTickets = winning);
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _success = null;
      _lastResult = null;
    });
    if (_selectedDrawId == null) {
      setState(() => _error = 'No pending draws — go to History');
      return;
    }
    // Check time restriction
    if (_winningRestricted) {
      final isPending = _pendingDraws.any((d) => d['id'] == _selectedDrawId);
      if (!isPending) {
        setState(
          () => _error = 'Not the time to enter winning number — entry allowed only during [salesClose — drawTime+2h] window. Check history or wait for notification.',
        );
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Important: Not the entry window — winning entry is time-restricted. Wait for notification.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        return;
      }
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
    if (_gameId == 'g_numbers' && raw.length != 3 && raw.length != 4) {
      setState(() => _error = 'Numbers needs 3 or 4 digits (e.g. 123 or 0123)');
      return;
    }
    if (_gameId == 'g_winz' && raw.length != 4) {
      setState(() => _error = 'Win 4 needs exactly 4 digits');
      return;
    }
    final draw = _draws.where((e) => e['id'] == _selectedDrawId).firstOrNull;
    if (draw != null &&
        draw['winningNumbers'] != null &&
        (draw['winningNumbers'] as String).trim().isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Confirm replacement'),
          content: Text(
            'Draw $_selectedDrawId already has result: ${draw['winningNumbers']}. Replace with $raw and recalculate winners?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _processing = true);
    try {
      final digits = raw.split('');
      final app = context.read<AppState>();
      final res = await app.processDrawResult(
        drawId: _selectedDrawId!,
        winningNumbers: digits,
        autoPay: _autoPay,
      );
      // If unrestricted, immediately close the period for this draw
      if (!_winningRestricted) {
        try {
          final d = _draws.where((e) => e['id'] == _selectedDrawId).firstOrNull;
          if (d != null) {
            final dt = MarketTimezone.wallTimeFromEpoch(
              asInt(d['drawTime']),
              _tz,
            );
            final name = d['name'] as String;
            final isMidday =
                name.contains('Midday') || name.contains('Morning');
            final type = isMidday ? 'MIDDAY' : 'EVENING';
            final dateStr =
                '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
            final pid = '$dateStr-$type';
            final db = context.read<AppDatabase>();
            final p = await db.getPeriodById(pid);
            if (p != null) {
              // Close period immediately
              await db.updatePeriodStatus(pid, 'COMPLETED');
              // Ensure sales are closed - update salesClose to now if still future
              final nowMs = DateTime.now().millisecondsSinceEpoch;
              if ((asInt(p['salesCloseTime'])) > nowMs) {
                await db.updatePeriodTimes(
                  pid,
                  asInt(p['salesOpenTime']),
                  nowMs,
                  asInt(p['drawTime']),
                );
              }
            }
          }
        } catch (_) {}
      }
      await _loadDraws();
      await _loadWinningPreview();
      if (!mounted) return;
      setState(() {
        _success =
            'Saved $raw — Winners: ${res['winningCount']} • Losers: ${res['losingCount']} • Prize: ${fmtMoney(res['totalPrize'])}';
        _lastResult = res;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_success!)));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _editWinnerForDraw(Map<String, dynamic> draw) async {
    // Check window lock for this draw's period
    try {
      final dt = MarketTimezone.wallTimeFromEpoch(asInt(draw['drawTime']), _tz);
      final name = draw['name'] as String;
      final isMidday = name.contains('Midday') || name.contains('Morning');
      final type = isMidday ? 'MIDDAY' : 'EVENING';
      final dateStr =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final pid = '$dateStr-$type';
      final p = await context.read<AppDatabase>().getPeriodById(pid);
      if (p != null && _winningRestricted) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final sc = asInt(p['salesCloseTime']);
        final dr = asInt(p['drawTime']);
        const window = 2 * 3600 * 1000;
        final can = now >= sc && now <= dr + window;
        if (!can) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Editing period for $pid has ended — the window was open until ${_fmt12FromMs(dr + window)}',
                ),
                backgroundColor: Colors.red,
              ),
            );
          return;
        }
      }
    } catch (_) {}
    final ctrl = TextEditingController(
      text: (draw['winningNumbers'] as String?)?.replaceAll(',', '') ?? '',
    );
    final gid = draw['gameId'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Winner — ${draw['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ID: ${draw['id']}',
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              maxLength: gid == 'g_numbers' ? 4 : 4,
              decoration: InputDecoration(
                labelText: 'Winner',
                hintText: gid == 'g_winz' ? '0123' : '123',
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              gid == 'g_numbers'
                  ? 'Enter 3 or 4 digits'
                  : 'Enter exactly 4 digits',
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            StatefulBuilder(
              builder: (ctx, setS) {
                return CheckboxListTile(
                  value: _autoPay,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Auto-pay ALL currently-computed winners (deducts cash)',
                    style: TextStyle(fontSize: 11),
                  ),
                  onChanged: (v) {
                    setState(() => _autoPay = v ?? false);
                    setS(() {});
                  },
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final raw = ctrl.text.trim().replaceAll(',', '').replaceAll(' ', '');
    if (raw.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(raw)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid winning number (digits 0-9)'),
        ),
      );
      return;
    }
    if (gid == 'g_winz' && raw.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Win 4 requires exactly 4 digits')),
      );
      return;
    }
    if (gid == 'g_numbers' && raw.length != 3 && raw.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Numbers requires 3 or 4 digits')),
      );
      return;
    }
    final existingWin =
        (draw['winningNumbers'] as String?)?.trim().isNotEmpty == true;
    if (existingWin && _autoPay) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text(
            'Confirm replacement with auto-pay',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'This draw already has result ${draw['winningNumbers']}. Replacing it with $raw recomputes winners and will immediately pay ALL currently-computed winning tickets, deducting cash from the drawer. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Replace & Pay All'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    setState(() => _processing = true);
    try {
      final res = await context.read<AppState>().processDrawResult(
        drawId: draw['id'],
        winningNumbers: raw.split(''),
        autoPay: _autoPay,
      );
      await _loadDraws();
      await _loadWinningPreview();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved $raw — ${res['winningCount']} winner(s)'),
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  List<Map<String, dynamic>> get _filteredHistory {
    List<Map<String, dynamic>> list = List.from(_draws);
    // Need to fetch all draws for history when _gameId filter is 'all' already loaded. For history game filter, apply separate.
    if (_historyGame != 'all') {
      list = list.where((d) => d['gameId'] == _historyGame).toList();
    }
    if (_historyStatus == 'pending') {
      list = list.where((d) {
        final win = d['winningNumbers'] as String?;
        return win == null || win.trim().isEmpty;
      }).toList();
    } else if (_historyStatus == 'done') {
      list = list.where((d) {
        final win = d['winningNumbers'] as String?;
        return win != null && win.trim().isNotEmpty;
      }).toList();
    }
    if (_historyDate != null) {
      final y = _historyDate!.year,
          m = _historyDate!.month,
          d = _historyDate!.day;
      list = list.where((e) {
        final dt = MarketTimezone.wallTimeFromEpoch(asInt(e['drawTime']), _tz);
        return dt.year == y && dt.month == m && dt.day == d;
      }).toList();
    }
    if (_historySearch.trim().isNotEmpty) {
      final q = _historySearch.trim().toLowerCase();
      list = list
          .where(
            (e) =>
                (e['name'] as String).toLowerCase().contains(q) ||
                (e['id'] as String).toLowerCase().contains(q) ||
                ((e['winningNumbers'] as String?) ?? '').contains(q),
          )
          .toList();
    }
    list.sort((a, b) => (asInt(b['drawTime'])).compareTo(asInt(a['drawTime'])));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingDraws;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw Result — NY Lottery'),
        backgroundColor: const Color(0xFF0B8A3E),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.edit), text: 'Enter Winner'),
            Tab(icon: Icon(Icons.history), text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // TAB 1: Winner exclusive — available period only (12h)
          _buildExclusiveWinnerTab(),
          // TAB 2: History
          // TAB 2: History —  All
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Filters',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${_filteredHistory.length}/${_draws.length} shown',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ChoiceChip(
                                label: const Text('All'),
                                selected: _historyGame == 'all',
                                onSelected: (_) =>
                                    setState(() => _historyGame = 'all'),
                              ),
                              const SizedBox(width: 6),
                              ChoiceChip(
                                label: const Text('Numbers'),
                                selected: _historyGame == 'g_numbers',
                                onSelected: (_) =>
                                    setState(() => _historyGame = 'g_numbers'),
                              ),
                              const SizedBox(width: 6),
                              ChoiceChip(
                                label: const Text('Win 4'),
                                selected: _historyGame == 'g_winz',
                                onSelected: (_) =>
                                    setState(() => _historyGame = 'g_winz'),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                width: 1,
                                height: 24,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(width: 12),
                              ChoiceChip(
                                label: const Text('All'),
                                selected: _historyStatus == 'all',
                                onSelected: (_) =>
                                    setState(() => _historyStatus = 'all'),
                              ),
                              const SizedBox(width: 6),
                              ChoiceChip(
                                label: const Text('Pending'),
                                selected: _historyStatus == 'pending',
                                onSelected: (_) =>
                                    setState(() => _historyStatus = 'pending'),
                              ),
                              const SizedBox(width: 6),
                              ChoiceChip(
                                label: const Text('Announced'),
                                selected: _historyStatus == 'done',
                                onSelected: (_) =>
                                    setState(() => _historyStatus = 'done'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  isDense: true,
                                  prefixIcon: Icon(Icons.search, size: 16),
                                  hintText: 'Search name, ID, or winner',
                                  border: OutlineInputBorder(),
                                  hintStyle: TextStyle(fontSize: 11),
                                ),
                                style: const TextStyle(fontSize: 12),
                                onChanged: (v) =>
                                    setState(() => _historySearch = v),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(
                                  Icons.calendar_today,
                                  size: 14,
                                ),
                                label: Text(
                                  _historyDate == null
                                      ? 'Any date'
                                      : '${_historyDate!.year}/${_historyDate!.month.toString().padLeft(2, '0')}/${_historyDate!.day.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _historyDate ?? DateTime.now(),
                                    firstDate: DateTime(2024),
                                    lastDate: DateTime(2030),
                                  );
                                  if (picked != null)
                                    setState(() => _historyDate = picked);
                                },
                              ),
                              if (_historyDate != null) ...[
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () =>
                                      setState(() => _historyDate = null),
                                ),
                              ],
                              const SizedBox(width: 6),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.today, size: 14),
                                label: const Text(
                                  'Today',
                                  style: TextStyle(fontSize: 11),
                                ),
                                onPressed: () => setState(
                                  () => _historyDate = DateTime.now(),
                                ),
                              ),
                              const SizedBox(width: 6),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.history, size: 14),
                                label: const Text(
                                  'Yesterday',
                                  style: TextStyle(fontSize: 11),
                                ),
                                onPressed: () => setState(
                                  () => _historyDate = DateTime.now().subtract(
                                    const Duration(days: 1),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _filteredHistory.isEmpty
                        ? const Center(
                            child: Text(
                              'No draws found',
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _filteredHistory.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (c, i) {
                              final d = _filteredHistory[i];
                              final win = d['winningNumbers'] as String?;
                              final hasWinner =
                                  win != null && win.trim().isNotEmpty;
                              final dt = MarketTimezone.wallTimeFromEpoch(
                                asInt(d['drawTime']),
                                _tz,
                              );
                              final drawTime12 =
                                  MarketTimezone.format12FromEpoch(
                                    asInt(d['drawTime']),
                                    _tz,
                                  );
                              final statusColor = hasWinner
                                  ? Colors.green
                                  : Colors.orange;
                              // window check for history edit lock
                              bool canEditHistory = true;
                              try {
                                final n = d['name'] as String;
                                final isMid =
                                    n.contains('Midday') ||
                                    n.contains('Morning');
                                final tt = isMid ? 'MIDDAY' : 'EVENING';
                                final ds =
                                    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                                final pidH = '$ds-$tt';
                                final ph = _periodsCache
                                    .where((e) => e['id'] == pidH)
                                    .firstOrNull;
                                if (ph != null && _winningRestricted) {
                                  final now =
                                      DateTime.now().millisecondsSinceEpoch;
                                  final sc = asInt(ph['salesCloseTime']);
                                  final dr = asInt(ph['drawTime']);
                                  canEditHistory =
                                      now >= sc && now <= dr + 2 * 3600 * 1000;
                                  // if no winner yet and window closed, also cannot add
                                  if (!hasWinner && !canEditHistory)
                                    canEditHistory = false;
                                }
                              } catch (_) {}
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(
                                                alpha: 0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              hasWinner
                                                  ? 'Announced'
                                                  : 'Pending',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: statusColor,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              d['gameId'] == 'g_winz'
                                                  ? 'Win 4'
                                                  : 'Numbers',
                                              style: const TextStyle(
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          Flexible(
                                            child: Builder(
                                              builder: (_) {
                                                return Text(
                                                  '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} • $drawTime12',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.black54,
                                                  ),
                                                  textAlign: TextAlign.end,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        d['name'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'ID: ${d['id']}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.black45,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: hasWinner
                                                    ? Colors.green.shade50
                                                    : Colors.grey.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'Winner',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                  Text(
                                                    hasWinner
                                                        ? win.replaceAll(
                                                            ',',
                                                            ' ',
                                                          )
                                                        : '— No winner —',
                                                    style: TextStyle(
                                                      fontSize: hasWinner
                                                          ? 16
                                                          : 12,
                                                      fontWeight: hasWinner
                                                          ? FontWeight.w900
                                                          : FontWeight.w500,
                                                      letterSpacing: hasWinner
                                                          ? 2
                                                          : 0,
                                                      color: hasWinner
                                                          ? Colors
                                                                .green
                                                                .shade700
                                                          : Colors.black45,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Column(
                                            children: [
                                              ElevatedButton.icon(
                                                icon: Icon(
                                                  canEditHistory
                                                      ? (hasWinner
                                                            ? Icons.edit
                                                            : Icons.add)
                                                      : Icons.lock,
                                                  size: 14,
                                                ),
                                                label: Text(
                                                  hasWinner
                                                      ? (canEditHistory
                                                            ? 'Correct'
                                                            : 'Locked')
                                                      : 'Enter',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      canEditHistory
                                                      ? (hasWinner
                                                            ? Colors.orange
                                                            : const Color(
                                                                0xFF0B8A3E,
                                                              ))
                                                      : Colors.grey,
                                                  foregroundColor: Colors.white,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8,
                                                      ),
                                                ),
                                                onPressed: canEditHistory
                                                    ? () =>
                                                          _editWinnerForDraw(d)
                                                    : null,
                                              ),
                                              const SizedBox(height: 4),
                                              if (hasWinner)
                                                Text(
                                                  canEditHistory
                                                      ? 'Tap to edit'
                                                      : 'Locked',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    color: canEditHistory
                                                        ? Colors.black45
                                                        : Colors.red,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
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
        ],
      ),
    );
  }

  Widget _profitRow(String label, String mult, String ex) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              mult,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  ex,
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
