import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../widgets/common.dart';

class SchedulesScreen extends StatefulWidget {
  const SchedulesScreen({super.key});

  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  late Future<List<WorkSchedule>> _future = Api.instance.schedules();

  Future<void> _reload() async {
    setState(() => _future = Api.instance.schedules());
    await _future;
  }

  Future<void> _open([WorkSchedule? s]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ScheduleFormScreen(schedule: s)),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jadwal Kerja')),
      floatingActionButton: FloatingActionButton(onPressed: _open, child: const Icon(Icons.add)),
      body: AsyncView<List<WorkSchedule>>(
        future: _future,
        onRefresh: _reload,
        builder: (context, items) {
          if (items.isEmpty) {
            return const EmptyState(
              'Belum ada jadwal. Tekan + untuk menambah.',
              icon: Icons.schedule,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final s in items)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text('${s.name} (${s.hoursLabel})'),
                    subtitle: Text(
                      '${s.daysLabel}\n'
                      'Toleransi ${s.lateToleranceMin} mnt • min. lembur ${s.minOvertimeMin} mnt • '
                      'ganti jam ${s.makeupEnabled ? 'aktif' : 'nonaktif'}',
                    ),
                    isThreeLine: true,
                    onTap: () => _open(s),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class ScheduleFormScreen extends StatefulWidget {
  final WorkSchedule? schedule;
  const ScheduleFormScreen({super.key, this.schedule});

  @override
  State<ScheduleFormScreen> createState() => _ScheduleFormScreenState();
}

class _ScheduleFormScreenState extends State<ScheduleFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.schedule?.name ?? 'Reguler');
  late final _tolerance = TextEditingController(text: '${widget.schedule?.lateToleranceMin ?? 0}');
  late final _minOvertime = TextEditingController(text: '${widget.schedule?.minOvertimeMin ?? 30}');
  late TimeOfDay _start = widget.schedule?.startTime ?? const TimeOfDay(hour: 8, minute: 0);
  late TimeOfDay _end = widget.schedule?.endTime ?? const TimeOfDay(hour: 17, minute: 0);
  late final Set<int> _days = {
    ...(widget.schedule?.workDays ?? const [1, 2, 3, 4, 5]),
  };
  late bool _makeup = widget.schedule?.makeupEnabled ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _tolerance.dispose();
    _minOvertime.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final t = await showTimePicker(context: context, initialTime: start ? _start : _end);
    if (t != null) setState(() => start ? _start = t : _end = t);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_days.isEmpty) {
      showError(context, 'Pilih minimal satu hari kerja.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.instance.saveSchedule(
        WorkSchedule(
          id: widget.schedule?.id,
          name: _name.text.trim(),
          startTime: _start,
          endTime: _end,
          lateToleranceMin: int.parse(_tolerance.text),
          workDays: _days.toList()..sort(),
          minOvertimeMin: int.parse(_minOvertime.text),
          makeupEnabled: _makeup,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await confirm(
      context,
      'Hapus jadwal?',
      'Karyawan dengan jadwal ini harus diberi jadwal baru agar bisa absen.',
    )) {
      return;
    }
    try {
      await Api.instance.deleteSchedule(widget.schedule!.id!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String? _intValidator(String? v) =>
      int.tryParse(v ?? '') == null || int.parse(v!) < 0 ? 'Angka >= 0' : null;

  @override
  Widget build(BuildContext context) {
    final overnight = _end.hour * 60 + _end.minute <= _start.hour * 60 + _start.minute;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.schedule == null ? 'Tambah Jadwal' : 'Ubah Jadwal'),
        actions: [
          if (widget.schedule != null)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nama jadwal (mis. Shift Pagi)'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Wajib diisi' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pick(true),
                    child: Text('Masuk ${fmtTimeOfDay(_start)}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pick(false),
                    child: Text('Pulang ${fmtTimeOfDay(_end)}'),
                  ),
                ),
              ],
            ),
            if (overnight)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Shift malam: jam pulang di hari berikutnya.'),
              ),
            const SizedBox(height: 16),
            const Text('Hari kerja'),
            Wrap(
              spacing: 6,
              children: [
                for (final e in dayNames.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: _days.contains(e.key),
                    onSelected: (v) => setState(() => v ? _days.add(e.key) : _days.remove(e.key)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tolerance,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Toleransi terlambat (menit)',
                helperText: 'Datang dalam batas ini tidak dihitung terlambat',
              ),
              validator: _intValidator,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _minOvertime,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Minimal lembur (menit)',
                helperText: 'Kelebihan jam di bawah angka ini tidak bisa diajukan lembur',
              ),
              validator: _intValidator,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Wajib ganti jam keterlambatan'),
              subtitle: const Text(
                'Kelebihan jam pulang dipakai menutup keterlambatan sebelum dihitung lembur',
              ),
              value: _makeup,
              onChanged: (v) => setState(() => _makeup = v),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Simpan')),
          ],
        ),
      ),
    );
  }
}
