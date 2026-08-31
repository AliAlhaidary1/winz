import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/database.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

class NumbersScreen extends StatefulWidget {
  const NumbersScreen({super.key});
  @override
  State<NumbersScreen> createState() => _NumbersScreenState();
}

class _NumbersScreenState extends State<NumbersScreen> {
  List<Map<String, dynamic>> _draws = [];
  String? _drawId;
  String _betType = 'Straight';
  final _amountCtrl = TextEditingController(text: '0.50');
  String _digits = '';
  bool _isQuickPick = false;
  bool _loadingDraws = true;
  List<Map<String, dynamic>> _myPlays = [];
  String _digitMode = '3D'; // 3D / 4D

  final betTypes = ['Straight', 'Box', 'Combo'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final allDraws = await db.getDrawsByGame('g_numbers');
    final draws = allDraws.where((d)=> d['status']=='open').take(4).toList();
    final tickets = await db.getTickets();
    if (!mounted) return;
    setState(() {
      _draws = draws.isNotEmpty ? draws : allDraws.take(4).toList();
      _drawId = _draws.isNotEmpty ? _draws.first['id'] as String : null;
      _loadingDraws = false;
      _myPlays = tickets.where((t)=> t['gameName']=='Numbers').take(30).toList();
      if(_myPlays.isEmpty) _myPlays = tickets.take(20).toList();
    });
  }

  void _pressDigit(String d){ if(_digits.length>=4) return; setState(()=> _digits+=d); }
  void _back()=> setState(()=> _digits = _digits.isNotEmpty ? _digits.substring(0,_digits.length-1) : '');
  void _clear()=> setState(()=> _digits='');
  void _quickPick(){
    final rnd=Random();
    final len=_digitMode=='3D' ? 3 : 4;
    String s=''; for(int i=0;i<len;i++) s+= rnd.nextInt(10).toString();
    setState(()=> _digits=s);
    _isQuickPick=true;
  }
  void _incAmount(){
    final cur = double.tryParse(_amountCtrl.text) ?? 0.5;
    final nxt = (cur + 0.5).clamp(0.5, 10.0);
    setState(()=> _amountCtrl.text = nxt.toStringAsFixed(2));
  }
  void _decAmount(){
    final cur = double.tryParse(_amountCtrl.text) ?? 0.5;
    final nxt = (cur - 0.5).clamp(0.5, 10.0);
    setState(()=> _amountCtrl.text = nxt.toStringAsFixed(2));
  }
  int _comboCount(List<String> d){ final n=d.length; final f=<String,int>{}; for(final x in d) { f[x]=(f[x]??0)+1; } int fact(int x)=> x<=1?1:x*fact(x-1); var denom=1; for(final c in f.values) { denom*=fact(c); } return fact(n)~/denom; }

  void _cycleBetType(){
    final idx = betTypes.indexOf(_betType);
    setState(()=> _betType = betTypes[(idx+1)%betTypes.length]);
  }

  void _cycleDigitMode(){
    setState((){
      _digitMode = _digitMode=='3D' ? '4D' : '3D';
      if(_digitMode=='3D' && _digits.length>3) _digits=_digits.substring(0,3);
    });
  }

