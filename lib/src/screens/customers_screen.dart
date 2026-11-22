import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../utils/format.dart';
import '../utils/responsive.dart';
import '../theme/app_theme.dart';

/// Manage registered customers and their saved plays.
///
/// Every registered customer can store one or more "usual" plays. Pressing
/// [Play] selects the customer and opens the matching sale screen with the
/// saved play prefilled, so the cashier does not have to re-enter the ticket.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  static const Color green = Color(0xFF0B8A3E);

  static const List<String> numbersBetTypes = [
    'Straight',
    'Box',
    'ST/BOX',
    'Combo',
  ];
  static const List<String> winzBetTypes = ['Straight', 'Box', 'ST/BOX'];
  static const List<String> drawTypes = ['Any', 'MIDDAY', 'EVENING'];

  List<Map<String, dynamic>> _customers = [];
  final Map<String, List<Map<String, dynamic>>> _plays = {};
  final Set<String> _expanded = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Load customers first and publish them immediately, then load saved plays
  /// per customer. A failure while reading one customer's plays must not hide
  /// the whole list (this is what made newly-added customers look missing).
  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final state = context.read<AppState>();
    try {
      final customers = await state.getCustomers();
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _loading = false;
        _error = null;
      });

      final plays = <String, List<Map<String, dynamic>>>{};
      for (final c in customers) {
        final id = '${c['id'] ?? ''}';
        try {
          plays[id] = await state.getCustomerPlays(id);
        } catch (_) {
          plays[id] = const <Map<String, dynamic>>[];
        }
      }
      if (!mounted) return;
      setState(() {
        _plays
          ..clear()
          ..addAll(plays);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  bool _isDefault(Map<String, dynamic> c) {
    final v = c['isDefault'];
    return c['id'] == AppState.defaultCustomerId || v == 1 || v == true;
  }

  void _snack(String message, {Color? background}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: background ?? green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Customer CRUD
  // ---------------------------------------------------------------------------

  Future<void> _addCustomer() async {
    final state = context.read<AppState>();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
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
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes / ملاحظات',
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
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Add / إضافة'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Customer name is required / الاسم مطلوب', background: Colors.red);
      return;
    }
    try {
      final id = await state.addCustomer(
        name: name,
        phone: phoneCtrl.text.trim(),
        notes: notesCtrl.text.trim(),
      );
      // Always refresh after a successful add, then verify the new customer
      // is actually in the list before reporting success.
      await _load();
      if (id.isNotEmpty && !_customers.any((c) => '${c['id']}' == id)) {
        throw Exception('Customer saved but not shown — please refresh');
      }
      _snack('Customer added / تمت الإضافة');
    } catch (e) {
      _snack(e.toString(), background: Colors.red);
    }
  }

  Future<void> _editCustomer(Map<String, dynamic> c) async {
    final state = context.read<AppState>();
    final nameCtrl = TextEditingController(text: '${c['name'] ?? ''}');
    final phoneCtrl = TextEditingController(text: '${c['phone'] ?? ''}');
    final notesCtrl = TextEditingController(text: '${c['notes'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: Responsive.dialogInsets(ctx),
        title: Text('Edit customer / تعديل عميل\n${c['name'] ?? ''}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name / الاسم'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone / الهاتف'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes / ملاحظات'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel / إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save / حفظ'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Customer name is required / الاسم مطلوب', background: Colors.red);
      return;
    }
    try {
      await state.updateCustomer(
        c['id'] as String,
        name: name,
        phone: phoneCtrl.text.trim(),
        notes: notesCtrl.text.trim(),
      );
      await _load();
      _snack('Customer updated / تم التحديث');
    } catch (e) {
      _snack(e.toString(), background: Colors.red);
    }
  }

  Future<void> _deleteCustomer(Map<String, dynamic> c) async {
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: Responsive.dialogInsets(ctx),
        title: const Text('Delete customer / حذف عميل'),
        content: Text(
          'Delete "${c['name'] ?? ''}"? Their tickets will be reassigned to the default customer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel / إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete / حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await state.deleteCustomer(c['id'] as String);
      _expanded.remove(c['id']);
      await _load();
      _snack('Customer deleted / تم الحذف');
    } catch (e) {
      _snack(e.toString(), background: Colors.red);
    }
  }

  // ---------------------------------------------------------------------------
  // Saved plays
  // ---------------------------------------------------------------------------

  Future<void> _addPlay(Map<String, dynamic> c) async {
    final state = context.read<AppState>();
    final customerId = '${c['id'] ?? ''}';
    final numbersCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    int digitCount = 3;
    String betType = numbersBetTypes.first;
    String drawType = drawTypes.first;

    // The digit count fully determines the game: 3 -> Numbers, 4 -> Win 4.
    String gameIdFor(int count) => count == 4 ? 'g_winz' : 'g_numbers';
    String gameNameFor(int count) => count == 4 ? 'Win 4' : 'Numbers';
    List<String> betTypesFor(int count) =>
        count == 4 ? winzBetTypes : numbersBetTypes;

    /// The first thing still missing/invalid, or null when the play is ready.
    /// Drives both the inline hint and the Save button, so a bad tap can never
    /// fall through to the snackbar path.
    String? validationError() {
      final numbers = numbersCtrl.text.trim();
      if (numbers.length != digitCount) {
        return 'Enter exactly $digitCount digits / أدخل $digitCount أرقام';
      }
      final amount = double.tryParse(amountCtrl.text.trim());
      if (amount == null || amount <= 0) {
        return 'Enter an amount above \$0 / أدخل مبلغاً أكبر من صفر';
      }
      if ((amount * 100).round() % 50 != 0) {
        return 'Amount must be in \$0.50 steps / المبلغ بخطوات 0.50\$';
      }
      final isCombo = betType == 'Combo';
      final isBox = betType == 'Box';
      final isStBox = betType == 'ST/BOX';
      if (isCombo && amount > 10 + 1e-9) {
        return 'Combo max \$10 per combo / 10\$ لكل تركيبة كحد أقصى';
      }
      if (isBox && amount > 50 + 1e-9) {
        return 'Box max \$50 / 50\$ كحد أقصى';
      }
      if (isStBox && amount > (digitCount == 4 ? 25 : 50) + 1e-9) {
        return 'ST/BOX max \$${digitCount == 4 ? 25 : 50} / حد أقصى';
      }
      if (!isCombo && !isBox && !isStBox) {
        final maxStraight = digitCount == 4 ? 10.0 : 100.0;
        if (amount > maxStraight + 1e-9) {
          return 'Straight max \$${maxStraight.toStringAsFixed(0)} / حد أقصى';
        }
      }
      return null;
    }

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialog) {
            final error = validationError();
            return AlertDialog(
              insetPadding: Responsive.dialogInsets(ctx),
              title: Text('Add play / إضافة لعبة — ${c['name'] ?? ''}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Digits / عدد الأرقام',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 3, label: Text('3 digits')),
                        ButtonSegment(value: 4, label: Text('4 digits')),
                      ],
                      selected: {digitCount},
                      onSelectionChanged: (selection) {
                        if (selection.isEmpty) return;
                        setDialog(() {
                          digitCount = selection.first;
                          // A saved number belongs to one count only: drop it
                          // when the count changes instead of keeping a
                          // now-invalid value.
                          numbersCtrl.clear();
                          final allowed = betTypesFor(digitCount);
                          if (!allowed.contains(betType)) {
                            betType = allowed.first;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: numbersCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: digitCount,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Numbers / الأرقام',
                        hintText: digitCount == 4 ? '1234' : '123',
                        counterText: '',
                      ),
                      onChanged: (v) {
                        final digits = v.replaceAll(RegExp(r'\D'), '');
                        final trimmed = digits.length > digitCount
                            ? digits.substring(0, digitCount)
                            : digits;
                        if (trimmed != v) {
                          numbersCtrl.value = numbersCtrl.value.copyWith(
                            text: trimmed,
                            selection: TextSelection.collapsed(
                              offset: trimmed.length,
                            ),
                          );
                        }
                        setDialog(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      // Recreate when the count changes so the allowed bet
                      // types (4 digits has no Combo) are picked up by
                      // initialValue.
                      key: ValueKey('betType-$digitCount'),
                      initialValue: betType,
                      decoration: const InputDecoration(
                        labelText: 'Bet type / نوع الرهان',
                      ),
                      items: betTypesFor(digitCount)
                          .map(
                            (t) => DropdownMenuItem(value: t, child: Text(t)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setDialog(() => betType = v ?? 'Straight'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount / المبلغ',
                        hintText: '0.50',
                      ),
                      onChanged: (_) => setDialog(() {}),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: drawType,
                      decoration: const InputDecoration(
                        labelText: 'Draw type / نوع السحب (optional)',
                      ),
                      items: drawTypes
                          .map(
                            (t) => DropdownMenuItem(value: t, child: Text(t)),
                          )
                          .toList(),
                      onChanged: (v) => setDialog(() => drawType = v ?? 'Any'),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          error,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel / إلغاء'),
                ),
                ElevatedButton(
                  onPressed: error == null
                      ? () => Navigator.pop(ctx, true)
                      : null,
                  child: const Text('Save / حفظ'),
                ),
              ],
            );
          },
        ),
      );
      if (ok != true) return;
      // Save is already gated by the same validation; this is only a safety
      // net so invalid input never produces a snackbar.
      if (validationError() != null) return;

      final numbers = numbersCtrl.text.trim();
      final amount = double.tryParse(amountCtrl.text.trim())!;
      await state.addCustomerPlay(
        customerId,
        gameId: gameIdFor(digitCount),
        gameName: gameNameFor(digitCount),
        numbers: numbers,
        betType: betType,
        amount: amount,
        drawType: drawType == 'Any' ? null : drawType,
        isQuickPick: false,
      );
      await _load();
    } catch (e) {
      _snack(e.toString(), background: Colors.red);
    } finally {
      numbersCtrl.dispose();
      amountCtrl.dispose();
    }
  }

  Future<void> _deletePlay(String playId) async {
    try {
      await context.read<AppState>().deleteCustomerPlay(playId);
      await _load();
    } catch (e) {
      _snack(e.toString(), background: Colors.red);
    }
  }

  /// Select the customer and open the right sale screen with a saved play
  /// prefilled. No snackbar on a successful selection/navigation.
  Future<void> _navigateToPlay(
    Map<String, dynamic> c,
    Map<String, dynamic> p,
  ) async {
    final state = context.read<AppState>();
    final id = '${c['id'] ?? ''}';
    try {
      if (_isDefault(c)) {
        await state.useDefaultCustomer();
      } else {
        await state.selectCustomer(id);
      }
    } catch (e) {
      _snack(e.toString(), background: Colors.red);
      return;
    }
    if (!mounted) return;

    final gameId = '${p['gameId'] ?? 'g_numbers'}';
    final args = <String, dynamic>{
      'customerId': id,
      'customerName': '${c['name'] ?? ''}',
      'numbers': '${p['numbers'] ?? ''}',
      'betType': '${p['betType'] ?? ''}',
      'amount': asDouble(p['amount']),
      'gameId': gameId,
      'drawType': '${p['drawType'] ?? ''}',
    };
    Navigator.pushNamed(
      context,
      gameId == 'g_winz' ? '/winz' : '/numbers',
      arguments: args,
    );
  }

  /// One saved play -> go straight to the sale screen.
  /// Several -> let the cashier pick one. None -> ask them to add a play.
  void _playCustomer(Map<String, dynamic> c) {
    final plays = _plays['${c['id'] ?? ''}'] ?? const <Map<String, dynamic>>[];
    if (plays.isEmpty) {
      _snack('No saved plays yet — add a play first / أضف لعبة أولاً');
      return;
    }
    if (plays.length == 1) {
      _navigateToPlay(c, plays.first);
      return;
    }

    showDialog<dynamic>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: Responsive.dialogInsets(ctx),
        title: Text('Choose a play / اختر لعبة — ${c['name'] ?? ''}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: Responsive.dialogContentMaxHeight(ctx),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: plays.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, index) {
                final p = plays[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    '${p['numbers'] ?? ''} • ${p['betType'] ?? ''} • '
                    '${fmtMoney(asDouble(p['amount']))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${p['gameName'] ?? ''}'
                    '${p['drawType'] != null && '${p['drawType']}'.isNotEmpty ? '  •  ${p['drawType']}' : ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(ctx, p),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel / إلغاء'),
          ),
        ],
      ),
    ).then((p) {
      if (p is Map<String, dynamic>) _navigateToPlay(c, p);
    });
  }

  // ---------------------------------------------------------------------------
  // Widgets
  // ---------------------------------------------------------------------------

  Widget _playsTile(String customerId) {
    final plays = _plays[customerId] ?? const <Map<String, dynamic>>[];
    if (plays.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Text(
          'No saved plays yet / لا توجد ألعاب محفوظة',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
      );
    }
    return Column(
      children: plays.map((p) {
        final draw = '${p['drawType'] ?? ''}';
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            backgroundColor: AppTheme.greenSoft,
            radius: 16,
            child: const Icon(
              Icons.confirmation_number,
              size: 15,
              color: green,
            ),
          ),
          title: Text(
            '${p['gameName'] ?? ''}  •  ${p['numbers'] ?? ''}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${p['betType'] ?? ''}  •  ${fmtMoney(asDouble(p['amount']))}'
            '${draw.isNotEmpty ? '  •  $draw' : ''}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Delete play / حذف اللعبة',
            onPressed: () => _deletePlay('${p['id'] ?? ''}'),
          ),
        );
      }).toList(),
    );
  }

  Widget _customerCard(Map<String, dynamic> c) {
    final id = '${c['id'] ?? ''}';
    final isDefault = _isDefault(c);
    final isSelected = id == context.watch<AppState>().currentCustomer['id'];
    final plays = _plays[id] ?? const <Map<String, dynamic>>[];
    final expanded = _expanded.contains(id);
    final phone = '${c['phone'] ?? ''}'.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppTheme.cardDecoration(
        borderColor: isSelected ? green : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ListTile paints its ink on the nearest Material ancestor; the
          // decorated card Container would hide the splash (debug assertion).
          Material(
            color: Colors.transparent,
            child: ListTile(
              onTap: () => setState(() {
                if (expanded) {
                  _expanded.remove(id);
                } else {
                  _expanded.add(id);
                }
              }),
              leading: CircleAvatar(
                backgroundColor: isDefault
                    ? Colors.grey.shade200
                    : AppTheme.greenSoft,
                child: Icon(
                  isDefault ? Icons.person_outline : Icons.person,
                  color: isDefault ? Colors.grey.shade600 : green,
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${c['name'] ?? ''}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isDefault)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Default / افتراضي',
                        style: TextStyle(fontSize: 10, color: Colors.black54),
                      ),
                    )
                  else if (isSelected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.greenSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Selected / محدد',
                        style: TextStyle(fontSize: 10, color: green),
                      ),
                    ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${phone.isEmpty ? '—' : phone}'
                  '  •  ${plays.length} saved play(s)',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              trailing: Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: green,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                TextButton.icon(
                  onPressed: () => _playCustomer(c),
                  icon: const Icon(Icons.play_circle_outline, size: 16),
                  label: const Text('Play / لعب'),
                ),
                TextButton.icon(
                  onPressed: () => _addPlay(c),
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('+ Play / لعبة'),
                ),
                if (!isDefault)
                  TextButton.icon(
                    onPressed: () => _editCustomer(c),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit / تعديل'),
                  ),
                if (!isDefault)
                  TextButton.icon(
                    onPressed: () => _deleteCustomer(c),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: Colors.red,
                    ),
                    label: const Text(
                      'Delete / حذف',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _playsTile(id),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Customers / العملاء',
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh / تحديث',
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('Add customer / عميل'),
        backgroundColor: green,
        onPressed: _addCustomer,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 40,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry / إعادة'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: Center(
                child: ConstrainedBox(
                  // On wide screens keep the card column readable instead of
                  // stretching every ListTile across the whole viewport.
                  constraints: BoxConstraints(
                    maxWidth: Responsive.contentMaxWidth(context),
                  ),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      Responsive.horizontalPadding(context),
                      12,
                      Responsive.horizontalPadding(context),
                      88,
                    ),
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'All customers / كل العملاء',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_customers.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'No customers yet / لا يوجد عملاء',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        ..._customers.map(_customerCard),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
