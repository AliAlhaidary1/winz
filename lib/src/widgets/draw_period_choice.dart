import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../theme/app_theme.dart';

Future<String?> showDrawPeriodChoice(
  BuildContext context, {
  bool arabic = false,
}) async {
  final app = context.read<AppState>();
  final morningOpen = await app.isDrawTypeSellableNow('MIDDAY');
  final eveningOpen = await app.isDrawTypeSellableNow('EVENING');
  final bothOpen = morningOpen && eveningOpen;
  if (!context.mounted) return null;
  if (!morningOpen && !eveningOpen) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('No open period to play now'),
        backgroundColor: Colors.red,
      ),
    );
    return null;
  }
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text(
        'When do you want to play?',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'A closed period cannot be selected. If Morning has ended you can play Evening only.',
            style: TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: Icon(
              Icons.wb_sunny,
              size: 16,
              color: morningOpen ? const Color(0xFF0B8A3E) : Colors.grey,
            ),
            label: Text(
              'Morning — 14:30',
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
              'Evening — 22:30',
              style: TextStyle(
                fontSize: 12,
                color: eveningOpen ? AppTheme.blue : Colors.grey,
              ),
            ),
            onPressed: eveningOpen ? () => Navigator.pop(c, 'EVENING') : null,
          ),
          const SizedBox(height: 6),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy_all, size: 16),
            label: const Text(
              'Both periods — two copies',
              style: TextStyle(fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: bothOpen ? const Color(0xFF0B8A3E) : Colors.grey,
              foregroundColor: Colors.white,
            ),
            onPressed: bothOpen ? () => Navigator.pop(c, 'BOTH') : null,
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
