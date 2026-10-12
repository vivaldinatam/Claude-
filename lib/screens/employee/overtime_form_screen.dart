import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../widgets/common.dart';

class OvertimeFormScreen extends StatefulWidget {
  const OvertimeFormScreen({super.key});

  @override
  State<OvertimeFormScreen> createState() => _OvertimeFormScreenState();
}

class _OvertimeFormScreenState extends State<OvertimeFormScreen> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _minutes = TextEditingController();
  late Future<List<Attendance>> _attendances;
  Attendance? _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // absensi bulan ini & bulan lalu yang punya kelebihan jam
    _attendances =
        Future.wait([
          Api.instance.attendances(now, employeeId: Api.instance.uid),
          Api.instance.attendances(DateTime(now.year, now.month - 1), employeeId: Api.instance.uid),
        ]).then(
          (lists) =>
              lists.expand((l) => l).where((a) => !a.isOpen && a.overtimeMinutes > 0).toList(),
        );
  }

  @override
  void dispose() {
    _reason.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _selected == null) return;
    setState(() => _saving = true);
    try {
      await Api.instance.submitOvertime(
        date: _selected!.workDate,
        minutes: int.parse(_minutes.text),
        reason: _reason.text.trim(),
      );
      if (!mounted) return;
      showInfo(context, 'Pengajuan lembur terkirim.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengajuan Lembur')),
      body: FutureBuilder<List<Attendance>>(
        future: _attendances,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Belum ada absensi dengan kelebihan jam.\n\n'
                  'Lembur dihitung dari jam pulang yang melewati jadwal, '
                  'setelah dipotong ganti jam keterlambatan.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<Attendance>(
                  initialValue: _selected,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tanggal lembur'),
                  items: [
                    for (final a in items)
                      DropdownMenuItem(
                        value: a,
                        child: Text(
                          '${fmtShortDate(a.workDate)} • lebih ${fmtMinutes(a.overtimeMinutes)}',
                        ),
                      ),
                  ],
                  validator: (v) => v == null ? 'Pilih tanggal' : null,
                  onChanged: (a) => setState(() {
                    _selected = a;
                    _minutes.text = '${a!.overtimeMinutes}';
                  }),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Durasi lembur (menit)'),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n <= 0) return 'Masukkan angka menit';
                    if (_selected != null && n > _selected!.overtimeMinutes) {
                      return 'Maksimal ${_selected!.overtimeMinutes} menit (kelebihan jam aktual)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _reason,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Pekerjaan yang dilakukan'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Mengirim...' : 'Kirim Pengajuan'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
