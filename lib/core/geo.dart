import 'dart:math' as math;

/// Jarak dua koordinat dalam meter (rumus Haversine).
/// Rumus yang sama dipakai di database (`public.distance_m`).
double distanceInMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadius * math.asin(math.sqrt(a));
}

/// Apakah titik berada di dalam radius lokasi.
bool isWithinRadius({
  required double lat,
  required double lng,
  required double centerLat,
  required double centerLng,
  required int radiusMeters,
}) => distanceInMeters(lat, lng, centerLat, centerLng) <= radiusMeters;
