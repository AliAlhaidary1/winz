import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/database.dart';
import '../providers/app_state.dart';

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key});
  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  List<Map<String, dynamic>> _draws = [];
  String? _drawId;
  String _betType = 'Straight';
  final _amountCtrl = TextEditingController(text: '1.00');
  String _digits = '';
  bool _loadingDraws = true;
  List<Map<String, dynamic>> _myPlays = [];
  final betTypes = ['Straight', 'Box', 'Combo', 'Straight/Box', 'Front Pair', 'Back Pair'];
  String _gameFilter = 'Numbers'; // Numbers=3D, 4D=4D

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final draws = await db.getDrawsByGame('g_numbers');
    final tickets = await db.getTickets();
    if (!mounted) return;
    setState(() {
      _draws = draws;
      _drawId = draws.isNotEmpty ? draws.first['id'] as String : null;
      _loadingDraws = false;
      _myPlays = tickets.take(20).toList();
    });
  }

  void _pressDigit(String d) {
    if (_digits.length >= 4) return;
    setState(() => _digits += d);
  }

  void _back() => setState(() => _digits = _digits.isNotEmpty ? _digits.substring(0, _digits.length - 1) : '');
  void _clear() => setState(() => _digits = '');

  void _quickPick() {
    final rnd = Random();
    final len = _gameFilter == '4D' ? 4 : 3;
    String s = '';
    for (int i = 0; i < len; i++) s += rnd.nextInt(10).toString();
    setState(() => _digits = s);
  }

  void _cycleBetType(){
    final idx = betTypes.indexOf(_betType);
    setState(()=> _betType = betTypes[(idx+1)%betTypes.length]);
  }

  void _cycleDigitMode(){
    setState((){
      _gameFilter = _gameFilter=='4D' ? 'Numbers' : '4D';
    });
  }

  Widget _appBarDrawField(){
    const green = Color(0xFF0B8A3E);
    if(_loadingDraws) return const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
    if(_draws.isEmpty) return const Text('No draws', style: TextStyle(color: Colors.white, fontSize: 13));
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _drawId,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, size: 18, color: green),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: green),
          items: _draws.map((d)=> DropdownMenuItem(value: d['id'] as String, child: Text(_drawLabel(d), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: green)))).toList(),
          onChanged: (v)=> setState(()=> _drawId=v),
        ),
      ),
    );
  }

  void _incAmount() {
    final cur = double.tryParse(_amountCtrl.text) ?? 1.0;
    final next = (cur + 0.5).clamp(0.5, 10.0);
    setState(() => _amountCtrl.text = next.toStringAsFixed(2));
  }

  void _decAmount() {
    final cur = double.tryParse(_amountCtrl.text) ?? 1.0;
    final next = (cur - 0.5).clamp(0.5, 10.0);
    setState(() => _amountCtrl.text = next.toStringAsFixed(2));
  }

  int _comboCountForValidation(List<String> digits) {
    final freq = <String, int>{};
    for (final d in digits) freq[d] = (freq[d] ?? 0) + 1;
    int fact(int x) => x <= 1 ? 1 : x * fact(x - 1);
    var denom = 1;
    for (final c in freq.values) denom *= fact(c);
    return fact(digits.length) ~/ denom;
  }

  Future<void> _play() async {
    if (_digits.length != 3 && _digits.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter 3 or 4 digits (0-9)')));
      return;
    }
    final amt = double.tryParse(_amountCtrl.text);
    if (amt == null || amt < 0.5 || amt > 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Amount \$0.50 - \$10.00')));
      return;
    }
    if (_betType.toLowerCase().contains('combo')) {
      final combos = _comboCountForValidation(_digits.split(''));
      if (combos <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Combo invalid for ${_digits}')));
        return;
      }
      final perCombo = amt / combos;
      if ((perCombo * 100).round() % 50 != 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Combo amount must be divisible by $combos')));
        return;
      }
    }
    final draw = _draws.firstWhere((d) => d['id'] == _drawId, orElse: () => {});
    final numbers = _digits.split('');
    final ticket = await context.read<AppState>().createTicket(
          gameId: 'g_numbers',
          gameName: 'Numbers',
          drawId: _drawId,
          drawName: draw['name'] as String?,
          numbers: numbers,
          betType: _betType,
          amount: amt,
          isQuickPick: false,
        );
    setState(() {
      _myPlays.insert(0, ticket);
      _digits = '';
    });
    if (!mounted) return;
    final amountDisplay = amt.toStringAsFixed(2);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${numbers.join()} • \$$amountDisplay')));
  }

  // Drawer widget
  Widget _drawer(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    return Drawer(
      child: ListView(padding: EdgeInsets.zero, children: [
        DrawerHeader(
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.storefront, color: Colors.white, size: 36),
            const SizedBox(height: 8),
            Text('NY Lottery POS', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text('${user?['username'] ?? ''} • ${user?['role'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
        ListTile(
          leading: const Icon(Icons.casino),
          title: const Text('Play'),
          selected: true,
          onTap: () => Navigator.pop(context),
        ),
        ListTile(leading: const Icon(Icons.emoji_events), title: const Text('Winz'), onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/winz'); }),
        const Divider(),
        ListTile(leading: const Icon(Icons.confirmation_number), title: const Text('Tickets'), onTap: () => Navigator.pushNamed(context, '/tickets')),
        ListTile(leading: const Icon(Icons.verified), title: const Text('Winning Tickets'), onTap: () => Navigator.pushNamed(context, '/winning')),
        ListTile(leading: const Icon(Icons.point_of_sale), title: const Text('Sales'), onTap: () => Navigator.pushNamed(context, '/cash')),
        ListTile(leading: const Icon(Icons.account_balance), title: const Text('Balance'), onTap: () => Navigator.pushNamed(context, '/balance')),
        ListTile(leading: const Icon(Icons.print), title: const Text('Print'), onTap: () => Navigator.pushNamed(context, '/print')),
        ListTile(leading: const Icon(Icons.assessment), title: const Text('Get Report'), onTap: () => Navigator.pushNamed(context, '/report')),
        ListTile(leading: const Icon(Icons.share), title: const Text('Share'), onTap: () => Navigator.pushNamed(context, '/share')),
        ListTile(leading: const Icon(Icons.help_outline), title: const Text('Help'), onTap: () => Navigator.pushNamed(context, '/help')),
        ListTile(leading: const Icon(Icons.settings), title: const Text('Configuration'), onTap: () => Navigator.pushNamed(context, '/config')),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text('Logout', style: TextStyle(color: Colors.red)),
          onTap: () {
            context.read<AppState>().logout();
            Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
          },
        ),
      ]),
    );
  }

  Widget _keyBtn(String l, {VoidCallback? onTap, Color? color, IconData? icon}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 56,
        decoration: BoxDecoration(color: color ?? Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
        alignment: Alignment.center,
        child: icon != null ? Icon(icon, size: 20) : Text(l, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      ),
    );
  }

  String _drawLabel(Map<String, dynamic> d) {
    final name = d['name'] as String;
    final periodRaw = name.split(' - ').first.replaceAll('Numbers ', '').trim();
    final datePart = name.split(' - ').length > 1 ? name.split(' - ').last : '';
    String period = periodRaw;
    if (periodRaw.toLowerCase().contains('morning') || periodRaw.toLowerCase().contains('midday')) period = 'Morning';
    else if (periodRaw.toLowerCase().contains('evening')) period = 'Evening';
    else if (periodRaw.toLowerCase().contains('night')) period = 'Night';
    return '$period • $datePart';
  }

  Widget _amountStepper() {
    return Container(
      height: 40,
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8), color: Colors.white),
      child: Row(children: [
        InkWell(onTap: _decAmount, borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8)), child: Container(width: 36, alignment: Alignment.center, child: const Icon(Icons.remove, size: 18))),
        Container(width: 1, color: Colors.grey.shade300),
        Expanded(
          child: TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, prefixText: '\$', contentPadding: EdgeInsets.symmetric(vertical: 8)),
          ),
        ),
        Container(width: 1, color: Colors.grey.shade300),
        InkWell(onTap: _incAmount, borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)), child: Container(width: 36, alignment: Alignment.center, child: const Icon(Icons.add, size: 18))),
      ]),
    );
  }

  // Single-row control bar: Tap to cycle for 3/4 and Bet Type + Amount - Draw in AppBar
  Widget _controlBar() {
    final digitsField = InkWell(
      onTap: _cycleDigitMode,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        width: 90,
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8), color: _gameFilter=='Numbers' ? const Color(0xFFE6F4EA) : Colors.white),
        alignment: Alignment.center,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.pin, size: 14, color: _gameFilter=='Numbers' ? const Color(0xFF0B8A3E) : Colors.black54),
          const SizedBox(width: 4),
          Text(_gameFilter=='Numbers' ? '3 Digits' : '4 Digits', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _gameFilter=='Numbers' ? const Color(0xFF0B8A3E) : Colors.black87)),
          const SizedBox(width: 4),
          const Icon(Icons.swap_horiz, size: 14, color: Colors.black45),
        ]),
      ),
    );

    final typeField = InkWell(
      onTap: _cycleBetType,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        width: 135,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8), color: Colors.white),
        alignment: Alignment.center,
        child: Row(children: [
          const Icon(Icons.style, size: 14, color: Color(0xFF0B8A3E)),
          const SizedBox(width: 6),
          Expanded(child: Text(_betType, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
          const Icon(Icons.swap_horiz, size: 14, color: Colors.black45),
        ]),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        digitsField,
        const SizedBox(width: 8),
        typeField,
        const SizedBox(width: 8),
        SizedBox(width: 135, child: _amountStepper()),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF0B8A3E);
    final w = MediaQuery.of(context).size.width;
    final isTablet = w >= 600;
    return Scaffold(
      appBar: AppBar(title: _appBarDrawField(), centerTitle: true, backgroundColor: green, foregroundColor: Colors.white, actions: [IconButton(icon: const Icon(Icons.logout, color: Colors.white), tooltip: 'Logout', onPressed: () => _showLogout(context))]),
      drawer: _drawer(context),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isTablet ? 760 : double.infinity),
          child: Column(children: [
            // ---- عرض الرقم المدخل ----
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: TextField(
                readOnly: true,
                controller: TextEditingController(text: _digits.isEmpty ? '' : _digits),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 8),
                decoration: InputDecoration(
                  hintText: _gameFilter == '4D' ? '----' : '---',
                  hintStyle: const TextStyle(letterSpacing: 8, color: Colors.black26),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  suffixIcon: _digits.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: _clear) : null,
                  labelText: 'Number 0-9 (${_gameFilter == '4D' ? '4' : '3'})',
                  labelStyle: const TextStyle(fontSize: 11),
                ),
              ),
            ),
            // Single-row control bar
            Container(
              color: Colors.grey.shade50,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: _loadingDraws ? const LinearProgressIndicator() : _controlBar(),
            ),
            const Divider(height: 1),
            // ---- قائمة الرهانات ----
            Expanded(
              child: _myPlays.isEmpty
                  ? const Center(child: Text('No plays yet — use keypad below', style: TextStyle(color: Colors.black45)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _myPlays.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (c, i) {
                        final t = _myPlays[i];
                        final amountText = (t['amount'] as num).toStringAsFixed(2);
                        final numbersText = t['numbers'].toString().replaceAll(',', ' ');
                        final betTypeText = t['betType'];
                        final drawNameText = t['drawName'] ?? '';
                        final createdAtText = t['createdAt'].toString().substring(0, 10);
                        final idText = t['id'];
                        final status = t['status'];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(backgroundColor: Colors.indigo.shade50, child: Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                          title: Text('$numbersText • $betTypeText • \$$amountText', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text('$drawNameText • $createdAtText • $idText', style: const TextStyle(fontSize: 10)),
                          trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: status == 'paid' ? Colors.green.shade50 : Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(6)), child: Text(status, style: const TextStyle(fontSize: 10))),
                          onTap: () => Navigator.pushNamed(context, '/ticket_detail', arguments: t),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            // Keypad with Quick Pick above ENTER - no duplicate Play/QP elsewhere
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.7,
                      children: [
                        for (int i = 1; i <= 9; i++) _keyBtn('$i', onTap: () => _pressDigit('$i')),
                        _keyBtn('C', onTap: _clear, color: Colors.red.shade50),
                        _keyBtn('0', onTap: () => _pressDigit('0')),
                        _keyBtn('', onTap: _back, icon: Icons.backspace_outlined, color: Colors.grey.shade100),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: SizedBox(
                      height: 4 * 56 + 3 * 8,
                      child: Column(children: [
                        SizedBox(
                          height: 56,
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _quickPick,
                            icon: const Icon(Icons.auto_awesome, size: 16),
                            label: const Text('Quick Pick', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), side: BorderSide(color: green.withValues(alpha: 0.4))),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: InkWell(
                            onTap: _play,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
                              alignment: Alignment.center,
                              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                                SizedBox(height: 4),
                                Text('PLAY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                                SizedBox(height: 2),
                                Text('ENTER', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 10, letterSpacing: 1)),
                              ]),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('End session and return to login?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          ElevatedButton(onPressed: () { context.read<AppState>().logout(); Navigator.pop(c); Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false); }, child: const Text('Logout')),
        ],
      ),
    );
  }
}
