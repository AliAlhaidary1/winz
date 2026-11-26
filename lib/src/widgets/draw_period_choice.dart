import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

/// Ask which draw period to use when copying (replaying) a previous ticket.
///
/// Choices:
///  * `MIDDAY` — force every play to the next open Midday draw.
///  * `EVENING` — force every play to the next open Evening draw.
///  * `AUTO` — "The same": keep each play's original period, so a ticket that
///    mixes Morning / Evening / Both is copied exactly as it was played.
Future<String?> showDrawPeriodChoice(
  BuildContext context, {
  bool arabic = false,
}) async {
  final app = context.read<AppState>();
  // Always show the choice dialog. A failed/closed check must never hide it.
  bool morningOpen = false;
  bool eveningOpen = false;
  try {
    morningOpen = await app.isDrawTypeSellableNow('MIDDAY');
  } catch (_) {}
  try {
    eveningOpen = await app.isDrawTypeSellableNow('EVENING');
  } catch (_) {}

  // Cross-check with the actual open periods. The state helper can report
  // false on a stale/failed session; the period list is authoritative.
  try {
    final periods = await context.read<AppDatabase>().getOpenPeriods();
    for (final p in periods) {
      final type = (p['drawType'] ?? p['id'] ?? '').toString().toUpperCase();
      if (type.contains('MIDDAY') || type.contains('MORNING')) {
        morningOpen = true;
      } else if (type.contains('EVENING')) {
        eveningOpen = true;
      }
    }
  } catch (_) {}
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text(
        'Copy — choose period',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            morningOpen && eveningOpen
                ? 'The same keeps every number in its original period.'
                : 'A closed draw has its button disabled. "The same" needs both draws open.',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: Icon(
              Icons.wb_sunny,
              size: 16,
              color: morningOpen ? const Color(0xFF0B8A3E) : Colors.grey,
            ),
            label: Text(
              'Morning only',
              style: TextStyle(
                fontSize: 12,
                color: morningOpen ? const Color(0xFF0B8A3E) : Colors.grey,
              ),
            ),
            onPressed: morningOpen ? () => Navigator.pop(c, 'MIDDAY') : null,
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            icon: Icon(
              Icons.nights_stay,
              size: 16,
              color: eveningOpen ? AppTheme.blue : Colors.grey,
            ),
            label: Text(
              'Evening only',
              style: TextStyle(
                fontSize: 12,
                color: eveningOpen ? AppTheme.blue : Colors.grey,
              ),
            ),
            onPressed: eveningOpen ? () => Navigator.pop(c, 'EVENING') : null,
          ),
          const SizedBox(height: 6),
          ElevatedButton.icon(
            icon: const Icon(Icons.content_copy, size: 16),
            label: const Text('The same', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0B8A3E),
              foregroundColor: Colors.white,
            ),
            onPressed: morningOpen && eveningOpen
                ? () => Navigator.pop(c, 'AUTO')
                : null,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}
