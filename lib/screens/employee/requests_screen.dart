import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../widgets/common.dart';
import 'leave_form_screen.dart';
import 'overtime_form_screen.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  late Future<List<LeaveRequest>> _leaves = Api.instance.myLeaves();
  late Future<List<OvertimeRequest>> _overtimes = Api.instance.myOvertimes();

  Future<void> _reloadLeaves() async {
    setState(() => _leaves = Api.instance.myLeaves());
    await _leaves;
  }

  Future<void> _reloadOvertimes() async {
    setState(() => _overtimes = Api.instance.myOvertimes());
    await _overtimes;
  }

  Future<void> _newRequest() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.event_note),
              title: const Text('Izin'),
              onTap: () => Navigator.pop(c, 'izin'),
            ),
            ListTile(
              leading: const Icon(Icons.healing),
              title: const Text('Sakit'),
              onTap: () => Navigator.pop(c, 'sakit'),
            ),
            ListTile(
              leading: const Icon(Icons.beach_access),
              title: const Text('Cuti'),
              onTap: () => Navigator.pop(c, 'cuti'),
            ),
            ListTile(
              leading: const Icon(Icons.more_time),
              title: const Text('Lembur'),
              onTap: () => Navigator.pop(c, 'lembur'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            choice == 'lembur' ? const OvertimeFormScreen() : LeaveFormScreen(type: choice),
      ),
    );
    if (saved == true) {
      choice == 'lembur' ? _reloadOvertimes() : _reloadLeaves();
    }
  }

  Future<void> _cancel(Future<void> Function() action, Future<void> Function() reload) async {
    if (!await confirm(context, 'Batalkan pengajuan?', 'Pengajuan ini akan dihapus.')) return;
    try {
      await action();
      await reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _newRequest,
          icon: const Icon(Icons.add),
          label: const Text('Ajukan'),
        ),
        body: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Izin / Sakit / Cuti'),
                Tab(text: 'Lembur'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  AsyncView<List<LeaveRequest>>(
                    future: _leaves,
                    onRefresh: _reloadLeaves,
                    builder: (context, items) {
                      if (items.isEmpty) return const EmptyState('Belum ada pengajuan.');
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                        children: [
                          for (final r in items)
                            LeaveTile(
                              request: r,
                              onCancel: r.status == 'pending'
                                  ? () =>
                                        _cancel(() => Api.instance.cancelLeave(r.id), _reloadLeaves)
                                  : null,
                            ),
                        ],
                      );
                    },
                  ),
                  AsyncView<List<OvertimeRequest>>(
                    future: _overtimes,
                    onRefresh: _reloadOvertimes,
                    builder: (context, items) {
                      if (items.isEmpty) return const EmptyState('Belum ada pengajuan lembur.');
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                        children: [
                          for (final r in items)
                            OvertimeTile(
                              request: r,
                              onCancel: r.status == 'pending'
                                  ? () => _cancel(
                                      () => Api.instance.cancelOvertime(r.id),
                                      _reloadOvertimes,
                                    )
                                  : null,
                            ),
                        ],
                      );
                    },
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

class LeaveTile extends StatelessWidget {
  final LeaveRequest request;
  final VoidCallback? onCancel;
  final Widget? trailing;
  const LeaveTile({super.key, required this.request, this.onCancel, this.trailing});

  @override
  Widget build(BuildContext context) {
    final r = request;
    final range = r.startDate == r.endDate
        ? fmtShortDate(r.startDate)
        : '${fmtShortDate(r.startDate)} - ${fmtShortDate(r.endDate)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${r.employeeName != null ? '${r.employeeName} - ' : ''}'
                    '${leaveTypeLabels[r.type]} (${r.calendarDays} hari)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                StatusChip(status: r.status, label: requestStatusLabels[r.status]!),
              ],
            ),
            const SizedBox(height: 4),
            Text(range),
            const SizedBox(height: 4),
            Text(r.reason, style: Theme.of(context).textTheme.bodySmall),
            if (r.attachmentUrl != null)
              Text('Lampiran: ${r.attachmentUrl}', style: Theme.of(context).textTheme.bodySmall),
            if (r.reviewNote != null && r.reviewNote!.isNotEmpty)
              Text(
                'Catatan admin: ${r.reviewNote}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            if (onCancel != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onCancel, child: const Text('Batalkan')),
              ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class OvertimeTile extends StatelessWidget {
  final OvertimeRequest request;
  final VoidCallback? onCancel;
  final Widget? trailing;
  const OvertimeTile({super.key, required this.request, this.onCancel, this.trailing});

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${r.employeeName != null ? '${r.employeeName} - ' : ''}'
                    'Lembur ${fmtShortDate(r.workDate)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                StatusChip(status: r.status, label: requestStatusLabels[r.status]!),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Diajukan: ${fmtMinutes(r.requestedMinutes)}'
              '${r.approvedMinutes != null ? ' • Disetujui: ${fmtMinutes(r.approvedMinutes!)}' : ''}',
            ),
            const SizedBox(height: 4),
            Text(r.reason, style: Theme.of(context).textTheme.bodySmall),
            if (r.reviewNote != null && r.reviewNote!.isNotEmpty)
              Text(
                'Catatan admin: ${r.reviewNote}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            if (onCancel != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onCancel, child: const Text('Batalkan')),
              ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
