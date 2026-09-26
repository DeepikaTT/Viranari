import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/session.dart';
import '../core/theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.session});
  final AppSession session;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController(text: '+91');
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _validPhone(String value) => RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value);

  Future<void> _submit() async {
    final phone = _phone.text.trim().replaceAll(' ', '');
    if (_email.text.trim().isEmpty ||
        _password.text.length < 8 ||
        (_register && _name.text.trim().length < 2) ||
        (_register && !_validPhone(phone))) {
      setState(() => _error = 'Enter a valid email, name, +country-code phone number, and password of at least 8 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await widget.session.register(
          _name.text.trim(),
          _email.text.trim(),
          _password.text,
          phoneE164: phone,
        );
      } else {
        await widget.session.login(_email.text.trim(), _password.text);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not connect to ViraNari backend.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: ViraColors.plum),
                    child: const Icon(Icons.shield_rounded, color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 22),
                  Text('ViraNari', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900, color: ViraColors.plum)),
                  const SizedBox(height: 8),
                  Text(
                    _register ? 'Create your safety profile.' : 'Courage connected. Safety that confirms delivery.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: ViraColors.mutedPlum),
                  ),
                  const SizedBox(height: 28),
                  if (_register) ...[
                    TextField(controller: _name, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person_outline))),
                    const SizedBox(height: 14),
                  ],
                  TextField(controller: _email, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email))),
                  if (_register) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Phone (+country code)',
                        helperText: 'Used only so trusted contacts can call you during an emergency.',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(controller: _password, obscureText: true, onSubmitted: (_) => _submit(), decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline))),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: ViraColors.dangerSoft, borderRadius: BorderRadius.circular(14)),
                      child: Text(_error!, style: const TextStyle(color: ViraColors.pinkDark, fontWeight: FontWeight.w600)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_register ? Icons.person_add_alt_1 : Icons.login),
                    label: Text(_register ? 'Create account' : 'Sign in'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _register = !_register),
                    child: Text(_register ? 'Already registered? Sign in' : 'New to ViraNari? Create account'),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Location is shared only during an SOS. Phone numbers are exposed only to accepted Trusted Circle relationships.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ViraColors.mutedPlum, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
