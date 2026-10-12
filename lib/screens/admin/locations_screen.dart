import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../services/location_service.dart';
import '../../widgets/common.dart';
import '../../widgets/location_map.dart';

class LocationsScreen extends StatefulWidget {
  const LocationsScreen({super.key});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  late Future<List<WorkLocation>> _future = Api.instance.locations();

  Future<void> _reload() async {
    setState(() => _future = Api.instance.locations());
    await _future;
  }

  Future<void> _open([WorkLocation? l]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => LocationFormScreen(location: l)),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lokasi Absensi')),
      floatingActionButton: FloatingActionButton(onPressed: _open, child: const Icon(Icons.add)),
      body: AsyncView<List<WorkLocation>>(
        future: _future,
        onRefresh: _reload,
        builder: (context, items) {
          if (items.isEmpty) {
            return const EmptyState(
              'Belum ada lokasi. Tekan + untuk menambah.',
              icon: Icons.location_off_outlined,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final l in items)
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.location_on,
                      color: l.isActive ? Colors.green : Colors.grey,
                    ),
                    title: Text(l.name),
                    subtitle: Text(
                      '${l.address ?? ''}\n'
                      '${l.latitude.toStringAsFixed(6)}, ${l.longitude.toStringAsFixed(6)} • '
                      'radius ${l.radiusM} m${l.isActive ? '' : ' • nonaktif'}',
                    ),
                    isThreeLine: true,
                    onTap: () => _open(l),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class LocationFormScreen extends StatefulWidget {
  final WorkLocation? location;
  const LocationFormScreen({super.key, this.location});

  @override
  State<LocationFormScreen> createState() => _LocationFormScreenState();
}

class _LocationFormScreenState extends State<LocationFormScreen> {
  final _form = GlobalKey<FormState>();
  final _map = MapController();
  late final _name = TextEditingController(text: widget.location?.name);
  late final _address = TextEditingController(text: widget.location?.address);
  late final _lat = TextEditingController(text: widget.location?.latitude.toString());
  late final _lng = TextEditingController(text: widget.location?.longitude.toString());
  late int _radius = widget.location?.radiusM ?? 100;
  late bool _active = widget.location?.isActive ?? true;
  bool _busy = false;

  LatLng? get _point {
    final lat = double.tryParse(_lat.text);
    final lng = double.tryParse(_lng.text);
    return lat == null || lng == null ? null : LatLng(lat, lng);
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setPoint(LatLng p, {bool move = false}) {
    setState(() {
      _lat.text = p.latitude.toStringAsFixed(7);
      _lng.text = p.longitude.toStringAsFixed(7);
    });
    if (move) _map.move(p, 17);
  }

  Future<void> _useMyLocation() async {
    setState(() => _busy = true);
    try {
      final p = await LocationService.currentPosition();
      _setPoint(LatLng(p.latitude, p.longitude), move: true);
      if (mounted) showInfo(context, 'Lokasi diambil (akurasi ±${p.accuracy.round()} m).');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Api.instance.saveLocation(
        WorkLocation(
          id: widget.location?.id,
          name: _name.text.trim(),
          address: _address.text.trim().isEmpty ? null : _address.text.trim(),
          latitude: double.parse(_lat.text),
          longitude: double.parse(_lng.text),
          radiusM: _radius,
          isActive: _active,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await confirm(
      context,
      'Hapus lokasi?',
      'Riwayat absensi tetap tersimpan. Lokasi ini tidak bisa dipakai lagi.',
    )) {
      return;
    }
    try {
      await Api.instance.deleteLocation(widget.location!.id!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String? _coordValidator(String? v, double limit) {
    final d = double.tryParse(v ?? '');
    if (d == null) return 'Angka tidak valid';
    if (d.abs() > limit) return 'Di luar rentang';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.location == null ? 'Tambah Lokasi' : 'Ubah Lokasi'),
        actions: [
          if (widget.location != null)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nama lokasi (mis. Kantor Pusat)'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Wajib diisi' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Alamat (opsional)'),
            ),
            const SizedBox(height: 12),
            const Text('Ketuk peta untuk memilih titik, atau gunakan lokasi Anda saat ini.'),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 260,
                child: LocationMap(
                  controller: _map,
                  selected: _point,
                  selectedRadius: _radius,
                  onTap: _setPoint,
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _useMyLocation,
              icon: const Icon(Icons.my_location),
              label: const Text('Gunakan lokasi saya saat ini'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _lat,
                    decoration: const InputDecoration(labelText: 'Latitude'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    validator: (v) => _coordValidator(v, 90),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lng,
                    decoration: const InputDecoration(labelText: 'Longitude'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    validator: (v) => _coordValidator(v, 180),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Radius absensi: $_radius meter'),
            Slider(
              value: _radius.toDouble(),
              min: 10,
              max: 1000,
              divisions: 99,
              label: '$_radius m',
              onChanged: (v) => setState(() => _radius = v.round()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lokasi aktif'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Simpan')),
          ],
        ),
      ),
    );
  }
}