  Widget _appBarDrawField(){
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
          icon: const Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.green),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.green),
          items: _draws.map((d)=> DropdownMenuItem(value: d['id'] as String, child: Text(_drawLabel(d), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.green)))).toList(),
          onChanged: (v)=> setState(()=> _drawId=v),
        ),
      ),
    );
  }

  Future<void> _play() async {
    if(_digits.isEmpty){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter numbers first'))); return; }
    final need = _digitMode=='3D' ? 3 : 4;
    if(_digits.length != need){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please enter exactly $need digits for $_digitMode mode'))); return; }
    final amt=double.tryParse(_amountCtrl.text);
    if(amt==null|| amt<0.5 || amt>10){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Amount \$0.50 - \$10.00'))); return; }
    if(_betType.toLowerCase().contains('combo')){
      final combos=_comboCount(_digits.split(''));
      if(combos<=1){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Combo not valid for $_digits'))); return; }
      if(((amt/combos)*100).round()%50!=0){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Combo needs amount divisible by $combos'))); return; }
    }
    final draw=_draws.firstWhere((d)=> d['id']==_drawId, orElse: ()=>{});
    try{
      final ticket=await context.read<AppState>().createTicket(gameId:'g_numbers', gameName:'Numbers', drawId:_drawId, drawName:draw['name'] as String?, numbers:_digits.split(''), betType:_betType, amount:amt, isQuickPick:_isQuickPick);
      setState(()=> _myPlays.insert(0,ticket));
      setState(()=> _digits='');
      _isQuickPick=false;
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ticket ${ticket['id']} • ${ticket['numbers'].toString().replaceAll(',', ' ')} • \$${amt.toStringAsFixed(2)}'), backgroundColor: AppTheme.green));
    }catch(e){
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  Widget _buildList(){
    return _myPlays.isEmpty ? _empty() : ListView.separated(
      padding: const EdgeInsets.fromLTRB(12,12,12,8),
      itemCount: _myPlays.length,
      separatorBuilder: (_,__)=> const SizedBox(height: 8),
      itemBuilder: (c,i){
        final t=_myPlays[i];
        final isPaid=t['status']=='paid';
        final isWin=t['status']=='winning';
        final color=isPaid? AppTheme.green : isWin? Colors.orange : AppTheme.blue;
        return Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.12))),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: ()=> Navigator.pushNamed(context,'/ticket_detail', arguments: t),
            child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
              Container(width: 4, height: 48, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)), child: Text(t['betType'], style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color))),
                  const SizedBox(width: 6),
                  Text(fmtMoney(t['amount']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: isPaid? AppTheme.greenLight : isWin? Colors.orange.shade50 : Colors.grey.shade100, borderRadius: BorderRadius.circular(20)), child: Text(t['status'], style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isPaid? AppTheme.green : isWin? Colors.orange.shade700 : Colors.black54))),
                ]),
                const SizedBox(height: 6),
                Text((t['numbers'] as String).replaceAll(',', '   '), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
                const SizedBox(height: 4),
                Row(children: [Icon(Icons.event, size: 12, color: Colors.grey.shade500), const SizedBox(width: 4), Expanded(child: Text('${t['drawName'] ?? '-'} • ${fmtDate(t['createdAt'])}', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted), overflow: TextOverflow.ellipsis))]),
              ])),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 16, color: Colors.black26),
            ])),
          ),
        );
      },
    );
  }

  // Single-row control bar: Tap to cycle for 3/4 and Bet Type + Amount stepper (Draw is now in AppBar)
  Widget _buildControlBar() {
    final digitsField = InkWell(
      onTap: _cycleDigitMode,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        width: 90,
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8), color: _digitMode=='3D' ? AppTheme.greenLight : Colors.white),
        alignment: Alignment.center,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.pin, size: 14, color: _digitMode=='3D' ? AppTheme.green : AppTheme.textMuted),
          const SizedBox(width: 4),
          Text(_digitMode, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _digitMode=='3D' ? AppTheme.green : AppTheme.textDark)),
          const SizedBox(width: 4),
          const Icon(Icons.swap_horiz, size: 14, color: AppTheme.textMuted),
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
          Icon(_betType=='Straight' ? Icons.straighten : _betType=='Box' ? Icons.inventory_2_outlined : Icons.shuffle, size: 14, color: AppTheme.green),
          const SizedBox(width: 6),
          Expanded(child: Text(_betType, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
          const Icon(Icons.swap_horiz, size: 14, color: AppTheme.textMuted),
        ]),
      ),
    );

    final amountStepper = Container(
      height: 40,
      width: 135,
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8), color: Colors.white),
      child: Row(children: [
        InkWell(onTap: _decAmount, borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8)), child: Container(width: 32, alignment: Alignment.center, child: const Icon(Icons.remove, size: 16))),
        Container(width: 1, color: Colors.grey.shade300),
        Expanded(
          child: TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, prefixText: '\$', contentPadding: EdgeInsets.symmetric(vertical: 8)),
          ),
        ),
        Container(width: 1, color: Colors.grey.shade300),
        InkWell(onTap: _incAmount, borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)), child: Container(width: 32, alignment: Alignment.center, child: const Icon(Icons.add, size: 16))),
      ]),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        digitsField,
        const SizedBox(width: 8),
        typeField,
        const SizedBox(width: 8),
        amountStepper,
      ]),
    );
  }

  Widget _buildInputPanel(){
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0,-4))]),
      padding: const EdgeInsets.fromLTRB(12,10,12,10),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_digitMode=='3D'?3:4, (idx){
          final has = idx < _digits.length;
          final char = has ? _digits[idx] : '';
          return Container(width: 48, height: 48, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: has? AppTheme.green : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: has? AppTheme.green : AppTheme.cardBorder, width: has? 2:1)), alignment: Alignment.center, child: has? Text(char, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)) : Text('—', style: TextStyle(fontSize: 16, color: Colors.grey.shade400)));
        })),
        const SizedBox(height: 4),
        Text(_digits.isEmpty ? '${_digitMode=='3D'?'3':'4'} digits (0-9)' : '${_digits.length}/${_digitMode=='3D'?'3':'4'}', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
        const SizedBox(height: 10),
        if(_loadingDraws) const LinearProgressIndicator(color: AppTheme.green) else _buildControlBar(),
      ]),
    );
  }

  Widget _buildKeypad(){
    // Keypad with Quick Pick above ENTER (Play) on the right - no duplicate Play/QP elsewhere
    final gridHeight = 4 * 56 + 3 * 8 + 8.0;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8,8,8,8),
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
              childAspectRatio: 1.8,
              children: [
                for(int i=1;i<=9;i++) _keyBtn('$i', onTap: ()=> _pressDigit('$i')),
                _keyBtn('C', onTap: _clear, bg: const Color(0xFFFFF1F1), fg: Colors.red, border: const Color(0xFFFFC9C9)),
                _keyBtn('0', onTap: ()=> _pressDigit('0')),
                _keyBtn('', onTap: _back, icon: Icons.backspace_outlined),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: SizedBox(
              height: gridHeight,
              child: Column(children: [
                // Quick Pick above ENTER
                SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _quickPick,
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('Quick Pick', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), side: BorderSide(color: AppTheme.green.withValues(alpha: 0.4))),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: InkWell(
                    onTap: _play,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(color: AppTheme.green, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.cardBorder)),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final w=MediaQuery.of(context).size.width;
    final h=MediaQuery.of(context).size.height;
    final isTablet=w>=600;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape && h < 500;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: _appBarDrawField(),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.help_outline, size: 18), onPressed: ()=> Navigator.pushNamed(context,'/help')), IconButton(icon: const Icon(Icons.logout, size: 18), onPressed: ()=> _logout())],
      ),
      drawer: _drawer(),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isTablet? 760: double.infinity),
          child: isLandscape
              ? Row(children: [
                  Expanded(flex: 3, child: _buildList()),
                  const VerticalDivider(width: 1),
                  Expanded(flex: 2, child: SingleChildScrollView(child: Column(children: [_buildInputPanel(), _buildKeypad()]))),
                ])
              : Column(children: [
            Expanded(child: _buildList()),
            _buildInputPanel(),
            _buildKeypad(),
          ]),
        ),
      ),
    );
  }

  String _drawLabel(Map<String,dynamic> d){
    final name = d['name'] as String;
    String period = 'Draw';
    if(name.contains('Morning')) period='Morning';
    else if(name.contains('Midday')) period='Morning';
    else if(name.contains('Evening')) period='Evening';
    else if(name.contains('Night')) period='Night';
    final dt = DateTime.fromMillisecondsSinceEpoch(d['drawTime'] as int);
    final time = '${dt.hour > 12 ? dt.hour-12 : dt.hour}:${dt.minute.toString().padLeft(2,'0')} ${dt.hour>=12 ? 'PM':'AM'}';
    return '$period • $time';
  }

  Widget _empty(){
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppTheme.greenLight, shape: BoxShape.circle), child: const Icon(Icons.confirmation_number_outlined, color: AppTheme.green, size: 28)),
      const SizedBox(height: 12),
      const Text('No plays yet', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      const Text('Enter 3 or 4 digits (0-9) above and tap Play\nTry Quick Pick for random numbers', style: TextStyle(fontSize: 11, color: AppTheme.textMuted), textAlign: TextAlign.center),
    ])));
  }

  Widget _drawer(){
    final user=context.watch<AppState>().currentUser;
    return Drawer(child: ListView(padding: EdgeInsets.zero, children: [
      DrawerHeader(decoration: BoxDecoration(gradient: LinearGradient(colors: [AppTheme.green, AppTheme.greenDark])), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.storefront, color: Colors.white, size: 32), const SizedBox(height: 8), const Text('NY Lottery POS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)), Text('${user?['username']??''} • ${user?['role']??''}', style: const TextStyle(color: Colors.white70, fontSize: 11))])),
      ListTile(leading: const Icon(Icons.home_outlined), title: const Text('Home'), onTap: (){ Navigator.pop(context); Navigator.pushNamed(context,'/home'); }),
      ListTile(leading: const Icon(Icons.numbers, color: AppTheme.green), title: const Text('Numbers'), selected: true, onTap: ()=> Navigator.pop(context)),
      ListTile(leading: const Icon(Icons.emoji_events, color: AppTheme.orange), title: const Text('Win 4'), onTap: (){ Navigator.pop(context); Navigator.pushNamed(context,'/winz'); }),
      const Divider(),
      ListTile(leading: const Icon(Icons.confirmation_number), title: const Text('Tickets'), onTap: ()=> Navigator.pushNamed(context,'/tickets')),
      ListTile(leading: const Icon(Icons.verified, color: AppTheme.green), title: const Text('Winning Tickets'), onTap: ()=> Navigator.pushNamed(context,'/winning')),
      ListTile(leading: const Icon(Icons.print), title: const Text('Print'), onTap: ()=> Navigator.pushNamed(context,'/print')),
      ListTile(leading: const Icon(Icons.settings), title: const Text('Settings'), onTap: ()=> Navigator.pushNamed(context,'/config')),
      const Divider(),
      ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Logout', style: TextStyle(color: Colors.red)), onTap: (){ context.read<AppState>().logout(); Navigator.pushNamedAndRemoveUntil(context,'/login', (_)=>false); }),
    ]));
  }

  Widget _keyBtn(String label, {VoidCallback? onTap, Color? bg, Color? fg, Color? border, IconData? icon}){
    return Material(
      color: bg ?? Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: border ?? AppTheme.cardBorder)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(height: 56, alignment: Alignment.center, child: icon!=null ? Icon(icon, size: 18, color: Colors.black54) : Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: fg ?? AppTheme.textDark))),
      ),
    );
  }

  void _logout(){ showDialog(context: context, builder: (c)=> AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), title: const Text('Logout'), content: const Text('End session?'), actions: [TextButton(onPressed: ()=> Navigator.pop(c), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(backgroundColor: AppTheme.red), onPressed: (){ context.read<AppState>().logout(); Navigator.pop(c); Navigator.pushNamedAndRemoveUntil(context,'/login', (_)=>false); }, child: const Text('Logout'))])); }
}
