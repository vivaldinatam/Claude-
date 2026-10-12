import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/attendance_calculator.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../services/location_service.dart';
import '../../widgets/common.dart';
import '../../widgets/location_map.dart';

class _DashboardData {
  final WorkSchedule? schedule;
  final List<WorkLocation> locations;
  final Attendance? latest;
  const _DashboardData(this.schedule, this.locations, this.latest);
}

class DashboardScreen extends StatefulWidget {
  final Profile profile;
  const DashboardScreen({super.key, required this.profile});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _data = _load();
  Position? _position;
  String? _positionError;
  bool _locating = false;
  bool _submitting = false;
  late DateTime _now = DateTime.now();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _refreshPosition();
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<_DashboardData> _load() async {
    final api = Api.instance;
    final results = await Future.wait([
      widget.profile.scheduleId == null
          ? Future<WorkSchedule?>.value(null)
          : api.schedule(widget.profile.scheduleId!),
      api.myLocations(),
      api.latestAttendance(),
    ]);
    return _DashboardData(
      results[0] as WorkSchedule?,
      results[1] as List<WorkLocation>,
      results[2] as Attendance?,
    );
  }

  Future<void> _reload() async {
    setState(() => _data = _load());
    await Future.wait([_data, _refreshPosition()]);
  }

