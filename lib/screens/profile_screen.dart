import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatelessWidget {
  final Profile profile;
  const ProfileScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: FutureBuilder<WorkSchedule?>(
        future: profile.scheduleId == null
            ? Future.value(null)
            : Api.instance.schedule(profile.scheduleId!),
        builder: (context, snap) {
          final schedule = snap.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CircleAvatar(
                radius: 36,
                child: Text(
                  profile.fullName.isEmpty ? '?' : profile.fullName[0].toUpperCase(),
                  style: const TextStyle(fontSize: 28),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                profile.fullName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(profile.isAdmin ? 'Admin' : 'Karyawan', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    _row(Icons.badge_outlined, 'Kode karyawan', profile.employeeCode ?? '-'),
                    _row(Icons.email_outlined, 'Email', profile.email ?? '-'),
                    _row(Icons.phone_outlined, 'Telepon', profile.phone ?? '-'),
                    _row(Icons.work_outline, 'Jabatan', profile.position ?? '-'),
                    _row(
                      Icons.schedule,
                      'Jadwal kerja',
                      schedule == null
                          ? 'Belum diatur'
                          : '${schedule.name} (${schedule.hoursLabel})',
                    ),
                    if (schedule != null)
                      _row(Icons.calendar_month, 'Hari kerja', schedule.daysLabel),
                    _row(
                      Icons.beach_access_outlined,
                      'Kuota cuti tahunan',
                      '${profile.annualLeaveQuota} hari',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Keluar'),
                onPressed: () async {
                  try {
                    await Api.instance.signOut();
                    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) =>
      ListTile(leading: Icon(icon), title: Text(label), subtitle: Text(value), dense: true);
}
