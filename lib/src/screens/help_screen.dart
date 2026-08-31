import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help'), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        _card('How to Play — Numbers (Pick 3 / 4)', [
          'Select Midday/Evening draw, choose Straight/Box/Combo/StraightBox/Front or Back Pair.',
          'Enter exactly 3 or 4 digits using 0-9 keypad (NY Lottery — 0 allowed).',
          r'Enter wager $0.50 - $10.00 (Combo cost = combos×wager, must be $0.50 steps) and confirm.',
          'Straight needs exact order. Box accepts any order. Sales close 5 min before draw.',
          'Tickets include draw, numbers, wager, barcode and QR code.',
        ]),
        _card('How to Play — Win 4 (Winz)', [
          'Select Midday/Evening Win 4 draw — exactly 4 digits 0-9.',
          'Types: Straight/Box/Combo/StraightBox (legacy Winz-Std etc still supported).',
          r'Wager $0.50 - $10.00 and confirm. Combo cost validated.',
        ]),
        _card('Tickets', [
          'Each sale creates a ticket with ID, serial and barcode. Present ticket for validation.',
          'Reprint available from Ticket Detail.',
        ]),
        _card('Validation & Payout', [
          'Use Winning Tickets to scan or enter Ticket ID/Barcode after admin sets winning number.',
          'Straight pays only exact order (e.g. 123 ≠ 321). Box/Combo pay any order. Prize = amount × multiplier (500/160/80 etc).',
          'Replacement of winning number correctly demotes previous winners to losing.',
          'Pay once — duplicate payout is blocked. Session 8h expiry enforced.',
        ]),
        _card('Cash & Reports — NY Accounting', [
          'Cash = physical (per operator). Balance = sales - payouts (per operator + global report).',
          'Every sale → Cash in + Balance credit. Every payout → Cash out + Balance debit.',
          'Open/Close session per operator. Admin draw needs admin role.',
        ]),
        _card('Support', [
          'Version 1.0.0+1',
          'No public registration — contact administrator for credentials.',
          'Please play responsibly. Must be 18+.',
        ]),
      ]),
    );
  }

  Widget _card(String title, List<String> bullets) {
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const Divider(height: 8),
              ...bullets.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('• ', style: TextStyle(fontSize: 11)), Expanded(child: Text(b, style: const TextStyle(fontSize: 11)))]))),
            ])));
  }
}
