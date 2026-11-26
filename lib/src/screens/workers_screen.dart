import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../providers/app_state.dart';

class WorkersScreen extends StatefulWidget {
  const WorkersScreen({super.key});
  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  List<Map<String, dynamic>> _workers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final all = await db.getAccounts();
    if (!mounted) return;
    setState(() {
      _workers = all.where((e) => e['role'] != 'owner').toList();
      _loading = false;
    });
  }

  Future<void> _addWorker() async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final commCtrl = TextEditingController(text: '5.0');
    final myRole =
        (context.read<AppState>().currentUser?['role'] ?? 'manager').toString();
    final assignableRoles = <String>['cashier', 'supervisor'];
    if (myRole == 'owner') assignableRoles.add('manager');
    var selectedRole = 'cashier';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add Worker'),
        content: StatefulBuilder(
          builder: (c, setDialogState) => SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passCtrl,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: commCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Commission %',
                  hintText: '5.0',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final role in assignableRoles)
                    DropdownMenuItem(
                      value: role,
                      child: Text(
                        role[0].toUpperCase() + role.substring(1),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedRole = v);
                },
              ),
            ],
          ),
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (userCtrl.text.trim().isEmpty || passCtrl.text.isEmpty) return;
    final comm = double.tryParse(commCtrl.text.trim());
    if (comm == null || comm < 0 || comm > 100) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Commission must be a number between 0 and 100'),
            backgroundColor: Colors.red,
          ),
        );
      return;
    }
    final db = context.read<AppDatabase>();
    final id = 'acc_${DateTime.now().millisecondsSinceEpoch}';
    try {
      await db.insertAccount({
        'id': id,
        'username': userCtrl.text.trim(),
        'password': passCtrl.text,
        'role': selectedRole,
        'status': 'active',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'commission': comm,
      });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      return;
    }
    await _load();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Worker added'),
          backgroundColor: Color(0xFF0B8A3E),
        ),
      );
  }

  Future<void> _editCommission(Map<String, dynamic> w) async {
    final ctrl = TextEditingController(
      text: w['commission']?.toString() ?? '5.0',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          'Commission for ${w['username']}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Commission %',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(ctrl.text) ?? 0;
    final db = context.read<AppDatabase>();
    await db.updateAccountCommission(w['id'] as String, v);
    await _load();
  }

  Future<void> _deleteWorker(Map<String, dynamic> w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Deactivate Worker'),
        content: Text(
          'Deactivate ${w['username']}? Their account and sales history will be kept, but they can no longer sign in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final db = context.read<AppDatabase>();
    // Soft delete: keep the row so operatorId references stay valid in
    // cash_ledger / balance_movements / tickets.
    await db.deactivateAccount(w['id'] as String);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AppState>().isAdmin;
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Workers'),
          backgroundColor: const Color(0xFF0B8A3E),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Admin only')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workers - Manage'),
        backgroundColor: const Color(0xFF0B8A3E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('Add Worker'),
        backgroundColor: const Color(0xFF0B8A3E),
        onPressed: _addWorker,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _workers.isEmpty
          ? const Center(child: Text('No workers'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _workers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (c, i) {
                final w = _workers[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade50,
                      child: Text(
                        (w['username'] as String)[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      w['username'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${w["role"] ?? "cashier"} • ${w["commission"] ?? 0}% • ${w["status"]}',
                      style: const TextStyle(fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.edit,
                            size: 18,
                            color: Colors.blue,
                          ),
                          onPressed: () => _editCommission(w),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete,
                            size: 18,
                            color: Colors.red,
                          ),
                          onPressed: () => _deleteWorker(w),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
