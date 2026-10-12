import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../widgets/common.dart';
import 'admin/admin_menu_screen.dart';
import 'employee/dashboard_screen.dart';
import 'employee/history_screen.dart';
import 'employee/recap_screen.dart';
import 'employee/requests_screen.dart';
import 'profile_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late Future<Profile?> _profile = Api.instance.myProfile();
  int _index = 0;

  Future<void> _reload() async {
    setState(() => _profile = Api.instance.myProfile());
    await _profile;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: _profile,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final profile = snap.data;
        if (snap.hasError || profile == null || !profile.isActive) {
          return _InactiveScreen(
            message: snap.hasError
                ? errorMessage(snap.error!)
                : 'Akun Anda menunggu aktivasi oleh admin.\n'
                      'Hubungi admin agar akun diaktifkan dan jadwal kerja diatur.',
            onRetry: _reload,
          );
        }

        final pages = <Widget>[
          DashboardScreen(profile: profile),
          const HistoryScreen(),
          const RequestsScreen(),
          const RecapScreen(),
          if (profile.isAdmin) const AdminMenuScreen(),
        ];
        final destinations = <NavigationDestination>[
          const NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Beranda'),
          const NavigationDestination(icon: Icon(Icons.history), label: 'Riwayat'),
          const NavigationDestination(icon: Icon(Icons.assignment_outlined), label: 'Pengajuan'),
          const NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Rekap'),
          if (profile.isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.admin_panel_settings_outlined),
              label: 'Admin',
            ),
        ];
        final titles = ['Absensi', 'Riwayat Absensi', 'Pengajuan', 'Rekap Bulanan', 'Admin'];
        final index = _index.clamp(0, pages.length - 1);

        return Scaffold(
          appBar: AppBar(
            title: Text(titles[index]),
            actions: [
              IconButton(
                tooltip: 'Profil',
                icon: const Icon(Icons.account_circle_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ProfileScreen(profile: profile)),
                ),
              ),
            ],
          ),
          body: IndexedStack(index: index, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: destinations,
          ),
        );
      },
    );
  }
}

class _InactiveScreen extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _InactiveScreen({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Absensi Karyawan')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top, size: 56),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Muat ulang')),
              TextButton(
                onPressed: () async {
                  try {
                    await Api.instance.signOut();
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                child: const Text('Keluar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
