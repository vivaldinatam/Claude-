import 'package:flutter/material.dart';

import 'admin_recap_screen.dart';
import 'approvals_screen.dart';
import 'employees_screen.dart';
import 'locations_screen.dart';
import 'schedules_screen.dart';
import 'settings_screen.dart';

class AdminMenuScreen extends StatelessWidget {
  const AdminMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String, Widget)>[
      (
        Icons.fact_check_outlined,
        'Persetujuan',
        'Izin, sakit, cuti, dan lembur',
        const ApprovalsScreen(),
      ),
      (
        Icons.location_on_outlined,
        'Lokasi Absensi',
        'Titik GPS & radius absensi',
        const LocationsScreen(),
      ),
      (
        Icons.schedule,
        'Jadwal Kerja',
        'Jam masuk/pulang, toleransi, hari kerja',
        const SchedulesScreen(),
      ),
      (
        Icons.people_outline,
        'Karyawan',
        'Aktivasi, jadwal, lokasi, kuota cuti',
        const EmployeesScreen(),
      ),
      (
        Icons.summarize_outlined,
        'Rekap Karyawan',
        'Rekap bulanan seluruh karyawan',
        const AdminRecapScreen(),
      ),
      (
        Icons.settings_outlined,
        'Pengaturan',
        'Zona waktu & aturan ganti jam',
        const SettingsScreen(),
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final (icon, title, subtitle, page) in items)
          Card(
            child: ListTile(
              leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
            ),
          ),
      ],
    );
  }
}
