import 'package:geolocator/geolocator.dart';

class LocationException implements Exception {
  final String message;
  final bool openSettings;
  const LocationException(this.message, {this.openSettings = false});
  @override
  String toString() => message;
}

class LocationService {
  LocationService._();

  /// Ambil posisi GPS terkini dengan izin & pengecekan layanan lokasi.
  static Future<Position> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
        'GPS tidak aktif. Aktifkan layanan lokasi di perangkat Anda.',
        openSettings: true,
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('Izin lokasi ditolak. Absensi membutuhkan izin lokasi.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Izin lokasi ditolak permanen. Buka pengaturan aplikasi untuk mengizinkan.',
        openSettings: true,
      );
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 25),
      ),
    );
  }

  static Future<void> openSettings() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
