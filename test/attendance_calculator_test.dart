import 'package:absensi_karyawan/core/attendance_calculator.dart';
import 'package:absensi_karyawan/core/geo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 10, 12, 8, 0);
  final end = DateTime(2026, 10, 12, 17, 0);

  group('lateMinutes', () {
    test('tepat waktu tidak terlambat', () {
      expect(AttendanceCalculator.lateMinutes(checkIn: start, scheduledStart: start), 0);
    });

    test('datang lebih awal tidak terlambat', () {
      expect(
        AttendanceCalculator.lateMinutes(
          checkIn: start.subtract(const Duration(minutes: 15)),
          scheduledStart: start,
        ),
        0,
      );
    });

    test('dalam toleransi tidak dihitung terlambat', () {
      expect(
        AttendanceCalculator.lateMinutes(
          checkIn: start.add(const Duration(minutes: 10)),
          scheduledStart: start,
          toleranceMinutes: 10,
        ),
        0,
      );
    });

    test('lewat toleransi dihitung penuh sejak jam masuk', () {
      expect(
        AttendanceCalculator.lateMinutes(
          checkIn: start.add(const Duration(minutes: 25, seconds: 40)),
          scheduledStart: start,
          toleranceMinutes: 10,
        ),
        25,
      );
    });
  });

  group('checkout & ganti jam', () {
    test('terlambat 30 menit, pulang 45 menit lebih lama -> ganti 30, lebih 15', () {
      final r = AttendanceCalculator.checkout(
        checkIn: start.add(const Duration(minutes: 30)),
        checkOut: end.add(const Duration(minutes: 45)),
        scheduledEnd: end,
        lateMinutes: 30,
      );
      expect(r.makeupMinutes, 30);
      expect(r.lateDebtMinutes, 0);
      expect(r.overtimeMinutes, 15);
      expect(r.earlyLeaveMinutes, 0);
      expect(r.workedMinutes, 9 * 60 + 15);
    });

    test('terlambat 60 menit, pulang 20 menit lebih lama -> sisa 40', () {
      final r = AttendanceCalculator.checkout(
        checkIn: start.add(const Duration(minutes: 60)),
        checkOut: end.add(const Duration(minutes: 20)),
        scheduledEnd: end,
        lateMinutes: 60,
      );
      expect(r.makeupMinutes, 20);
      expect(r.lateDebtMinutes, 40);
      expect(r.overtimeMinutes, 0);
    });

    test('ganti jam nonaktif -> seluruh kelebihan jadi lembur', () {
      final r = AttendanceCalculator.checkout(
        checkIn: start.add(const Duration(minutes: 30)),
        checkOut: end.add(const Duration(minutes: 90)),
        scheduledEnd: end,
        lateMinutes: 30,
        makeupEnabled: false,
      );
      expect(r.makeupMinutes, 0);
      expect(r.lateDebtMinutes, 30);
      expect(r.overtimeMinutes, 90);
    });

    test('pulang cepat dihitung (dibulatkan ke atas)', () {
      final r = AttendanceCalculator.checkout(
        checkIn: start,
        checkOut: end.subtract(const Duration(minutes: 14, seconds: 30)),
        scheduledEnd: end,
      );
      expect(r.earlyLeaveMinutes, 15);
      expect(r.overtimeMinutes, 0);
    });

    test('hari libur -> semua jam kerja jadi lembur', () {
      final r = AttendanceCalculator.checkout(
        checkIn: DateTime(2026, 10, 11, 9),
        checkOut: DateTime(2026, 10, 11, 13, 30),
        isWorkDay: false,
      );
      expect(r.overtimeMinutes, 270);
      expect(r.workedMinutes, 270);
    });

    test('minimal lembur', () {
      expect(AttendanceCalculator.isOvertimeEligible(29, 30), isFalse);
      expect(AttendanceCalculator.isOvertimeEligible(30, 30), isTrue);
      expect(AttendanceCalculator.isOvertimeEligible(0, 0), isFalse);
    });
  });

  group('ganti jam bulanan', () {
    test('mode hari yang sama tidak mengubah sisa', () {
      final m = AttendanceCalculator.monthly(
        mode: MakeupMode.sameDay,
        sameDayMakeupMinutes: 20,
        lateDebtMinutes: 40,
        overtimeMinutes: 100,
        approvedOvertimeMinutes: 0,
      );
      expect(m.makeupMinutes, 20);
      expect(m.lateDebtMinutes, 40);
    });

    test('mode bulanan memakai kelebihan jam yang tidak diajukan lembur', () {
      final m = AttendanceCalculator.monthly(
        mode: MakeupMode.monthly,
        sameDayMakeupMinutes: 20,
        lateDebtMinutes: 40,
        overtimeMinutes: 100,
        approvedOvertimeMinutes: 75,
      );
      // kelebihan bebas = 25 -> sisa 15
      expect(m.makeupMinutes, 45);
      expect(m.lateDebtMinutes, 15);
    });
  });

  group('geo', () {
    test('jarak Monas - Bundaran HI sekitar 2,2 km', () {
      final d = distanceInMeters(-6.175392, 106.827153, -6.194900, 106.823030);
      expect(d, closeTo(2217, 30));
    });

    test('isWithinRadius', () {
      expect(
        isWithinRadius(
          lat: -6.175392,
          lng: 106.827153,
          centerLat: -6.175392,
          centerLng: 106.828,
          radiusMeters: 100,
        ),
        isTrue,
      );
      expect(
        isWithinRadius(
          lat: -6.175392,
          lng: 106.827153,
          centerLat: -6.175392,
          centerLng: 106.830,
          radiusMeters: 100,
        ),
        isFalse,
      );
    });
  });
}
