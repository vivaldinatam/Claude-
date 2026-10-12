import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../widgets/common.dart';
import '../employee/requests_screen.dart';

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  String _status = 'pending';
  late Future<List<LeaveRequest>> _leaves = Api.instance.leavesByStatus(_status);
  late Future<List<OvertimeRequest>> _overtimes = Api.instance.overtimesByStatus(_status);

  Future<void> _reload() async {
    setState(() {
      _leaves = Api.instance.leavesByStatus(_status);
      _overtimes = Api.instance.overtimesByStatus(_status);
    });
    await Future.wait([_leaves, _overtimes]);
  }

  /// Dialog catatan (+ menit untuk lembur). Mengembalikan null jika dibatalkan.
  Future<(String?, int?)?> _askNote({required bool approve, int? defaultMinutes}) {
    final note = TextEditingController();
    final minutes = TextEditingController(text: defaultMinutes?.toString());
    return showDialog<(String?, int?)>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(approve ? 'Setujui pengajuan' : 'Tolak pengajuan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (approve && defaultMinutes != null) ...[
              TextField(
                controller: minutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Menit lembur disetujui'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(c, (
              note.text.trim().isEmpty ? null : note.text.trim(),
              int.tryParse(minutes.text),
            )),
            child: Text(approve ? 'Setujui' : 'Tolak'),
          ),
        ],
      ),
    );
  }

  Future<void> _reviewLeave(LeaveRequest r, bool approve) async {
    final input = await _askNote(approve: approve);
    if (input == null) return;
    try {
      await Api.instance.reviewLeave(r.id, approve, note: input.$1);
      if (mounted) showInfo(context, approve ? 'Pengajuan disetujui.' : 'Pengajuan ditolak.');
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _reviewOvertime(OvertimeRequest r, bool approve) async {
    final input = await _askNote(approve: approve, defaultMinutes: r.requestedMinutes);
    if (input == null) return;
    try {
      await Api.instance.reviewOvertime(r.id, approve, minutes: input.$2, note: input.$1);
      if (mounted) showInfo(context, approve ? 'Lembur disetujui.' : 'Lembur ditolak.');
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _actions(VoidCallback onReject, VoidCallback onApprove) => _status != 'pending'
      ? const SizedBox.shrink()
      : Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: onReject, child: const Text('Tolak')),
            const SizedBox(width: 8),
            FilledButton(onPressed: onApprove, child: const Text('Setujui')),
          ],
        );

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Persetujuan'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Izin / Sakit / Cuti'),
              Tab(text: 'Lembur'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<String>(
                segments: [
                  for (final e in requestStatusLabels.entries)
                    ButtonSegment(value: e.key, label: Text(e.value)),
                ],
                selected: {_status},
                onSelectionChanged: (s) {
                  _status = s.first;
                  _reload();
                },
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  AsyncView<List<LeaveRequest>>(
                    future: _leaves,
                    onRefresh: _reload,
                    builder: (context, items) => items.isEmpty
                        ? const EmptyState('Tidak ada pengajuan.')
                        : ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            children: [
                              for (final r in items)
                                LeaveTile(
                                  request: r,
                                  trailing: _actions(
                                    () => _reviewLeave(r, false),
                                    () => _reviewLeave(r, true),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  AsyncView<List<OvertimeRequest>>(
                    future: _overtimes,
                    onRefresh: _reload,
                    builder: (context, items) => items.isEmpty
                        ? const EmptyState('Tidak ada pengajuan lembur.')
                        : ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            children: [
                              for (final r in items)
                                OvertimeTile(
                                  request: r,
                                  trailing: _actions(
                                    () => _reviewOvertime(r, false),
                                    () => _reviewOvertime(r, true),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
