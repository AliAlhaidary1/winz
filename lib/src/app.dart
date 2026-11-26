import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/database.dart';
import 'providers/app_state.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lottery_screen.dart';
import 'screens/numbers_screen.dart';
import 'screens/winz_screen.dart';
import 'screens/play_screen.dart';
import 'screens/admin_draw_screen.dart';
import 'screens/sales_screen.dart';
import 'screens/tickets_screen.dart';
import 'screens/ticket_detail_screen.dart';
import 'screens/winning_tickets_screen.dart';
import 'screens/cash_screen.dart';
import 'screens/balance_screen.dart';
import 'screens/print_screen.dart';
import 'screens/report_screen.dart';
import 'screens/share_screen.dart';
import 'screens/help_screen.dart';
import 'screens/change_credentials_screen.dart';
import 'screens/config_screen.dart';
import 'screens/workers_screen.dart';
import 'screens/customers_screen.dart';

class YeLotteryApp extends StatelessWidget {
  final AppDatabase db;
  const YeLotteryApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider(create: (_) => AppState(db)),
      ],
      child: MaterialApp(
        title: 'Winz POS Pro',
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        theme: AppTheme.light(),
        initialRoute: '/login',
        routes: {
          '/login': (_) => const LoginScreen(),
          '/play': (_) => const PlayScreen(),
          // drawId is a draw identifier, not a game id — the screen sets its
          // own default game internally.
          '/admin/draw': (_) => const AdminDrawScreen(drawId: ''),
          '/home': (_) => const HomeScreen(),
          '/lottery': (_) => const LotteryScreen(),
          '/numbers': (_) => const NumbersScreen(),
          '/winz': (_) => const WinzScreen(),
          '/sales': (_) => const SalesScreen(),
          '/tickets': (_) => const TicketsScreen(),
          '/winning': (_) => const WinningTicketsScreen(),
          '/cash': (_) => const CashScreen(),
          '/balance': (_) => const BalanceScreen(),
          '/print': (_) => const PrintScreen(),
          '/report': (_) => const ReportScreen(),
          '/share': (_) => const ShareScreen(),
          '/help': (_) => const HelpScreen(),
          '/config': (_) => const ConfigScreen(),
          '/change_credentials': (_) => const ChangeCredentialsScreen(),
          '/workers': (_) => const WorkersScreen(),
          '/customers': (_) => const CustomersScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/ticket_detail') {
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              builder: (_) => TicketDetailScreen(ticket: args ?? const {}),
              settings: settings,
            );
          }
          return null;
        },
      ),
    );
  }
}
