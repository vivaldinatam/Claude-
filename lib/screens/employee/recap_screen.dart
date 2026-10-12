import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../widgets/common.dart';

class RecapScreen extends StatefulWidget {
  final String? employeeId;
  const RecapScreen({super.key, this.employeeId});

  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen> {
  DateTime _month = DateTime.now();
  late Future<List<MonthlyRecap>> _future = _load();

  Future<List<MonthlyRecap>> _load() =>
      Api.instance.monthlyRecap(_month, employeeId: widget.employeeId ?? Api.instance.uid);

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
          child: AsyncView<List<MonthlyRecap>>(
            future: _future,
            onRefresh: _reload,
            builder: (context, items) {
              if (items.isEmpty) return const EmptyState('Data rekap tidak tersedia.');
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                children: [RecapDetail(recap: items.first)],
              );
            },
          ),
        ),
      ],
    );
  }
}

class RecapDetail extends StatelessWidget {
  final MonthlyRecap recap;
  const RecapDetail({super.key, required this.recap});

  @override
  Widget build(BuildContext context) {
    final r = recap;
    Widget grid(List<Widget> children) => GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.05,
      children: children,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Kehadiran'),
        grid([
          StatTile(label: 'Hari kerja', value: '${r.workDays}', icon: Icons.calendar_month),
          StatTile(
            label: 'Hadir',
            value: '${r.presentDays}',
            icon: Icons.check_circle,
            color: Colors.green,
          ),
          StatTile(
            label: 'Tanpa keterangan',
            value: '${r.absentDays}',
            icon: Icons.cancel,
            color: Colors.red,
          ),
          StatTile(
            label: 'Izin',
            value: '${r.izinDays}',
            icon: Icons.event_note,
            color: Colors.blue,
          ),
          StatTile(
            label: 'Sakit',
            value: '${r.sakitDays}',
            icon: Icons.healing,
            color: Colors.purple,
          ),
          StatTile(
            label: 'Cuti',
            value: '${r.cutiDays}',
            icon: Icons.beach_access,
            color: Colors.teal,
          ),
        ]),
        const SectionTitle('Keterlambatan & Ganti Jam'),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              _row('Jumlah terlambat', '${r.lateCount} kali'),
              _row('Total jam terlambat', fmtMinutes(r.lateMinutes)),
              _row('Sudah diganti', fmtMinutes(r.makeupMinutes), color: Colors.green),
              _row(
                'Sisa belum diganti',
                fmtMinutes(r.lateDebtMinutes),
                color: r.lateDebtMinutes > 0 ? Colors.red : null,
                bold: true,
              ),
              _row('Pulang lebih awal', fmtMinutes(r.earlyLeaveMinutes)),
            ],
          ),
        ),
        const SectionTitle('Lembur'),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              _row('Kelebihan jam (setelah ganti jam)', fmtMinutes(r.overtimeMinutes)),
              _row(
                'Lembur disetujui',
                fmtMinutes(r.overtimeApprovedMinutes),
                color: Colors.green,
                bold: true,
              ),
            ],
          ),
        ),
        const SectionTitle('Cuti Tahunan'),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              _row('Kuota', '${r.leaveQuota} hari'),
              _row('Terpakai tahun ini', '${r.leaveUsedYear} hari'),
              _row('Sisa', '${r.leaveRemaining} hari', bold: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value, {Color? color, bool bold = false}) => ListTile(
    dense: true,
    title: Text(label),
    trailing: Text(
      value,
      style: TextStyle(
        color: color,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontSize: 14,
      ),
    ),
  );
}
