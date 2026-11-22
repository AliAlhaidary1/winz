import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../data/database.dart';
import '../utils/format.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/app_drawer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _cash = 0;
  double _balance = 0;
  List<Map<String, dynamic>> _pendingNotifs = [];
  List<Map<String, dynamic>> _customers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final db = context.read<AppDatabase>();
    final c = await app.computeCashBalance();
    final b = await app.computeGeneralBalance();
    List<Map<String, dynamic>> customers = [];
    try {
      customers = (await app.getCustomers())
          .where((cu) => !_isDefaultCustomer(cu))
          .toList();
    } catch (_) {}
    try {
      // Only the data shown on this page: cash, balance and pending results.
      final cfg = await db.getAppConfig();
      final wr = cfg
          .where((e) => e['key'] == 'winning_time_restricted')
          .firstOrNull;
      final restricted = wr == null ? true : wr['value'] == '1';
      List<Map<String, dynamic>> pending = [];
      if (restricted) {
        await db.seedDrawPeriods();
        await db.refreshPeriodStatuses();
        final periods = await db.getAllPeriods();
        final draws = await db.getAllDraws();
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        for (final d in draws) {
          final win = d['winningNumbers'] as String?;
          if (win != null && win.trim().isNotEmpty) continue;
          final dt = asInt(d['drawTime']);
          final name = d['name'] as String;
          final isMidday = name.contains('Midday') || name.contains('Morning');
          final type = isMidday ? 'MIDDAY' : 'EVENING';
          final drawDt = DateTime.fromMillisecondsSinceEpoch(dt);
          final dateStr =
              '${drawDt.year}-${drawDt.month.toString().padLeft(2, '0')}-${drawDt.day.toString().padLeft(2, '0')}';
          final pid = '$dateStr-$type';
          final p = periods.where((e) => e['id'] == pid).firstOrNull;
          if (p == null) continue;
          final sc = asInt(p['salesCloseTime']);
          final dr = asInt(p['drawTime']);
          if (nowMs >= sc && nowMs <= dr + 2 * 3600 * 1000) {
            pending.add(d);
          }
        }
      }
      if (mounted) {
        setState(() {
          _cash = c;
          _balance = b;
          _pendingNotifs = pending;
          _customers = customers;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cash = c;
          _balance = b;
          _customers = customers;
        });
      }
    }
  }

  bool _isDefaultCustomer(Map<String, dynamic> c) {
    final v = c['isDefault'];
    return c['id'] == AppState.defaultCustomerId || v == 1 || v == true;
  }

  Future<bool> _confirmExit() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: Responsive.dialogInsets(c),
        title: const Text('Exit App'),
        content: const Text('Do you want to exit the application?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return res == true;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _confirmExit();
        if (shouldExit && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        drawer: _buildDrawer(),
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          title: const Text('NY Lottery POS'),
          actions: [
            _userChip(user),
            IconButton(
              icon: const Icon(Icons.logout, size: 18),
              tooltip: 'Logout',
              onPressed: () => _confirmLogout(),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          color: AppTheme.green,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: Responsive.contentMaxWidth(context),
              ),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  Responsive.horizontalPadding(context),
                  24,
                  Responsive.horizontalPadding(context),
                  24,
                ),
                children: [
                  _greeting(user),
                  const SizedBox(height: 24),
                  _summaryStrip(),
                  const SizedBox(height: 24),
                  _primaryAction(),
                  const SizedBox(height: 20),
                  _customersStrip(),
                  const SizedBox(height: 20),
                  _quickAccess(),
                  const SizedBox(height: 28),
                  const Center(
                    child: Text(
                      'NY Lottery POS • 18+ Play Responsibly',
                      style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Compact account badge in the app bar. On the narrowest phones the
  /// centered title needs the space, so only the initial is shown there;
  /// the full username remains available in the drawer header.
  Widget _userChip(Map<String, dynamic>? user) {
    final username = user?['username']?.toString() ?? '';
    final initial = username.isEmpty ? 'U' : username[0];
    final avatar = CircleAvatar(
      radius: 12,
      backgroundColor: Colors.white,
      child: Text(
        initial.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppTheme.green,
        ),
      ),
    );
    if (MediaQuery.of(context).size.width < 393) {
      return Padding(padding: const EdgeInsets.only(right: 8), child: avatar);
    }
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.isDesktop(context) ? 140 : 84,
            ),
            child: Text(
              username,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _greeting(Map<String, dynamic>? user) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now();
    final date =
        '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
    final username = user?['username'] ?? 'Operator';
    return Row(
      children: [
        Expanded(
          child: Text(
            'مرحباً، $username  •  $date',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_pendingNotifs.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  size: 14,
                  color: AppTheme.orange,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_pendingNotifs.length} pending',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.orange,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _summaryStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: _summaryItem(
              icon: Icons.payments_outlined,
              label: 'Cash',
              value: fmtMoney(_cash),
              color: AppTheme.green,
            ),
          ),
          Container(width: 1, height: 34, color: AppTheme.cardBorder),
          Expanded(
            child: _summaryItem(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Balance',
              value: fmtMoney(_balance),
              color: AppTheme.blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _primaryAction() {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/numbers'),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        decoration: AppTheme.softGreenDecoration(),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.confirmation_number,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sell Ticket',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Numbers • Pick 3/4',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Customers strip (compact)
  // ---------------------------------------------------------------------------

  Widget _customersStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Customers / العملاء',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: _addCustomer,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.green,
                visualDensity: VisualDensity.compact,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '+ Add',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            itemCount: 1 + _customers.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              if (i == 0) {
                return _customerChip(
                  label: 'Cash / افتراضي',
                  isDefault: true,
                  onTap: () =>
                      _onCustomerTap(AppState.defaultCustomerId, 'Cash'),
                );
              }
              final c = _customers[i - 1];
              final id = '${c['id'] ?? ''}';
              final name = '${c['name'] ?? ''}';
              return _customerChip(
                label: name,
                isDefault: false,
                onTap: () => _onCustomerTap(id, name),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _customerChip({
    required String label,
    required bool isDefault,
    required VoidCallback onTap,
  }) {
    final color = isDefault ? AppTheme.green : AppTheme.textDark;
    // A horizontal ListView gives its children unbounded width. Cap each
    // chip so a very long (Arabic/English) customer name ellipsizes instead
    // of producing a chip wider than the screen.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width - 48,
      ),
      child: SizedBox(
        height: 34,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: isDefault ? AppTheme.greenSoft : Colors.white,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: isDefault
                    ? AppTheme.green.withValues(alpha: 0.35)
                    : AppTheme.cardBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isDefault ? Icons.person_outline : Icons.person,
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _snack(String message, {Color? background}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: background ?? AppTheme.green,
      ),
    );
  }

  String _numbersString(dynamic v) {
    if (v is List) return v.join(',');
    return '${v ?? ''}';
  }

  Future<void> _addCustomer() async {
    final app = context.read<AppState>();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: Responsive.dialogInsets(c),
        title: const Text('Add customer / إضافة عميل'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name / الاسم',
                  hintText: 'e.g. Ahmad / أحمد',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone / الهاتف',
                  hintText: 'Optional / اختياري',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel / إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Add / إضافة'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack(
        'Customer name is required / الاسم مطلوب',
        background: AppTheme.red,
      );
      return;
    }
    try {
      await app.addCustomer(name: name, phone: phoneCtrl.text.trim());
      await _load();
      _snack('Customer added / تمت الإضافة');
    } catch (e) {
      _snack('$e', background: AppTheme.red);
    }
  }

  Future<void> _onCustomerTap(String id, String name) async {
    final app = context.read<AppState>();
    List<Map<String, dynamic>> plays;
    try {
      plays = await app.getCustomerPlays(id);
    } catch (e) {
      _snack('$e', background: AppTheme.red);
      return;
    }
    if (!mounted) return;
    if (plays.isEmpty) {
      _snack('No saved plays — add from Customers');
      return;
    }

    Map<String, dynamic> play;
    if (plays.length == 1) {
      play = plays.first;
    } else {
      final chosen = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: Responsive.dialogInsets(c),
          title: Text('Saved plays / المحفوظة\n$name'),
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: Responsive.dialogContentMaxHeight(c),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: plays.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final p = plays[i];
                  return ListTile(
                    dense: true,
                    title: Text(
                      '${p['gameName'] ?? ''}  •  ${_numbersString(p['numbers'])}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${p['betType'] ?? ''}  •  ${fmtMoney(p['amount'])}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(c, p),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel / إلغاء'),
            ),
          ],
        ),
      );
      if (chosen == null || !mounted) return;
      play = chosen;
    }
    await _openPlay(id, name, play);
  }

  Future<void> _openPlay(String id, String name, Map<String, dynamic> p) async {
    final app = context.read<AppState>();
    try {
      await app.selectCustomer(id);
    } catch (e) {
      _snack('$e', background: AppTheme.red);
      return;
    }
    if (!mounted) return;
    final gameId = '${p['gameId'] ?? ''}';
    final route = gameId == 'g_winz' ? '/winz' : '/numbers';
    Navigator.pushNamed(
      context,
      route,
      arguments: {
        'customerId': id,
        'customerName': name,
        'numbers': _numbersString(p['numbers']),
        'betType': '${p['betType'] ?? ''}',
        'amount': p['amount'],
        'gameId': gameId,
        'drawType': '${p['drawType'] ?? ''}',
      },
    );
  }

  Widget _quickAccess() {
    final tiles = [
      (Icons.verified, 'Check Winner', const Color(0xFF2E7D32), '/winning'),
      (
        Icons.confirmation_number,
        'Tickets',
        const Color(0xFF9C27B0),
        '/tickets',
      ),
      (Icons.account_balance, 'Cash', const Color(0xFF795548), '/cash'),
      (Icons.assessment, 'Report', const Color(0xFFE91E63), '/report'),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        // 2 columns on phones, 3 on tablets (600-1023) and 4 on desktop:
        // 4 across a 600px tablet made the tiles cramped and clipped labels.
        crossAxisCount: Responsive.gridCrossAxisCount(context),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.35,
      ),
      itemCount: tiles.length,
      itemBuilder: (ctx, i) {
        final t = tiles[i];
        return _quickTile(icon: t.$1, label: t.$2, color: t.$3, route: t.$4);
      },
    );
  }

  Widget _quickTile({
    required IconData icon,
    required String label,
    required Color color,
    required String route,
  }) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, route),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: AppTheme.cardDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() => const AppDrawer(currentRoute: '/home');

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: Responsive.dialogInsets(c),
        title: const Text('Logout'),
        content: const Text('End your session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () {
              context.read<AppState>().logout();
              Navigator.pop(c);
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (_) => false,
              );
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
