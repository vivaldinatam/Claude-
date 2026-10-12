import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../widgets/common.dart';

class HistoryScreen extends StatefulWidget {
  /// Jika diisi (oleh admin), tampilkan riwayat karyawan tersebut.
  final String? employeeId;
  const HistoryScreen({super.key, this.employeeId});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _month = DateTime.now();
  late Future<List<Attendance>> _future = _load();

  Future<List<Attendance>> _load() =>
      Api.instance.attendances(_month, employeeId: widget.employeeId ?? Api.instance.uid);

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MonthSelector(
          month: _month,
          onChanged: (m) {
            _month = m;
            _reload();
          },
        ),
        Expanded(
          child: AsyncView<List<Attendance>>(
            future: _future,
            onRefresh: _reload,
            builder: (context, items) {
              if (items.isEmpty) return const EmptyState('Belum ada absensi di bulan ini.');
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => AttendanceCard(attendance: items[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class AttendanceCard extends StatelessWidget {
  final Attendance attendance;
  const AttendanceCard({super.key, required this.attendance});

  @override
  Widget build(BuildContext context) {
    final a = attendance;
    final details = <String>[
      if (a.lateMinutes > 0) 'Terlambat ${fmtMinutes(a.lateMinutes)}',
      if (a.makeupMinutes > 0) 'Diganti ${fmtMinutes(a.makeupMinutes)}',
      if (!a.isOpen && a.lateDebtMinutes > 0) 'Sisa ${fmtMinutes(a.lateDebtMinutes)}',
      if (a.earlyLeaveMinutes > 0) 'Pulang cepat ${fmtMinutes(a.earlyLeaveMinutes)}',
      if (a.overtimeMinutes > 0) 'Lebih ${fmtMinutes(a.overtimeMinutes)}',
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    a.employeeName != null
                        ? '${a.employeeName} - ${fmtShortDate(a.workDate)}'
                        : fmtDate(a.workDate),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                StatusChip(status: a.status, label: a.statusLabel),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.login, size: 16),
                Text(' ${fmtTime(a.checkInAt)}'),
                const SizedBox(width: 16),
                const Icon(Icons.logout, size: 16),
                Text(' ${fmtTime(a.checkOutAt)}'),
                const Spacer(),
                if (!a.isOpen) Text(fmtMinutes(a.workedMinutes)),
              ],
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(details.join(' • '), style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
