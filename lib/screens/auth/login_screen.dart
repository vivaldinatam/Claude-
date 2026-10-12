import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_register) {
        final res = await Api.instance.signUp(
          _email.text.trim(),
          _password.text,
          _name.text.trim(),
        );
        if (!mounted) return;
        if (res.session == null) {
          showInfo(context, 'Pendaftaran berhasil. Cek email untuk konfirmasi, lalu login.');
          setState(() => _register = false);
        }
      } else {
        await Api.instance.signIn(_email.text.trim(), _password.text);
      }
    } catch (e) {
      if (mounted) showError(context, e);
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
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.fingerprint, size: 72, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Absensi Karyawan',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _register ? 'Daftar akun baru' : 'Masuk ke akun Anda',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_register) ...[
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Nama lengkap'),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Wajib diisi' : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v ?? '').contains('@') ? null : 'Email tidak valid',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Kata sandi',
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v ?? '').length < 6 ? 'Minimal 6 karakter' : null,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_register ? 'Daftar' : 'Masuk'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _register = !_register),
                    child: Text(_register ? 'Sudah punya akun? Masuk' : 'Belum punya akun? Daftar'),
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
