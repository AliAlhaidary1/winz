import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController(text: 'agent1');
  final _passCtrl = TextEditingController(text: 'agent123');
  bool _loading = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      final ok = await context.read<AppState>().login(_userCtrl.text.trim(), _passCtrl.text);
      if (!mounted) return;
      setState(() => _loading = false);
      if (ok) {
        Navigator.of(context).pushReplacementNamed('/numbers');
      } else {
        setState(() => _error = 'Invalid credentials — try: admin / admin123, agent1 / agent123, cashier / cashier123');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Database error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  // Brand header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.cardBorder)),
                    child: Row(children: [
                      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppTheme.green, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.confirmation_number, color: Colors.white, size: 20)),
                      const SizedBox(width: 12),
                      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('NY LOTTERY POS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.8)),
                        Text('Numbers • Win 4 • Official', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                      ])),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppTheme.greenLight, borderRadius: BorderRadius.circular(20)), child: const Text('POS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.green))),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  // Card
                  Container(
                    decoration: AppTheme.cardDecoration(),
                    padding: const EdgeInsets.all(22),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('Welcome back', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      const Text('Sign in to continue to your store', style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _userCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Username', hintText: 'e.g. admin', prefixIcon: Icon(Icons.person_outline, size: 18)),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline, size: 18),
                          suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18), onPressed: () => setState(() => _obscure = !_obscure)),
                        ),
                        onSubmitted: (_) => _login(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Color(0xFFFFF1F1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Color(0xFFFFC9C9))), child: Row(children: [Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.error_outline, color: Colors.white, size: 14)), const SizedBox(width: 10), Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFB42318), fontSize: 12)))])),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          child: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Login →'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(children: [Expanded(child: Divider(color: AppTheme.cardBorder)), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Demo accounts', style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w600))), Expanded(child: Divider(color: AppTheme.cardBorder))]),
                      const SizedBox(height: 12),
                      _demoRow('Admin', 'admin / admin123', AppTheme.green),
                      const SizedBox(height: 8),
                      _demoRow('Agent', 'agent1 / agent123', AppTheme.blue),
                      const SizedBox(height: 8),
                      _demoRow('Cashier', 'cashier / cashier123', Colors.orange),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  const Text('Accounts are created by administrator • No public registration • 18+', style: TextStyle(fontSize: 10, color: AppTheme.textMuted), textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _demoRow(String role, String creds, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.12))),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(role, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        const Spacer(),
        Text(creds, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
      ]),
    );
  }
}
