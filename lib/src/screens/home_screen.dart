import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../data/database.dart';
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
  List<Map<String,dynamic>> _pendingNotifs = [];
  bool _winningRestricted = true;
  int _playsToday = 0;
  int _winnersToday = 0;
  double _winRate = 0;
  double _workerCommission = 0;
  double _workerRate = 5.0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final db = context.read<AppDatabase>();
    final c = await app.computeCashBalance();
    final b = await app.computeGeneralBalance();
    try{
      final cfg = await db.getAppConfig();
      final wr = cfg.where((e)=> e['key']=='winning_time_restricted').firstOrNull;
      final restricted = wr==null ? true : wr['value']=='1';
      List<Map<String,dynamic>> pending = [];
      if(restricted){
        await db.seedDrawPeriods();
        await db.refreshPeriodStatuses();
        final periods = await db.getAllPeriods();
        final draws = await db.getAllDraws();
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        for(final d in draws){
          final win = d['winningNumbers'] as String?;
          if(win!=null && win.trim().isNotEmpty) continue;
          final dt = d['drawTime'] as int;
          final name = d['name'] as String;
          final isMidday = name.contains('Midday')||name.contains('Morning');
          final type = isMidday ? 'MIDDAY' : 'EVENING';
          final drawDt = DateTime.fromMillisecondsSinceEpoch(dt);
          final dateStr = '${drawDt.year}-${drawDt.month.toString().padLeft(2,'0')}-${drawDt.day.toString().padLeft(2,'0')}';
          final pid = '$dateStr-$type';
          final p = periods.where((e)=> e['id']==pid).firstOrNull;
          if(p==null) continue;
          final sc = p['salesCloseTime'] as int;
          final dr = p['drawTime'] as int;
          if(nowMs >= sc && nowMs <= dr + 2*3600*1000){
            pending.add(d);
          }
        }
      }
      final now2 = DateTime.now();
      final todayStart = DateTime(now2.year, now2.month, now2.day).millisecondsSinceEpoch;
      final todayEnd = DateTime(now2.year, now2.month, now2.day, 23,59,59,999).millisecondsSinceEpoch;
      final allTickets = await db.getTickets();
      final todayTickets = allTickets.where((t)=> (t['createdAt'] as int) >= todayStart && (t['createdAt'] as int) <= todayEnd).toList();
      final playsToday = todayTickets.length;
      final winnersToday = todayTickets.where((t)=> t['status']=='winning' || t['status']=='paid').length;
      final winRate = playsToday>0 ? (winnersToday/playsToday*100) : 0.0;
      double workerRate = 5.0;
      double workerCommission = 0;
      final curUser = app.currentUser;
      if(curUser != null){
        final comm = curUser['commission'];
        if(comm != null) workerRate = (comm as num).toDouble();
        else {
          final acc = await db.findAccount(curUser['username'], curUser['password']);
          if(acc != null && acc['commission'] != null) workerRate = (acc['commission'] as num).toDouble();
        }
        final salesToday = todayTickets.fold<double>(0, (s,e)=> s + (e['total'] as num).toDouble());
        workerCommission = salesToday * workerRate / 100;
      }
      if (mounted) setState(() { _cash = c; _balance = b; _pendingNotifs = pending; _winningRestricted = restricted; _playsToday = playsToday; _winnersToday = winnersToday; _winRate = winRate; _workerCommission = workerCommission; _workerRate = workerRate; });
    }catch(_){
      if (mounted) setState(() { _cash = c; _balance = b; });
    }
  }

  Future<bool> _confirmExit() async {
    final res = await showDialog<bool>(context: context, builder: (c)=> AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Exit App'),
      content: const Text('Do you want to exit the application?'),
      actions: [TextButton(onPressed: ()=> Navigator.pop(c,false), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(backgroundColor: AppTheme.red), onPressed: ()=> Navigator.pop(c,true), child: const Text('Exit'))],
    ));
    return res==true;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    final isAdmin = user?['role'] == 'admin';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if(didPop) return;
        final shouldExit = await _confirmExit();
        if(shouldExit && context.mounted){
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      drawer: _buildDrawer(),
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('NY Lottery POS'),
        actions: [
          Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)), child: Row(children: [CircleAvatar(radius: 12, backgroundColor: Colors.white, child: Text((user?['username']?[0] ?? 'U').toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.green))), const SizedBox(width: 6), Text(user?['username'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))])),
          IconButton(icon: const Icon(Icons.logout, size: 18), tooltip: 'Logout', onPressed: () => _confirmLogout()),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.green,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: Responsive.contentMaxWidth(context)),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(Responsive.horizontalPadding(context), 14, Responsive.horizontalPadding(context), 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Today's small stats
                GridView.count(
                  crossAxisCount: Responsive.isDesktop(context) ? 4 : 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: Responsive.isTablet(context) || Responsive.isDesktop(context) ? 2.2 : 1.9,
                  children: [
                    _smallStat('Plays Today', '$_playsToday', Icons.confirmation_number, AppTheme.green),
                    _smallStat('Winners Today', '$_winnersToday', Icons.emoji_events, Colors.orange),
                    _smallStat('Win Rate', '${_winRate.toStringAsFixed(1)}%', Icons.percent, Colors.purple),
                    _smallStat('Commission ${_workerRate.toStringAsFixed(1)}%', '\$${_workerCommission.toStringAsFixed(2)}', Icons.account_balance_wallet, Colors.teal),
                  ],
                ),
                if(isAdmin) Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Align(alignment: Alignment.centerRight, child: TextButton.icon(icon: const Icon(Icons.people, size: 14), label: const Text('Manage Workers', style: TextStyle(fontSize: 11)), onPressed: ()=> Navigator.pushNamed(context, '/workers'))),
                ),
                const SizedBox(height: 14),
                // Stats
                LayoutBuilder(builder: (ctx, c) {
                  final narrow = c.maxWidth < 380;
                  if (narrow) {
                    return Column(children: [
                      _stat('Cash in Drawer', _cash, Icons.payments, AppTheme.green, 'After sales & payouts'),
                      const SizedBox(height: 10),
                      _stat('Balance', _balance, Icons.account_balance_wallet, AppTheme.blue, 'Sales - Prizes'),
                    ]);
                  }
                  return Row(children: [
                    Expanded(child: _stat('Cash in Drawer', _cash, Icons.payments, AppTheme.green, 'After sales & payouts')),
                    const SizedBox(width: 10),
                    Expanded(child: _stat('Balance', _balance, Icons.account_balance_wallet, AppTheme.blue, 'Sales - Prizes')),
                  ]);
                }),
                const SizedBox(height: 16),
                const Text('Quick Actions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 10),
                _actionGrid(),
                const SizedBox(height: 8),
                _categorySection('Play', [
                  (Icons.casino, 'Lottery', const Color(0xFF6C5CE7), '/lottery'),
                  (Icons.numbers, 'Numbers', AppTheme.green, '/numbers'),
                ]),
                _categorySection('Tickets & Sales', [
                  (Icons.point_of_sale, 'Sales', const Color(0xFF009688), '/sales'),
                  (Icons.confirmation_number, 'Tickets', const Color(0xFF9C27B0), '/tickets'),
                  (Icons.verified, 'Winner', const Color(0xFF2E7D32), '/winning'),
                  (Icons.admin_panel_settings, 'Draw', AppTheme.green, '/admin/draw'),
                ]),
                _categorySection('Finance', [
                  (Icons.account_balance, 'Cash', const Color(0xFF795548), '/cash'),
                  (Icons.account_balance_wallet, 'Balance', AppTheme.blue, '/balance'),
                  (Icons.assessment, 'Report', const Color(0xFFE91E63), '/report'),
                  (Icons.print, 'Print', const Color(0xFFFF8F00), '/print'),
                ]),
                _categorySection('System', [
                  (Icons.share, 'Share', const Color(0xFF33691E), '/share'),
                  (Icons.help_outline, 'Help', const Color(0xFF78909C), '/help'),
                  (Icons.settings, 'Config', const Color(0xFF37474F), '/config'),
                  if (isAdmin) (Icons.people, 'Workers', Colors.blue, '/workers'),
                ]),
                const SizedBox(height: 16),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.settings, size: 16), label: const Text('Settings'), onPressed: () => Navigator.pushNamed(context, '/config'))),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.logout, size: 16), label: const Text('Logout'), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red), onPressed: () => _confirmLogout())),
                ]),
                const SizedBox(height: 10),
                const Center(child: Text('NY Lottery POS • Official Clone • 18+ Play Responsibly', style: TextStyle(fontSize: 10, color: AppTheme.textMuted))),
              ]),
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _smallStat(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.cardDecoration(),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 16)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w600)), Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color))])),
      ]),
    );
  }

  Widget _buildDrawer() => const AppDrawer(currentRoute: '/home');

  Widget _stat(String label, double value, IconData icon, Color color, String hint) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 16)),
          const Spacer(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)), child: Row(children: [Icon(Icons.trending_up, size: 12, color: color), const SizedBox(width: 4), Text('Live', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold))])),
        ]),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
        Text(hint, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
        const SizedBox(height: 6),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('\$${value.toStringAsFixed(2)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color))),
      ]),
    );
  }

  Widget _actionGrid() {
    return Column(children: [
      Row(children: [
        Expanded(child: _actionCard(icon: Icons.confirmation_number, title: 'Sell Ticket', subtitle: 'Numbers', color: AppTheme.green, onTap: () => Navigator.pushNamed(context, '/numbers'))),
        const SizedBox(width: 10),
        Expanded(child: _actionCard(icon: Icons.verified, title: 'Check Winner', subtitle: 'Scan & pay', color: AppTheme.blue, onTap: () => Navigator.pushNamed(context, '/winning'))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _actionCard(icon: Icons.receipt_long, title: 'Tickets', subtitle: 'History & reprint', color: Color(0xFF6A1B9A), onTap: () => Navigator.pushNamed(context, '/tickets'))),
        const SizedBox(width: 10),
        Expanded(child: _actionCard(icon: Icons.admin_panel_settings, title: 'Draw Result', subtitle: 'Admin only', color: Color(0xFF00695C), onTap: () => Navigator.pushNamed(context, '/admin/draw'))),
      ]),
    ]);
  }

  Widget _actionCard({required IconData icon, required String title, required String subtitle, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.cardDecoration(borderColor: color.withValues(alpha: 0.12)),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: Colors.white, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)), Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted))])),
          const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.black26),
        ]),
      ),
    );
  }

  Widget _categorySection(String title, List<(IconData, String, Color, String)> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 6), child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54))),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: Responsive.gridCrossAxisCount(context, mobile: 3, tablet: 4, desktop: 4),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: Responsive.isTablet(context) || Responsive.isDesktop(context) ? 1.15 : 1.05,
        ),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final e = items[i];
          return InkWell(
            onTap: () => Navigator.pushNamed(context, e.$4),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: AppTheme.cardDecoration(),
              padding: const EdgeInsets.all(8),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: e.$3, shape: BoxShape.circle), child: Icon(e.$1, color: Colors.white, size: 16)),
                const SizedBox(height: 6),
                Text(e.$2, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          );
        },
      ),
      const SizedBox(height: 10),
    ]);
  }

  Widget _opsGrid() {
    return LayoutBuilder(builder: (ctx, c) {
      int cross = Responsive.gridCrossAxisCount(context, mobile: 3, tablet: 4, desktop: 4);
      if (c.maxWidth < 340) cross = 2;
      else if (c.maxWidth >= 720 && !Responsive.isDesktop(context)) cross = 4;
      final items = [
        (Icons.casino, 'Lottery', Color(0xFF6C5CE7), '/lottery'),
        (Icons.numbers, 'Numbers', AppTheme.green, '/numbers'),
        (Icons.point_of_sale, 'Sales', Color(0xFF009688), '/sales'),
        (Icons.confirmation_number, 'Tickets', Color(0xFF9C27B0), '/tickets'),
        (Icons.verified, 'Winner', Color(0xFF2E7D32), '/winning'),
        (Icons.account_balance, 'Cash', Color(0xFF795548), '/cash'),
        (Icons.account_balance_wallet, 'Balance', AppTheme.blue, '/balance'),
        (Icons.print, 'Print', Color(0xFFFF8F00), '/print'),
        (Icons.assessment, 'Report', Color(0xFFE91E63), '/report'),
        (Icons.share, 'Share', Color(0xFF33691E), '/share'),
        (Icons.help_outline, 'Help', Color(0xFF78909C), '/help'),
        (Icons.settings, 'Config', Color(0xFF37474F), '/config'),
        (Icons.admin_panel_settings, 'Draw', AppTheme.green, '/admin/draw'),
      ];
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cross, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.05),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final e = items[i];
          return InkWell(
            onTap: () => Navigator.pushNamed(context, e.$4),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: AppTheme.cardDecoration(),
              padding: const EdgeInsets.all(12),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: e.$3, shape: BoxShape.circle), child: Icon(e.$1, color: Colors.white, size: 18)),
                const SizedBox(height: 8),
                Text(e.$2, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
              ]),
            ),
          );
        },
      );
    });
  }

  void _confirmLogout() {
    showDialog(context: context, builder: (c)=> AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Logout'),
      content: const Text('End your session?'),
      actions: [TextButton(onPressed: ()=> Navigator.pop(c), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(backgroundColor: AppTheme.red), onPressed: (){ context.read<AppState>().logout(); Navigator.pop(c); Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false); }, child: const Text('Logout'))],
    ));
  }
}
