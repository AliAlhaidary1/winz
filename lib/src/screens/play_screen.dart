import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/database.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/app_drawer.dart';
import '../utils/format.dart';
import 'barcode_scanner_screen.dart';

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key});
  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  List<Map<String, dynamic>> _draws = [];
  String? _drawId;
  String _betType = 'Straight';
  final _amountCtrl = TextEditingController(text: '0.50');
  String _digits = '';
  bool _loadingDraws = true;
  final betTypes = ['Straight', 'Box', 'Combo', 'Straight/Box', 'Front Pair', 'Back Pair'];
  String _gameFilter = 'Numbers';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final draws = await db.getDrawsByGame('g_numbers');
    if (!mounted) return;
    setState(() {
      _draws = draws;
      _drawId = draws.isNotEmpty ? draws.first['id'] as String : null;
      _loadingDraws = false;
    });
  }

  void _pressDigit(String d) { if (_digits.length >= 4) return; setState(() => _digits += d); }
  void _back() => setState(() => _digits = _digits.isNotEmpty ? _digits.substring(0, _digits.length - 1) : '');
  void _clear() => setState(() => _digits = '');
  void _quickPick() {
    final rnd = Random();
    final len = _gameFilter == '4D' ? 4 : 3;
    String s = '';
    for (int i = 0; i < len; i++) s += rnd.nextInt(10).toString();
    setState(() => _digits = s);
  }
  void _cycleBetType(){ final idx = betTypes.indexOf(_betType); setState(()=> _betType = betTypes[(idx+1)%betTypes.length]); }
  void _cycleDigitMode(){ setState(()=> _gameFilter = _gameFilter=='4D' ? 'Numbers' : '4D'); }

  Widget _appBarDrawField(){
    const green = Color(0xFF0B8A3E);
    if(_loadingDraws) return const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
    if(_draws.isEmpty) return const Text('No draws', style: TextStyle(color: Colors.white, fontSize: 13));
    return Container(height: 36, padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: _drawId, isDense: true, icon: const Icon(Icons.arrow_drop_down, size: 18, color: green), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: green), items: _draws.map((d)=> DropdownMenuItem(value: d['id'] as String, child: Text(_drawLabel(d), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: green)))).toList(), onChanged: (v)=> setState(()=> _drawId=v))));
  }

  void _incAmount() { final cur = double.tryParse(_amountCtrl.text) ?? 0.5; setState(() => _amountCtrl.text = (cur + 0.5).clamp(0.5,10.0).toStringAsFixed(2)); }
  void _decAmount() { final cur = double.tryParse(_amountCtrl.text) ?? 0.5; setState(() => _amountCtrl.text = (cur - 0.5).clamp(0.5,10.0).toStringAsFixed(2)); }

  Future<void> _addToCart() async {
    if (_digits.length != 3 && _digits.length != 4) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter 3 or 4 digits'))); return; }
    final amt = double.tryParse(_amountCtrl.text);
    final is3D = _digits.length == 3;
    final isBoxBet = _betType.toLowerCase() == 'box';
    double maxAmt = isBoxBet ? 50 : (is3D ? 100 : 10);
    if (amt == null || amt < 0.5 || amt > maxAmt) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Amount \$0.50 - \$${maxAmt.toStringAsFixed(2)}'))); return; }
    final draw = _draws.firstWhere((d) => d['id'] == _drawId, orElse: () => {});
    try{
      await context.read<AppState>().addToCart(gameId: 'g_numbers', gameName: 'Numbers', drawId: _drawId, drawName: draw['name'] as String?, numbers: _digits.split(''), betType: _betType, amount: amt);
      setState(()=> _digits='');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to cart — press SALE'), backgroundColor: AppTheme.green));
    }catch(e){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ','')), backgroundColor: Colors.red)); }
  }
  Future<void> _doSale() async {
    final app = context.read<AppState>();
    if(app.isCartEmpty){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cart empty'))); return; }
    try{
      final ticket = await app.commitSale();
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('SALE Ticket ${ticket['id']} • ${fmtMoney(ticket['total'])}'), backgroundColor: AppTheme.green));
      await _load();
      Navigator.pushNamed(context, '/print', arguments: ticket);
    }catch(e){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ','')), backgroundColor: Colors.red)); }
  }

  Widget _drawer() => const AppDrawer(currentRoute: '/play');

  Widget _keyBtn(String l, {VoidCallback? onTap, Color? color, IconData? icon}) {
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10), child: Container(height: 56, decoration: BoxDecoration(color: color ?? Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)), alignment: Alignment.center, child: icon != null ? Icon(icon, size: 20) : Text(l, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))));
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
    return Container(height: 40, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8), color: Colors.white), child: Row(children: [InkWell(onTap: _decAmount, child: Container(width: 36, alignment: Alignment.center, child: const Icon(Icons.remove, size: 18))), Container(width: 1, color: Colors.grey.shade300), Expanded(child: TextField(controller: _amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), decoration: const InputDecoration(border: InputBorder.none, isDense: true, prefixText: '\$', contentPadding: EdgeInsets.symmetric(vertical: 8)))), Container(width: 1, color: Colors.grey.shade300), InkWell(onTap: _incAmount, child: Container(width: 36, alignment: Alignment.center, child: const Icon(Icons.add, size: 18)))]));
  }
  Widget _controlBar() {
    final digitsField = InkWell(onTap: _cycleDigitMode, borderRadius: BorderRadius.circular(8), child: Container(height: 40, width: 90, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8), color: _gameFilter=='Numbers' ? const Color(0xFFE6F4EA) : Colors.white), alignment: Alignment.center, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.pin, size: 14, color: _gameFilter=='Numbers' ? const Color(0xFF0B8A3E) : Colors.black54), const SizedBox(width: 4), Text(_gameFilter=='Numbers' ? '3 Digits' : '4 Digits', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _gameFilter=='Numbers' ? const Color(0xFF0B8A3E) : Colors.black87))])));
    final typeField = InkWell(onTap: _cycleBetType, borderRadius: BorderRadius.circular(8), child: Container(height: 40, width: 135, padding: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8), color: Colors.white), alignment: Alignment.center, child: Row(children: [const Icon(Icons.style, size: 14, color: Color(0xFF0B8A3E)), const SizedBox(width: 6), Expanded(child: Text(_betType, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis))])));
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [digitsField, const SizedBox(width: 8), typeField, const SizedBox(width: 8), SizedBox(width: 135, child: _amountStepper())]));
  }

  Widget _cartSection(){
    return Consumer<AppState>(builder: (_, app, __){
      if(app.isCartEmpty) return const SizedBox.shrink();
      return Container(color: const Color(0xFFF0F7F0), padding: const EdgeInsets.fromLTRB(12,8,12,8), child: SizedBox(width: double.infinity, height: 44, child: ElevatedButton.icon(onPressed: _doSale, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0B8A3E)), icon: const Icon(Icons.receipt_long), label: Text('SALE  ${fmtMoney(app.cartTotal)} (${app.cartCount} plays)'))));
    });
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF0B8A3E);
    final w = MediaQuery.of(context).size.width;
    final isTablet = w >= 600;
    return Scaffold(
      appBar: AppBar(title: _appBarDrawField(), centerTitle: true, backgroundColor: green, foregroundColor: Colors.white, actions: [
        Consumer<AppState>(builder: (_, app, __)=> app.isCartEmpty ? const SizedBox() : Padding(padding: const EdgeInsets.only(right:8), child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal:8, vertical:4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text('${app.cartCount} • ${fmtMoney(app.cartTotal)}', style: const TextStyle(color: green, fontWeight: FontWeight.w800, fontSize: 11)))))),
        IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: () => _showLogout(context))]),
      drawer: const AppDrawer(currentRoute: '/play'),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isTablet ? 760 : double.infinity),
          child: Column(children: [
            Container(width: double.infinity, color: Colors.white, padding: const EdgeInsets.fromLTRB(10, 10, 10, 6), child: TextField(readOnly: true, controller: TextEditingController(text: _digits.isEmpty ? '' : _digits), textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 8), decoration: InputDecoration(hintText: _gameFilter == '4D' ? '----' : '---', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, suffixIcon: _digits.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: _clear) : null))),
            Container(color: Colors.grey.shade50, padding: const EdgeInsets.fromLTRB(10, 8, 10, 8), child: _loadingDraws ? const LinearProgressIndicator() : _controlBar()),
            Expanded(child: Consumer<AppState>(builder: (ctx, app, __){
              final cart = app.cart;
              if(cart.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFE6F4EA), shape: BoxShape.circle), child: const Icon(Icons.shopping_cart_outlined, color: Color(0xFF0B8A3E), size: 28)), const SizedBox(height: 12), const Text('Cart empty — add numbers then SALE', style: TextStyle(fontWeight: FontWeight.w800)), const Text('Only current plays shown', style: TextStyle(fontSize: 11, color: Colors.black54))])) );
              return ListView.separated(padding: const EdgeInsets.all(8), itemCount: cart.length, separatorBuilder: (_,__)=> const Divider(height: 1), itemBuilder: (c,i){
                final it=cart[i]; return ListTile(dense: true, leading: CircleAvatar(backgroundColor: Colors.green.shade50, child: Text('${i+1}', style: const TextStyle(fontSize: 11, color: Color(0xFF0B8A3E)))), title: Text('${it.numbers.join(' ')} • ${it.betType} • ${fmtMoney(it.amount)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)), subtitle: Text('${it.drawName??''} • ${it.gameName}', style: const TextStyle(fontSize: 10)), trailing: InkWell(onTap: ()=> app.removeFromCart(it.id), child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.delete_outline, size: 16, color: Colors.red))), onTap: (){});
              });
            })),
            _cartSection(),
            Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(8, 8, 8, 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.7, children: [for (int i = 1; i <= 9; i++) _keyBtn('$i', onTap: () => _pressDigit('$i')), _keyBtn('C', onTap: _clear, color: Colors.red.shade50), _keyBtn('0', onTap: () => _pressDigit('0')), _keyBtn('', onTap: _back, icon: Icons.backspace_outlined, color: Colors.grey.shade100)])),
              const SizedBox(width: 8),
              Expanded(flex: 1, child: SizedBox(height: 4 * 56 + 3 * 8, child: Column(children: [
                SizedBox(height: 56, width: double.infinity, child: OutlinedButton.icon(onPressed: _quickPick, icon: const Icon(Icons.auto_awesome, size: 16), label: const Text('Quick Pick', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)), style: OutlinedButton.styleFrom(side: BorderSide(color: green.withValues(alpha: 0.4))))),
                const SizedBox(height: 8),
                Expanded(child: InkWell(onTap: _addToCart, borderRadius: BorderRadius.circular(10), child: Container(decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(10)), alignment: Alignment.center, child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_shopping_cart, color: Colors.white, size: 28), Text('ADD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)), Text('to cart', style: TextStyle(color: Colors.white70, fontSize: 10))])))),
              ]))),
            ])),
          ]),
        ),
      ),
    );
  }
  void _showLogout(BuildContext context) {
    showDialog(context: context, builder: (c) => AlertDialog(title: const Text('Logout'), content: const Text('End session?'), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), ElevatedButton(onPressed: () { context.read<AppState>().logout(); Navigator.pop(c); Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false); }, child: const Text('Logout'))]));
  }
}
