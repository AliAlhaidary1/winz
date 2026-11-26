import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../utils/responsive.dart';

/// Lets the signed-in user change their own username and password.
class ChangeCredentialsScreen extends StatefulWidget {
  const ChangeCredentialsScreen({super.key});

  @override
  State<ChangeCredentialsScreen> createState() => _ChangeCredentialsScreenState();
}

class _ChangeCredentialsScreenState extends State<ChangeCredentialsScreen> {
  static const green = Color(0xFF0B8A3E);
  final _form = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newUsername = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().currentUser;
    _newUsername.text = (user?['username'] ?? '').toString();
  }

  @override
  void dispose() {
    _currentPassword.dispose();
    _newUsername.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await context.read<AppState>().changeCredentials(
        currentPassword: _currentPassword.text,
        newUsername: _newUsername.text,
        newPassword: _newPassword.text,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = 'Username and password updated';
      });
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        backgroundColor: green,
        foregroundColor: Colors.white,
        title: const Text(
          'Change Credentials',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Update your login details',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'You must enter your current password to save changes.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 18),
                      _field(
                        controller: _currentPassword,
                        label: 'Current password',
                        icon: Icons.lock_outline,
                        obscure: true,
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Enter current password'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _newUsername,
                        label: 'New username',
                        icon: Icons.person_outline,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter a username'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _newPassword,
                        label: 'New password',
                        icon: Icons.password,
                        obscure: true,
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Enter a new password'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _confirmPassword,
                        label: 'Confirm new password',
                        icon: Icons.password,
                        obscure: true,
                        validator: (v) => v != _newPassword.text
                            ? 'Passwords do not match'
                            : null,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(backgroundColor: green),
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: Text(_saving ? 'Saving…' : 'Save changes'),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _message!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _message!.contains('updated')
                                ? green
                                : Colors.red,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
