import 'package:flutter/material.dart';

import '../../core/attendance_calculator.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _accuracy = TextEditingController();
  String _timezone = 'Asia/Jakarta';
  MakeupMode _mode = MakeupMode.sameDay;
  late final Future<void> _loaded = _load();
  bool _busy = false;

  static const _timezones = {
    'Asia/Jakarta': 'WIB (Asia/Jakarta)',
    'Asia/Makassar': 'WITA (Asia/Makassar)',
    'Asia/Jayapura': 'WIT (Asia/Jayapura)',
  };

  Future<void> _load() async {
    final s = await Api.instance.settings();
    _name.text = s.companyName;
    _accuracy.text = '${s.maxGpsAccuracyM}';
    _timezone = _timezones.containsKey(s.timezone) ? s.timezone : 'Asia/Jakarta';
    _mode = s.makeupMode;
  }

  @override
  void dispose() {
    _name.dispose();
    _accuracy.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Api.instance.updateSettings(
        CompanySettings(
          companyName: _name.text.trim(),
          timezone: _timezone,
          makeupMode: _mode,
          maxGpsAccuracyM: int.parse(_accuracy.text),
        ),
      );
      if (mounted) {
        showInfo(context, 'Pengaturan disimpan.');
        Navigator.pop(context);
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
      appBar: AppBar(title: const Text('Pengaturan')),
      body: FutureBuilder<void>(
        future: _loaded,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text(errorMessage(snap.error!)));
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nama perusahaan'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _timezone,
                  decoration: const InputDecoration(labelText: 'Zona waktu'),
                  items: [
                    for (final e in _timezones.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _timezone = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _accuracy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Batas akurasi GPS (meter)',
                    helperText: 'Absen ditolak jika akurasi GPS lebih buruk dari angka ini',
                  ),
                  validator: (v) =>
                      int.tryParse(v ?? '') == null || int.parse(v!) <= 0 ? 'Angka > 0' : null,
                ),
                const SectionTitle('Aturan ganti jam keterlambatan'),
                RadioGroup<MakeupMode>(
                  groupValue: _mode,
                  onChanged: (v) => setState(() => _mode = v!),
                  child: const Column(
                    children: [
                      RadioListTile<MakeupMode>(
                        contentPadding: EdgeInsets.zero,
                        value: MakeupMode.sameDay,
                        title: Text('Hari yang sama'),
                        subtitle: Text(
                          'Terlambat hanya bisa diganti dengan pulang lebih lama '
                          'di hari itu juga.',
                        ),
                      ),
                      RadioListTile<MakeupMode>(
                        contentPadding: EdgeInsets.zero,
                        value: MakeupMode.monthly,
                        title: Text('Akumulasi bulanan'),
                        subtitle: Text(
                          'Sisa terlambat boleh diganti dengan kelebihan jam di hari '
                          'lain pada bulan yang sama (yang tidak diajukan sebagai lembur).',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(onPressed: _busy ? null : _save, child: const Text('Simpan')),
              ],
            ),
          );
        },
      ),
    );
  }
}
