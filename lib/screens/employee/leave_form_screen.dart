import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../widgets/common.dart';

class LeaveFormScreen extends StatefulWidget {
  final String type; // izin | sakit | cuti
  const LeaveFormScreen({super.key, required this.type});

  @override
  State<LeaveFormScreen> createState() => _LeaveFormScreenState();
}

class _LeaveFormScreenState extends State<LeaveFormScreen> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _attachment = TextEditingController();
  late DateTimeRange _range = DateTimeRange(start: _today, end: _today);
  bool _saving = false;

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _reason.dispose();
    _attachment.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: _today.subtract(const Duration(days: 30)),
      lastDate: _today.add(const Duration(days: 365)),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await Api.instance.submitLeave(
        type: widget.type,
        start: _range.start,
        end: _range.end,
        reason: _reason.text.trim(),
        attachmentUrl: _attachment.text,
      );
      if (!mounted) return;
      showInfo(context, 'Pengajuan terkirim, menunggu persetujuan admin.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = leaveTypeLabels[widget.type]!;
    final days = _range.end.difference(_range.start).inDays + 1;
    return Scaffold(
      appBar: AppBar(title: Text('Pengajuan $label')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(4),
              ),
              leading: const Icon(Icons.date_range),
              title: Text(
                _range.start == _range.end
                    ? fmtDate(_range.start)
                    : '${fmtShortDate(_range.start)} - ${fmtShortDate(_range.end)}',
              ),
              subtitle: Text('$days hari kalender'),
              onTap: _pickRange,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reason,
              maxLines: 3,
              decoration: InputDecoration(labelText: 'Alasan $label'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Wajib diisi' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _attachment,
              decoration: InputDecoration(
                labelText: widget.type == 'sakit'
                    ? 'Link surat dokter (opsional)'
                    : 'Link lampiran (opsional)',
                helperText: 'Misalnya link Google Drive',
              ),
            ),
            if (widget.type == 'cuti') ...[
              const SizedBox(height: 16),
              const Text(
                'Cuti dihitung berdasarkan hari kerja dan dipotong dari kuota '
                'cuti tahunan saat disetujui admin.',
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Mengirim...' : 'Kirim Pengajuan'),
            ),
          ],
        ),
      ),
    );
  }
}
