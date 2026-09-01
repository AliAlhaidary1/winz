import 'dart:async';
import 'package:flutter/material.dart';
import '../services/draw_period_service.dart';
import '../data/database.dart';
import 'package:provider/provider.dart';

class DrawCountdown extends StatefulWidget {
  final String periodId;
  const DrawCountdown({super.key, required this.periodId});
  @override
  State<DrawCountdown> createState() => _DrawCountdownState();
}

class _DrawCountdownState extends State<DrawCountdown> {
  Timer? _timer;
  String _display = '--:--:--';
  String _status = 'LOADING';
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant DrawCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.periodId != widget.periodId) _tick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    try {
      final db = context.read<AppDatabase>();
      final svc = DrawPeriodService(db);
      final c = await svc.getCountdownForPeriod(widget.periodId);
      if (!mounted) return;
      setState(() {
        _display = c?['display'] ?? '--';
        _status = c?['status'] ?? '--';
        _isOpen = _status == 'OPEN';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _display = '--');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _isOpen ? const Color(0xFFE8F5E9) : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _isOpen ? const Color(0xFF0B8A3E).withOpacity(0.2) : Colors.red.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_isOpen ? Icons.timer_outlined : Icons.block, size: 14, color: _isOpen ? const Color(0xFF0B8A3E) : Colors.red),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_isOpen ? 'Sales close in:' : _status, style: TextStyle(fontSize: 9, color: _isOpen ? const Color(0xFF0B8A3E) : Colors.red, fontWeight: FontWeight.bold)),
          Text(_display, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _isOpen ? const Color(0xFF0B8A3E) : Colors.red)),
        ]),
      ]),
    );
  }
}
