import 'package:flutter/material.dart';

class LotteryScreen extends StatelessWidget {
  const LotteryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lottery'), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Choose a game', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          _gameCard(context, title: 'Numbers', subtitle: 'Pick 3 / Pick 4 — keypad 0-9', icon: Icons.grid_on, color: Colors.indigo, route: '/numbers', details: r'Straight / Box / Combo / StrBox / Pairs • $0.50 - $10.00 • Midday 2:30 / Evening 10:30'),
          const SizedBox(height: 12),
          _gameCard(context, title: 'Win 4', subtitle: 'Pick 4 — 4 digits 0-9', icon: Icons.emoji_events, color: Colors.orange, route: '/winz', details: r'4 digits • Straight/Box/Combo • $0.50 - $10.00 • Midday/Evening'),
        ]),
      ),
    );
  }

  Widget _gameCard(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color color, required String route, required String details}) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, route),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(radius: 28, backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color, size: 28)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              const SizedBox(height: 4),
              Text(details, style: const TextStyle(fontSize: 10, color: Colors.black45)),
            ])),
            const Icon(Icons.arrow_forward_ios, size: 14),
          ]),
        ),
      ),
    );
  }
}
