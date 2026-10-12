import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../widgets/common.dart';
import '../employee/history_screen.dart';
import '../employee/recap_screen.dart';

class AdminRecapScreen extends StatefulWidget {
  const AdminRecapScreen({super.key});

  @override
  State<AdminRecapScreen> createState() => _AdminRecapScreenState();
}

class _AdminRecapScreenState extends State<AdminRecapScreen> {
  DateTime _month = DateTime.now();
  late Future<List<MonthlyRecap>> _future = Api.instance.monthlyRecap(_month);

  Future<void> _reload() async {
    setState(() => _future = Api.instance.monthlyRecap(_month));
    await _future;
  }

  void _openDetail(MonthlyRecap r) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(r.fullName),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Rekap'),
                  Tab(text: 'Riwayat'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                RecapScreen(employeeId: r.employeeId),
                HistoryScreen(employeeId: r.employeeId),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rekap Karyawan')),
      body: Column(
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
                if (items.isEmpty) return const EmptyState('Belum ada karyawan aktif.');
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: [
                    for (final r in items)
                      Card(
                        child: ListTile(
                          title: Text(r.fullName),
                          subtitle: Text(
                            'Hadir ${r.presentDays}/${r.workDays} • Alpa ${r.absentDays} • '
                            'Izin ${r.izinDays} • Sakit ${r.sakitDays} • Cuti ${r.cutiDays}\n'
                            'Terlambat ${r.lateCount}x (${fmtMinutes(r.lateMinutes)}) • '
                            'Sisa ganti jam ${fmtMinutes(r.lateDebtMinutes)}\n'
                            'Lembur disetujui ${fmtMinutes(r.overtimeApprovedMinutes)}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openDetail(r),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
