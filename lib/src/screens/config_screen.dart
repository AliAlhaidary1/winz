import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../utils/responsive.dart';
import 'settings/draw_settings_screen.dart';
import 'settings/prize_settings_screen.dart';
import 'settings/general_settings_screen.dart';
import 'settings/backup_settings_screen.dart';
import 'workers_screen.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  List<Map<String, dynamic>> _configs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final c = await db.getAppConfig();
    if (!mounted) return;
    setState(() {
      _configs = c;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF0B8A3E);
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF6F8F6),
        appBar: AppBar(
          backgroundColor: green,
          foregroundColor: Colors.white,
          title: const Text('Settings'),
        ),
        body: const Center(child: CircularProgressIndicator(color: green)),
      );
    }
    final drawCount = _configs
        .where(
          (e) =>
              (e['key'] as String).contains('midday') ||
              (e['key'] as String).contains('evening') ||
              (e['key'] as String).contains('draw_'),
        )
        .length;
    final prizeCount = _configs
        .where(
          (e) =>
              (e['key'] as String).contains('numbers') ||
              (e['key'] as String).contains('win4') ||
              (e['key'] as String).contains('straight') ||
              (e['key'] as String).contains('box'),
        )
        .length;
    final backupCount = _configs
        .where((e) => (e['key'] as String).contains('backup'))
        .length;
    final generalCount = _configs.length - drawCount - prizeCount - backupCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        backgroundColor: green,
        foregroundColor: Colors.white,
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Manage your store',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: Responsive.gridCrossAxisCount(
                    context,
                    mobile: 2,
                    tablet: 2,
                    desktop: 4,
                  ),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio:
                      Responsive.isTablet(context) ||
                          Responsive.isDesktop(context)
                      ? 1.1
                      : 0.70,
                  children: [
                    _hubCard(
                      context,
                      icon: Icons.people,
                      color: Colors.blue,
                      title: 'Users',
                      subtitle: 'Manage workers',
                      count: 'Workers',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const WorkersScreen(),
                        ),
                      ),
                    ),
                    _hubCard(
                      context,
                      icon: Icons.schedule,
                      color: Colors.deepPurple,
                      title: 'Draw Schedule',
                      subtitle: 'Times & winning rules',
                      count: '$drawCount items',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DrawSettingsScreen(),
                        ),
                      ),
                    ),
                    _hubCard(
                      context,
                      icon: Icons.card_giftcard,
                      color: green,
                      title: 'Prize Settings',
                      subtitle: 'NY prizes',
                      count: '$prizeCount items',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PrizeSettingsScreen(),
                        ),
                      ),
                    ),
                    _hubCard(
                      context,
                      icon: Icons.settings,
                      color: Colors.orange,
                      title: 'General',
                      subtitle: 'Company, printer & customer %',
                      count: '$generalCount items',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GeneralSettingsScreen(),
                        ),
                      ),
                    ),
                    _hubCard(
                      context,
                      icon: Icons.backup,
                      color: Colors.teal,
                      title: 'Backup',
                      subtitle: 'Backup copies',
                      count:
                          (_configs.any(
                                (e) =>
                                    e['key'] == 'backup_enabled' &&
                                    e['value'] == '0',
                              ) ||
                              _configs.any(
                                (e) =>
                                    e['key'] == 'backup_interval' &&
                                    e['value'] == 'never',
                              ))
                          ? 'Off'
                          : 'Auto + manual',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BackupSettingsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  color: const Color(0xFFE6F4EA),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(
                      Responsive.horizontalPadding(context),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: green, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Tap a category to manage its settings. Changes apply instantly.',
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

  Widget _hubCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String count,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                count,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: color.withOpacity(0.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
