import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';

/// Peta OpenStreetMap: lingkaran radius lokasi absensi + posisi pengguna.
class LocationMap extends StatelessWidget {
  final List<WorkLocation> locations;
  final LatLng? userPosition;
  final LatLng? selected;
  final int? selectedRadius;
  final void Function(LatLng point)? onTap;
  final MapController? controller;

  const LocationMap({
    super.key,
    this.locations = const [],
    this.userPosition,
    this.selected,
    this.selectedRadius,
    this.onTap,
    this.controller,
  });

  LatLng get _center =>
      selected ??
      userPosition ??
      (locations.isNotEmpty
          ? LatLng(locations.first.latitude, locations.first.longitude)
          : const LatLng(-6.200000, 106.816666)); // Jakarta

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: _center,
        initialZoom: 16,
        onTap: onTap == null ? null : (_, point) => onTap!(point),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.vivaldinatam.absensi_karyawan',
        ),
        CircleLayer(
          circles: [
            for (final l in locations)
              CircleMarker(
                point: LatLng(l.latitude, l.longitude),
                radius: l.radiusM.toDouble(),
                useRadiusInMeter: true,
                color: primary.withValues(alpha: 0.15),
                borderColor: primary,
                borderStrokeWidth: 2,
              ),
            if (selected != null && selectedRadius != null)
              CircleMarker(
                point: selected!,
                radius: selectedRadius!.toDouble(),
                useRadiusInMeter: true,
                color: Colors.orange.withValues(alpha: 0.2),
                borderColor: Colors.orange,
                borderStrokeWidth: 2,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final l in locations)
              Marker(
                point: LatLng(l.latitude, l.longitude),
                width: 32,
                height: 32,
                child: Icon(Icons.business, color: primary),
              ),
            if (selected != null)
              Marker(
                point: selected!,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.location_pin, color: Colors.orange, size: 40),
              ),
            if (userPosition != null)
              Marker(
                point: userPosition!,
                width: 22,
                height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                  ),
                ),
              ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }
}
