import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../services/draw_period_service.dart';
import '../../providers/app_state.dart';
import '../../utils/responsive.dart';
import '../../utils/timezone.dart';

class DrawSettingsScreen extends StatefulWidget {
  const DrawSettingsScreen({super.key});
  @override
  State<DrawSettingsScreen> createState() => _DrawSettingsScreenState();
}

class _DrawSettingsScreenState extends State<DrawSettingsScreen> {
  List<Map<String, dynamic>> _drawConfigs = [];
  String _tz = MarketTimezone.defaultTimezone;
  bool _winningRestricted = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final c = await db.getAppConfig();
    final svc = DrawPeriodService(db);
    final dcfgs = await svc.getAllDrawConfigs();
    final tz = await svc.getTimezone();
    final wr = c
        .where((e) => e['key'] == 'winning_time_restricted')
        .firstOrNull;
    final restricted = wr == null ? true : wr['value'] == '1';
    if (wr == null)
      await db.upsertConfig('winning_time_restricted', '1', 'local');
    if (!mounted) return;
    setState(
      () => {
        _drawConfigs = dcfgs,
        _tz = tz,
        _winningRestricted = restricted,
        _loading = false,
      },
    );
  }

  Future<void> _toggleWinningRestricted(bool v) async {
    final db = context.read<AppDatabase>();
    await db.upsertConfig('winning_time_restricted', v ? '1' : '0', 'local');
    setState(() => _winningRestricted = v);
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            v
                ? 'Winning entry is now time-restricted'
                : 'Winning entry is now unrestricted',
          ),
          backgroundColor: const Color(0xFF0B8A3E),
        ),
      );
  }

  String _fmt12(String hhmm) {
    try {
      final p = hhmm.trim().split(':');
      int h = int.parse(p[0]);
      int m = int.parse(p[1].replaceAll(RegExp(r'[^0-9]'), ''));
      // handle AM/PM already stored
      if (hhmm.toUpperCase().contains('PM') && h < 12) h += 12;
      if (hhmm.toUpperCase().contains('AM') && h == 12) h = 0;
      bool am = h < 12;
      int h12 = h % 12;
      if (h12 == 0) h12 = 12;
      return '$h12:${m.toString().padLeft(2, '0')} ${am ? 'AM' : 'PM'}';
    } catch (_) {
      return hhmm;
    }
  }

  TimeOfDay _parseToTOD(String s) {
    try {
      s = s.trim();
      bool isPM = s.toUpperCase().contains('PM');
      bool isAM = s.toUpperCase().contains('AM');
      s = s.replaceAll(RegExp(r'\s*[AP]M', caseSensitive: false), '').trim();
      final p = s.split(':');
      int h = int.parse(p[0]);
      int m = int.parse(p[1]);
      if (isPM && h < 12) h += 12;
      if (isAM && h == 12) h = 0;
      return TimeOfDay(hour: h, minute: m);
    } catch (_) {
      return const TimeOfDay(hour: 14, minute: 15);
    }
  }

  String _todTo24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String _todTo12(TimeOfDay t) {
    int h = t.hour;
    bool am = h < 12;
    int h12 = h % 12;
    if (h12 == 0) h12 = 12;
    return '$h12:${t.minute.toString().padLeft(2, '0')} ${am ? 'AM' : 'PM'}';
  }

  Future<void> _editDrawConfig(Map<String, dynamic> cfg) async {
    final drawType = cfg['drawType'] as String;
    TimeOfDay salesClose = _parseToTOD(cfg['salesClose'] as String);
    TimeOfDay drawTime = _parseToTOD(cfg['drawTime'] as String);
    bool enabled = cfg['enabled'] as bool;
    String resultMode = cfg['resultMode'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            'Configure $drawType — 12h',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'اختر الوقت بنظام 12 ساعة — سيُحفظ تلقائياً ويُطبق على الفترات القادمة',
                  style: TextStyle(fontSize: 10, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(
                    Icons.timer,
                    size: 16,
                    color: Colors.deepPurple,
                  ),
                  label: Text(
                    'إغلاق البيع: ${_todTo12(salesClose)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: salesClose,
                      builder: (ctx2, child) => MediaQuery(
                        data: MediaQuery.of(ctx2)
                            .copyWith(alwaysUse24HourFormat: false),
                        child: child!,
                      ),
                    );
                    if (picked != null) setS(() => salesClose = picked);
                  },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(
                    Icons.alarm,
                    size: 16,
                    color: Colors.deepPurple,
                  ),
                  label: Text(
                    'وقت السحب: ${_todTo12(drawTime)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: drawTime,
                      builder: (ctx2, child) => MediaQuery(
                        data: MediaQuery.of(ctx2)
                            .copyWith(alwaysUse24HourFormat: false),
                        child: child!,
                      ),
                    );
                    if (picked != null) setS(() => drawTime = picked);
                  },
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'المعاينة 12h:\nSales Close ${_todTo12(salesClose)}  •  Draw ${_todTo12(drawTime)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: enabled,
                  title: const Text('Enabled', style: TextStyle(fontSize: 12)),
                  dense: true,
                  onChanged: (v) => setS(() => enabled = v),
                ),
                DropdownButtonFormField<String>(
                  value: resultMode,
                  decoration: const InputDecoration(
                    labelText: 'Result Mode',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'manual', child: Text('Manual')),
                    DropdownMenuItem(value: 'auto', child: Text('Automatic')),
                  ],
                  onChanged: (v) => setS(() => resultMode = v ?? 'manual'),
                ),
              ],
            ),
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final svc = DrawPeriodService(context.read<AppDatabase>());
    final user = context.read<AppState>().currentUser?['username'] as String?;
    try {
      await svc.updateDrawConfig(
        drawType: drawType,
        salesClose: _todTo24(salesClose),
        drawTime: _todTo24(drawTime),
        enabled: enabled,
        resultMode: resultMode,
        user: user,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$drawType updated — ${_todTo12(salesClose)} / ${_todTo12(drawTime)}',
          ),
          backgroundColor: const Color(0xFF0B8A3E),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _editTimezone() async {
    final ctrl = TextEditingController(text: _tz);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Timezone', style: TextStyle(fontSize: 13)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Timezone',
            hintText: 'America/New_York',
            border: OutlineInputBorder(),
            isDense: true,
          ),
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
    final svc = DrawPeriodService(context.read<AppDatabase>());
    await svc.setTimezone(ctrl.text.trim());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF0B8A3E);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        backgroundColor: green,
        foregroundColor: Colors.white,
        title: const Text('Draw Settings'),
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
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule,
                            size: 16,
                            color: Colors.deepPurple,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Draw Schedule',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.deepPurple,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _tz,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.edit,
                              size: 14,
                              color: Colors.deepPurple,
                            ),
                            onPressed: _editTimezone,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._drawConfigs.map((cfg) {
                        final type = cfg['drawType'] as String;
                        final enabled = cfg['enabled'] as bool;
                        return Card(
                          color: enabled ? Colors.white : Colors.grey.shade100,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: enabled
                                  ? Colors.deepPurple.withOpacity(0.15)
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: enabled
                                  ? Colors.deepPurple.withOpacity(0.1)
                                  : Colors.grey.shade200,
                              child: Icon(
                                type == 'MIDDAY'
                                    ? Icons.wb_sunny
                                    : Icons.nights_stay,
                                color: enabled
                                    ? Colors.deepPurple
                                    : Colors.grey,
                                size: 16,
                              ),
                            ),
                            title: Text(
                              type == 'MIDDAY'
                                  ? 'Midday — صباحي'
                                  : 'Evening — مسائي',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: enabled
                                    ? Colors.black87
                                    : Colors.black54,
                              ),
                            ),
                            subtitle: Text(
                              'إغلاق: ${_fmt12(cfg['salesClose'])} • السحب: ${_fmt12(cfg['drawTime'])} • ${cfg['resultMode']}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.black54,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.edit,
                                size: 16,
                                color: Colors.deepPurple,
                              ),
                              onPressed: () => _editDrawConfig(cfg),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                      Card(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Colors.orange.withOpacity(0.15),
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(
                            Responsive.horizontalPadding(context),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.timer,
                                      color: Colors.orange,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Winning Number Entry',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          'Control when winning number can be entered',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _winningRestricted,
                                    activeColor: Colors.orange,
                                    onChanged: _toggleWinningRestricted,
                                  ),
                                ],
                              ),
                              const Divider(height: 12),
                              Text(
                                _winningRestricted
                                    ? 'Time-restricted: Entry only during [salesClose — drawTime+2h] window.'
                                    : 'Unrestricted: Winning number can be entered anytime. Period will close immediately after entry.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _winningRestricted
                                      ? Colors.black87
                                      : Colors.green.shade700,
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

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
