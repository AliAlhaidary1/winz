import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _cash = 0;
  double _balance = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final c = await app.computeCashBalance();
    final b = await app.computeGeneralBalance();
    if (mounted) setState(() { _cash = c; _balance = b; });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    final isAdmin = user?['role'] == 'admin';
    return Scaffold(
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
            constraints: const BoxConstraints(maxWidth: 960),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Admin hero gradient
                if (isAdmin)
                  Container(
                    decoration: AppTheme.softGreenDecoration(),
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.emoji_events, color: AppTheme.green, size: 26)),
                      const SizedBox(width: 14),
                      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Admin • Draw Result', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                        SizedBox(height: 3),
                        Text('Set winning numbers for Midday / Evening / Night draws', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ])),
                      FilledButton( onPressed: null, style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(Colors.white), foregroundColor: WidgetStatePropertyAll(AppTheme.green)), child: Text('Open')),
                    ]),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.cardBorder)),
                    child: Row(children: [
                      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.shield_outlined, color: AppTheme.orange, size: 18)),
                      const SizedBox(width: 10),
                      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Admin controls draws', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), Text('Login as admin / admin123 to set winners', style: TextStyle(fontSize: 11, color: AppTheme.textMuted))])),
                      TextButton(onPressed: () => Navigator.pushNamed(context, '/admin/draw'), child: const Text('View')),
                    ]),
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
                const SizedBox(height: 16),
                const Text('All Operations', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 10),
                _opsGrid(),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppTheme.greenLight, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.green.withValues(alpha: 0.15))),
                  child: Row(children: [
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.green, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.lightbulb, color: Colors.white, size: 16)),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('How to set winner?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), Text('Admin → Draw Result → choose Midday/Evening/Night → enter 123 or 0123 → Save', style: TextStyle(fontSize: 11, color: AppTheme.textMuted))])),
                    FilledButton(onPressed: null, style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(AppTheme.green)), child: Text('Go')),
                  ]),
                ),
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
    );
  }

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
        Expanded(child: _actionCard(icon: Icons.confirmation_number, title: 'Sell Ticket', subtitle: 'Numbers / Win 4', color: AppTheme.green, onTap: () => Navigator.pushNamed(context, '/numbers'))),
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

  Widget _opsGrid() {
    return LayoutBuilder(builder: (ctx, c) {
      int cross = 3;
      if (c.maxWidth < 340) cross = 2;
      else if (c.maxWidth >= 720) cross = 4;
      final items = [
        (Icons.casino, 'Lottery', Color(0xFF6C5CE7), '/lottery'),
        (Icons.numbers, 'Numbers', AppTheme.green, '/numbers'),
        (Icons.emoji_events, 'Win 4', AppTheme.orange, '/winz'),
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
