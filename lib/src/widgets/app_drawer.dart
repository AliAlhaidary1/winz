import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

class AppDrawer extends StatelessWidget {
  final String currentRoute;
  const AppDrawer({super.key, this.currentRoute = ''});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    final isAdmin = user?['role'] == 'admin';
    return Drawer(
      child: ListView(padding: EdgeInsets.zero, children: [
        DrawerHeader(
          decoration: BoxDecoration(gradient: LinearGradient(colors: [AppTheme.green, AppTheme.greenDark])),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.storefront, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            const Text('NY Lottery POS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            Text('${user?['username'] ?? ''} • ${user?['role'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)), child: Text('All operations available here', style: const TextStyle(color: Colors.white, fontSize: 10))),
          ]),
        ),
        // Quick Actions - same as Home
        const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('Quick Actions', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54))),
        ListTile(leading: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: AppTheme.green, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.confirmation_number, color: Colors.white, size: 16)), title: const Text('Sell Ticket', style: TextStyle(fontSize: 13)), subtitle: const Text('Numbers', style: TextStyle(fontSize: 11)), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/numbers'); }),
        ListTile(leading: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: AppTheme.blue, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.verified, color: Colors.white, size: 16)), title: const Text('Check Winner', style: TextStyle(fontSize: 13)), subtitle: const Text('Scan & pay', style: TextStyle(fontSize: 11)), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/winning'); }),
        ListTile(leading: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFF6A1B9A), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.receipt_long, color: Colors.white, size: 16)), title: const Text('Tickets', style: TextStyle(fontSize: 13)), subtitle: const Text('History & reprint', style: TextStyle(fontSize: 11)), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/tickets'); }),
        ListTile(leading: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFF00695C), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 16)), title: const Text('Draw Result', style: TextStyle(fontSize: 13)), subtitle: const Text('Admin only', style: TextStyle(fontSize: 11)), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/admin/draw'); }),
        const Divider(),
        const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('All Operations', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54))),
        ListTile(leading: const Icon(Icons.casino, color: Color(0xFF6C5CE7)), title: const Text('Lottery'), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/lottery'); }),
        ListTile(leading: const Icon(Icons.numbers, color: AppTheme.green), title: const Text('Numbers'), subtitle: const Text('3-Digit & 4-Digit', style: TextStyle(fontSize: 11)), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/numbers'); }),
        ListTile(leading: const Icon(Icons.point_of_sale, color: Color(0xFF009688)), title: const Text('Sales'), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/sales'); }),
        ListTile(leading: const Icon(Icons.confirmation_number, color: Color(0xFF9C27B0)), title: const Text('Tickets'), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/tickets'); }),
        ListTile(leading: const Icon(Icons.verified, color: Color(0xFF2E7D32)), title: const Text('Winner'), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/winning'); }),
        ListTile(leading: const Icon(Icons.account_balance, color: Color(0xFF795548)), title: const Text('Cash'), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/cash'); }),
        ListTile(leading: const Icon(Icons.account_balance_wallet, color: AppTheme.blue), title: const Text('Balance'), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/balance'); }),
        ListTile(leading: const Icon(Icons.print, color: Color(0xFFFF8F00)), title: const Text('Print'), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/print'); }),
        ListTile(leading: const Icon(Icons.assessment, color: Color(0xFFE91E63)), title: const Text('Report'), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/report'); }),
        ListTile(leading: const Icon(Icons.share, color: Color(0xFF33691E)), title: const Text('Share'), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/share'); }),
        ListTile(leading: const Icon(Icons.help_outline, color: Color(0xFF78909C)), title: const Text('Help'), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/help'); }),
        ListTile(leading: const Icon(Icons.settings, color: Color(0xFF37474F)), title: const Text('Config'), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/config'); }),
        ListTile(leading: const Icon(Icons.admin_panel_settings, color: AppTheme.green), title: const Text('Draw'), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/admin/draw'); }),
        const Divider(),
        if (isAdmin) ListTile(leading: const Icon(Icons.people, color: Colors.blue), title: const Text('Workers'), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/workers'); }),
        ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Logout', style: TextStyle(color: Colors.red)), onTap: () { context.read<AppState>().logout(); Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false); }),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.all(12), child: Text('NY Lottery POS • 18+ Play Responsibly', style: TextStyle(fontSize: 10, color: Colors.grey.shade500), textAlign: TextAlign.center)),
      ]),
    );
  }
}
