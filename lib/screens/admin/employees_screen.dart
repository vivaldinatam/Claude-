import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../widgets/common.dart';
import '../employee/history_screen.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  late Future<List<Profile>> _future = Api.instance.employees();
  String _query = '';

  Future<void> _reload() async {
    setState(() => _future = Api.instance.employees());
    await _future;
  }

  Future<void> _open(Profile p) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EmployeeFormScreen(profile: p)),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Karyawan')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cari nama / kode / email',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Karyawan mendaftar sendiri lewat aplikasi, lalu admin mengaktifkan '
              'dan mengatur jadwal & lokasinya di sini.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: AsyncView<List<Profile>>(
              future: _future,
              onRefresh: _reload,
              builder: (context, all) {
                final items = all
                    .where(
                      (p) =>
                          _query.isEmpty ||
                          p.fullName.toLowerCase().contains(_query) ||
                          (p.employeeCode ?? '').toLowerCase().contains(_query) ||
                          (p.email ?? '').toLowerCase().contains(_query),
                    )
                    .toList();
                if (items.isEmpty) return const EmptyState('Tidak ada karyawan.');
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final p in items)
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(p.fullName.isEmpty ? '?' : p.fullName[0].toUpperCase()),
                          ),
                          title: Text(p.fullName),
                          subtitle: Text(
                            [
                              if (p.employeeCode != null) p.employeeCode!,
                              p.email ?? '',
                              if (p.isAdmin) 'Admin',
                            ].where((s) => s.isNotEmpty).join(' • '),
                          ),
                          trailing: p.isActive
                              ? (p.scheduleId == null
                                    ? const StatusChip(status: 'terlambat', label: 'Tanpa jadwal')
                                    : const StatusChip(status: 'approved', label: 'Aktif'))
                              : const StatusChip(status: 'pending', label: 'Belum aktif'),
                          onTap: () => _open(p),
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

class EmployeeFormScreen extends StatefulWidget {
  final Profile profile;
  const EmployeeFormScreen({super.key, required this.profile});

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.fullName);
  late final _code = TextEditingController(text: widget.profile.employeeCode);
  late final _phone = TextEditingController(text: widget.profile.phone);
  late final _position = TextEditingController(text: widget.profile.position);
  late final _quota = TextEditingController(text: '${widget.profile.annualLeaveQuota}');
  late String _role = widget.profile.role;
  late String? _scheduleId = widget.profile.scheduleId;
  late bool _active = widget.profile.isActive;
  Set<String> _locationIds = {};
  late final Future<(List<WorkSchedule>, List<WorkLocation>)> _options = _loadOptions();
  bool _busy = false;

  Future<(List<WorkSchedule>, List<WorkLocation>)> _loadOptions() async {
    final api = Api.instance;
    final schedules = await api.schedules();
    final locations = await api.locations();
    _locationIds = await api.employeeLocationIds(widget.profile.id);
    return (schedules, locations);
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _phone, _position, _quota]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (widget.profile.id == Api.instance.uid && _role != 'admin') {
      final ok = await confirm(
        context,
        'Turunkan hak admin Anda?',
        'Anda tidak akan bisa membuka menu Admin lagi.',
      );
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      String? clean(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
      await Api.instance.updateEmployee(
        Profile(
          id: widget.profile.id,
          fullName: _name.text.trim(),
          email: widget.profile.email,
          employeeCode: clean(_code),
          phone: clean(_phone),
          position: clean(_position),
          role: _role,
          scheduleId: _scheduleId,
          annualLeaveQuota: int.parse(_quota.text),
          isActive: _active,
        ),
      );
      await Api.instance.setEmployeeLocations(widget.profile.id, _locationIds);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Karyawan'),
        actions: [
          IconButton(
            tooltip: 'Riwayat absensi',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text('Riwayat ${widget.profile.fullName}')),
                  body: HistoryScreen(employeeId: widget.profile.id),
                ),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<(List<WorkSchedule>, List<WorkLocation>)>(
        future: _options,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text(errorMessage(snap.error!)));
          final (schedules, locations) = snap.data!;
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(widget.profile.email ?? '', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Akun aktif'),
                  subtitle: const Text('Hanya akun aktif yang bisa absen'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nama lengkap'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(labelText: 'Kode / NIK karyawan'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _position,
                  decoration: const InputDecoration(labelText: 'Jabatan'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'No. telepon'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Peran'),
                  items: const [
                    DropdownMenuItem(value: 'employee', child: Text('Karyawan')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (v) => setState(() => _role = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: schedules.any((s) => s.id == _scheduleId) ? _scheduleId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Jadwal kerja'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('- Belum diatur -')),
                    for (final s in schedules)
                      DropdownMenuItem<String?>(
                        value: s.id,
                        child: Text('${s.name} (${s.hoursLabel})'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _scheduleId = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _quota,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Kuota cuti tahunan (hari)'),
                  validator: (v) =>
                      int.tryParse(v ?? '') == null || int.parse(v!) < 0 ? 'Angka >= 0' : null,
                ),
                const SectionTitle('Lokasi absensi yang diizinkan'),
                const Text(
                  'Jika tidak ada yang dipilih, karyawan bisa absen di semua lokasi aktif.',
                  style: TextStyle(fontSize: 12),
                ),
                for (final l in locations)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.name),
                    subtitle: Text('radius ${l.radiusM} m${l.isActive ? '' : ' • nonaktif'}'),
                    value: _locationIds.contains(l.id),
                    onChanged: (v) => setState(
                      () => v == true ? _locationIds.add(l.id!) : _locationIds.remove(l.id),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : _save, child: const Text('Simpan')),
              ],
            ),
          );
        },
      ),
    );
  }
}