  Future<Position?> _refreshPosition() async {
    setState(() {
      _locating = true;
      _positionError = null;
    });
    try {
      final p = await LocationService.currentPosition();
      if (mounted) setState(() => _position = p);
      return p;
    } catch (e) {
      if (mounted) setState(() => _positionError = e.toString());
      return null;
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Lokasi terdekat beserta jaraknya dari posisi saat ini.
  (WorkLocation, double)? _nearest(List<WorkLocation> locations, Position p) {
    (WorkLocation, double)? best;
    for (final l in locations) {
      final d = distanceInMeters(p.latitude, p.longitude, l.latitude, l.longitude);
      if (best == null || d < best.$2) best = (l, d);
    }
    return best;
  }

  bool _isOpenShift(Attendance? a) =>
      a != null && a.isOpen && DateTime.now().difference(a.checkInAt) < const Duration(hours: 24);

  bool _doneToday(Attendance? a) {
    if (a == null || a.isOpen) return false;
    final today = DateTime.now();
    return a.workDate.year == today.year &&
        a.workDate.month == today.month &&
        a.workDate.day == today.day;
  }

  Future<void> _submit(_DashboardData data, {required bool checkOut}) async {
    final position = await _refreshPosition();
    if (!mounted) return;
    if (position == null) {
      _showLocationProblem();
      return;
    }
    if (position.isMocked) {
      showError(context, 'Lokasi palsu (mock location) terdeteksi. Matikan aplikasi fake GPS.');
      return;
    }
    final nearest = _nearest(data.locations, position);
    if (nearest != null && nearest.$2 > nearest.$1.radiusM) {
      final proceed = await confirm(
        context,
        'Di luar area absensi',
        'Jarak Anda ke ${nearest.$1.name} sekitar ${nearest.$2.round()} m '
            '(maksimal ${nearest.$1.radiusM} m). Server kemungkinan akan menolak. Tetap kirim?',
      );
      if (!proceed || !mounted) return;
    }

    if (checkOut && data.latest?.scheduledEnd != null) {
      final preview = AttendanceCalculator.checkout(
        checkIn: data.latest!.checkInAt,
        checkOut: DateTime.now(),
        scheduledEnd: data.latest!.scheduledEnd,
        lateMinutes: data.latest!.lateMinutes,
        makeupEnabled: data.schedule?.makeupEnabled ?? true,
        isWorkDay: data.latest!.isWorkDay,
      );
      final lines = <String>[
        if (preview.earlyLeaveMinutes > 0)
          'Anda pulang ${fmtMinutes(preview.earlyLeaveMinutes)} lebih awal dari jadwal.',
        if (preview.lateDebtMinutes > 0)
          'Sisa keterlambatan yang belum diganti: ${fmtMinutes(preview.lateDebtMinutes)}.',
      ];
      if (lines.isNotEmpty) {
        final proceed = await confirm(context, 'Absen pulang sekarang?', lines.join('\n\n'));
        if (!proceed || !mounted) return;
      }
    }

    setState(() => _submitting = true);
    try {
      final result = checkOut
          ? await Api.instance.checkOut(position)
          : await Api.instance.checkIn(position);
      if (!mounted) return;
      await _showResult(result, checkOut: checkOut, schedule: data.schedule);
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showLocationProblem() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Lokasi tidak tersedia'),
        content: Text(_positionError ?? 'Gagal mendapatkan lokasi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tutup')),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              LocationService.openSettings();
            },
            child: const Text('Buka pengaturan'),
          ),
        ],
      ),
    );
  }

  Future<void> _showResult(Attendance a, {required bool checkOut, WorkSchedule? schedule}) {
    final lines = <String>[];
    if (!checkOut) {
      lines.add('Absen masuk tercatat pukul ${fmtTime(a.checkInAt)}.');
      if (!a.isWorkDay) {
        lines.add('Hari ini bukan hari kerja; seluruh jam kerja dihitung sebagai lembur.');
      } else if (a.lateMinutes > 0) {
        lines.add('Anda terlambat ${fmtMinutes(a.lateMinutes)}.');
        if (schedule?.makeupEnabled ?? true) {
          lines.add(
            'Ganti dengan pulang paling cepat pukul '
            '${fmtTime(a.scheduledEnd?.add(Duration(minutes: a.lateMinutes)))}.',
          );
        }
      } else {
        lines.add('Tepat waktu. Selamat bekerja!');
      }
    } else {
      lines.add('Absen pulang tercatat pukul ${fmtTime(a.checkOutAt)}.');
      lines.add('Total kerja: ${fmtMinutes(a.workedMinutes)}.');
      if (a.lateMinutes > 0) {
        lines.add(
          'Terlambat ${fmtMinutes(a.lateMinutes)}, sudah diganti '
          '${fmtMinutes(a.makeupMinutes)}, sisa ${fmtMinutes(a.lateDebtMinutes)}.',
        );
      }
      if (a.earlyLeaveMinutes > 0) lines.add('Pulang cepat ${fmtMinutes(a.earlyLeaveMinutes)}.');
      if (a.overtimeMinutes > 0) {
        final eligible = AttendanceCalculator.isOvertimeEligible(
          a.overtimeMinutes,
          schedule?.minOvertimeMin ?? 0,
        );
        lines.add(
          'Kelebihan jam ${fmtMinutes(a.overtimeMinutes)}. '
          '${eligible ? 'Ajukan lembur di menu Pengajuan agar disetujui admin.' : 'Belum mencapai minimal lembur (${schedule?.minOvertimeMin ?? 0} menit).'}',
        );
      }
    }
    return showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: Text(checkOut ? 'Absen pulang berhasil' : 'Absen masuk berhasil'),
        content: Text(lines.join('\n\n')),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<_DashboardData>(
      future: _data,
      onRefresh: _reload,
      builder: (context, data) {
        final latest = data.latest;
        final open = _isOpenShift(latest);
        final done = _doneToday(latest);
        final nearest = _position == null ? null : _nearest(data.locations, _position!);
        final inside = nearest != null && nearest.$2 <= nearest.$1.radiusM;
        final theme = Theme.of(context);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Halo, ${widget.profile.fullName}', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      '${_now.hour.toString().padLeft(2, '0')}:'
                      '${_now.minute.toString().padLeft(2, '0')}:'
                      '${_now.second.toString().padLeft(2, '0')}',
                      style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(fmtDate(_now)),
                    const SizedBox(height: 8),
                    Text(
                      data.schedule == null
                          ? 'Jadwal kerja belum diatur admin'
                          : 'Jadwal: ${data.schedule!.name} (${data.schedule!.hoursLabel})',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _todayCard(latest, open, done),
            const SizedBox(height: 12),
            _locationCard(data, nearest, inside),
            const SizedBox(height: 16),
            if (data.schedule == null)
              const Text(
                'Hubungi admin untuk mengatur jadwal kerja Anda sebelum absen.',
                textAlign: TextAlign.center,
              )
            else if (done)
              const FilledButton(onPressed: null, child: Text('Absensi hari ini selesai'))
            else
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  style: open
                      ? FilledButton.styleFrom(backgroundColor: Colors.orange.shade700)
                      : null,
                  onPressed: _submitting ? null : () => _submit(data, checkOut: open),
                  icon: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(open ? Icons.logout : Icons.login),
                  label: Text(
                    open ? 'Absen Pulang' : 'Absen Masuk',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _todayCard(Attendance? latest, bool open, bool done) {
    final show = open || done;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: _timeCol('Masuk', show ? fmtTime(latest!.checkInAt) : '--:--')),
            Expanded(child: _timeCol('Pulang', show ? fmtTime(latest!.checkOutAt) : '--:--')),
            Expanded(
              child: _timeCol(
                'Terlambat',
                show && latest!.lateMinutes > 0 ? fmtMinutes(latest.lateMinutes) : '-',
                color: show && latest!.lateMinutes > 0 ? Colors.orange.shade800 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeCol(String label, String value, {Color? color}) => Column(
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text(
        value,
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
      ),
    ],
  );

  Widget _locationCard(_DashboardData data, (WorkLocation, double)? nearest, bool inside) {
    final pos = _position;
    String status;
    Color color;
    if (_locating && pos == null) {
      status = 'Mencari lokasi...';
      color = Colors.grey;
    } else if (pos == null) {
      status = _positionError ?? 'Lokasi tidak tersedia';
      color = Colors.red;
    } else if (data.locations.isEmpty) {
      status = 'Belum ada lokasi absensi aktif';
      color = Colors.red;
    } else if (inside) {
      status = 'Di dalam area ${nearest!.$1.name} (${nearest.$2.round()} m)';
      color = Colors.green;
    } else {
      status =
          'Di luar area. ${nearest!.$1.name} berjarak ${nearest.$2.round()} m '
          '(maks. ${nearest.$1.radiusM} m)';
      color = Colors.red;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: LocationMap(
              locations: data.locations,
              userPosition: pos == null ? null : LatLng(pos.latitude, pos.longitude),
            ),
          ),
          ListTile(
            leading: Icon(Icons.location_on, color: color),
            title: Text(status, style: TextStyle(color: color)),
            subtitle: pos == null ? null : Text('Akurasi GPS ±${pos.accuracy.round()} m'),
            trailing: IconButton(
              tooltip: 'Perbarui lokasi',
              icon: _locating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              onPressed: _locating ? null : _refreshPosition,
            ),
          ),
        ],
      ),
    );
  }
}
