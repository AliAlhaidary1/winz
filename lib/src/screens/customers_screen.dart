import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../utils/format.dart';
import '../theme/app_theme.dart';

/// Manage registered customers and their saved "usual" plays.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  static const Color green = Color(0xFF0B8A3E);

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

  Future<void> _load() async {
    setState(() => _loading = true);
    final state = context.read<AppState>();
    try {
      final customers = await state.getCustomers();
      final plays = <String, List<Map<String, dynamic>>>{};
      for (final c in customers) {
        final id = c['id'] as String;
        plays[id] = await state.getCustomerPlays(id);
      }
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _plays
          ..clear()
          ..addAll(plays);
        _loading = false;
        _error = null;
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
      SnackBar(content: Text(message), backgroundColor: background ?? green),
    );
  }

  Future<void> _addCustomer() async {
    final state = context.read<AppState>();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
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
      await state.addCustomer(
        name: name,
        phone: phoneCtrl.text.trim(),
        notes: notesCtrl.text.trim(),
      );
      await _load();
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

  Future<void> _selectCustomer(Map<String, dynamic> c) async {
    try {
      await context.read<AppState>().selectCustomer(c['id'] as String);
      await _load();
      _snack('Selected: ${c['name'] ?? ''} / تم الاختيار');
    } catch (e) {
      _snack(e.toString(), background: Colors.red);
    }
  }

  Future<void> _useDefault() async {
    try {
      await context.read<AppState>().useDefaultCustomer();
      await _load();
      _snack('Using default customer / العميل الافتراضي');
    } catch (e) {
      _snack(e.toString(), background: Colors.red);
    }
  }

  Future<void> _playUsual(Map<String, dynamic> c) async {
    try {
      final result = await context.read<AppState>().playCustomerUsual(
        c['id'] as String,
      );
      final added = asInt(result['added']);
      final skipped = (result['skipped'] as List?) ?? const [];
      final buffer = StringBuffer('Added $added play(s) / تمت الإضافة');
      if (skipped.isNotEmpty) {
        buffer.write(' • Skipped ${skipped.length}: ${skipped.join('; ')}');
      }
      await _load();
      _snack(buffer.toString());
      if (added > 0 && mounted) {
        Navigator.pushNamed(context, '/numbers');
      }
    } catch (e) {
      _snack(e.toString(), background: Colors.red);
    }
  }

  Widget _playsTile(String customerId) {
    final plays = _plays[customerId] ?? const <Map<String, dynamic>>[];
    if (plays.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Text(
          'No saved plays yet — add them from the sale screen cart',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
      );
    }
    return Column(
      children: plays.map((p) {
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
          ),
          subtitle: Text(
            '${p['betType'] ?? ''}'
            '${p['amount'] != null ? '  •  ${p['amount']}' : ''}'
            '${p['drawType'] != null && '${p['drawType']}'.isNotEmpty ? '  •  ${p['drawType']}' : ''}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        );
      }).toList(),
    );
  }

  Widget _customerCard(Map<String, dynamic> c) {
    final id = c['id'] as String;
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
          ListTile(
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
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ),
            trailing: Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              color: green,
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _playsTile(id),
            ),
          if (!isDefault)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Wrap(
                spacing: 4,
                runSpacing: 0,
                children: [
                  TextButton.icon(
                    onPressed: () => _selectCustomer(c),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Select / تحديد'),
                  ),
                  TextButton.icon(
                    onPressed: () => _playUsual(c),
                    icon: const Icon(Icons.playlist_play, size: 16),
                    label: const Text('Play usual / العادة'),
                  ),
                  TextButton.icon(
                    onPressed: () => _editCustomer(c),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit / تعديل'),
                  ),
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
        ],
      ),
    );
  }

  Widget _selectedCustomerCard() {
    final current = context.watch<AppState>().currentCustomer;
    final id = '${current['id'] ?? ''}';
    final isDefault = id == AppState.defaultCustomerId;
    final name = '${current['name'] ?? AppState.defaultCustomerName}';
    return Container(
      decoration: AppTheme.cardDecoration(borderColor: green),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.greenSoft,
              child: Icon(Icons.person, color: green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selected customer / العميل المحدد',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: isDefault ? null : _useDefault,
              icon: const Icon(Icons.restore, size: 16),
              label: const Text('Default / افتراضي'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers / العملاء'),
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                children: [
                  _selectedCustomerCard(),
                  const SizedBox(height: 16),
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
                        child: Text('No customers yet / لا يوجد عملاء'),
                      ),
                    )
                  else
                    ..._customers.map(_customerCard),
                ],
              ),
            ),
    );
  }
}
