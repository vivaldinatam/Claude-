/// Logika perhitungan absensi. Aturan di sini identik dengan fungsi
/// `check_in`, `check_out`, dan `monthly_recap` di database (database yang
/// menjadi sumber kebenaran; kelas ini dipakai untuk pratinjau & unit test).
library;

enum MakeupMode { sameDay, monthly }

MakeupMode makeupModeFromDb(String value) =>
    value == 'monthly' ? MakeupMode.monthly : MakeupMode.sameDay;

String makeupModeToDb(MakeupMode mode) => mode == MakeupMode.monthly ? 'monthly' : 'same_day';

class CheckoutResult {
  /// Menit setelah jam pulang terjadwal.
  final int extraMinutes;

  /// Menit pulang lebih awal dari jadwal.
  final int earlyLeaveMinutes;

  /// Menit keterlambatan yang tertutup oleh kelebihan jam pulang.
  final int makeupMinutes;

  /// Sisa keterlambatan yang belum diganti.
  final int lateDebtMinutes;

  /// Kelebihan jam setelah dipotong ganti jam (calon lembur).
  final int overtimeMinutes;

  /// Total menit dari absen masuk sampai absen pulang.
  final int workedMinutes;

  const CheckoutResult({
    required this.extraMinutes,
    required this.earlyLeaveMinutes,
    required this.makeupMinutes,
    required this.lateDebtMinutes,
    required this.overtimeMinutes,
    required this.workedMinutes,
  });
}

class MonthlyMakeup {
  final int makeupMinutes;
  final int lateDebtMinutes;
  const MonthlyMakeup(this.makeupMinutes, this.lateDebtMinutes);
}

class AttendanceCalculator {
  AttendanceCalculator._();

  /// Menit terlambat. Datang dalam batas toleransi = tidak terlambat (0).
  /// Lewat toleransi = dihitung penuh sejak jam masuk.
  static int lateMinutes({
    required DateTime checkIn,
    required DateTime scheduledStart,
    int toleranceMinutes = 0,
  }) {
    final late = checkIn.difference(scheduledStart).inSeconds ~/ 60;
    if (late <= 0 || late <= toleranceMinutes) return 0;
    return late;
  }

  /// Perhitungan saat absen pulang.
  ///
  /// Ganti jam: kelebihan jam setelah jam pulang dipakai terlebih dahulu
  /// untuk menutup keterlambatan; sisanya baru dihitung sebagai lembur.
  /// Pada hari libur seluruh jam kerja dihitung sebagai lembur.
  static CheckoutResult checkout({
    required DateTime checkIn,
    required DateTime checkOut,
    DateTime? scheduledEnd,
    int lateMinutes = 0,
    bool makeupEnabled = true,
    bool isWorkDay = true,
  }) {
    final worked = _floorMinutes(checkOut.difference(checkIn));
    if (!isWorkDay || scheduledEnd == null) {
      return CheckoutResult(
        extraMinutes: 0,
        earlyLeaveMinutes: 0,
        makeupMinutes: 0,
        lateDebtMinutes: lateMinutes,
        overtimeMinutes: worked,
        workedMinutes: worked,
      );
    }
    final extra = _floorMinutes(checkOut.difference(scheduledEnd));
    final earlySeconds = scheduledEnd.difference(checkOut).inSeconds;
    final early = earlySeconds > 0 ? (earlySeconds + 59) ~/ 60 : 0;
    final makeup = makeupEnabled ? (lateMinutes < extra ? lateMinutes : extra) : 0;
    return CheckoutResult(
      extraMinutes: extra,
      earlyLeaveMinutes: early,
      makeupMinutes: makeup,
      lateDebtMinutes: lateMinutes - makeup,
      overtimeMinutes: extra - makeup,
      workedMinutes: worked,
    );
  }

  /// Lembur hanya diakui jika kelebihan jam mencapai batas minimal.
  static bool isOvertimeEligible(int overtimeMinutes, int minOvertimeMinutes) =>
      overtimeMinutes > 0 && overtimeMinutes >= minOvertimeMinutes;

  /// Ganti jam level bulanan.
  ///
  /// Mode [MakeupMode.monthly]: kelebihan jam yang TIDAK disetujui sebagai
  /// lembur ikut menutup sisa keterlambatan dari hari-hari lain di bulan yang sama.
  static MonthlyMakeup monthly({
    required MakeupMode mode,
    required int sameDayMakeupMinutes,
    required int lateDebtMinutes,
    required int overtimeMinutes,
    required int approvedOvertimeMinutes,
  }) {
    if (mode == MakeupMode.sameDay) {
      return MonthlyMakeup(sameDayMakeupMinutes, lateDebtMinutes);
    }
    final freeExtra = overtimeMinutes - approvedOvertimeMinutes;
    final pool = freeExtra > 0 ? freeExtra : 0;
    final carry = lateDebtMinutes < pool ? lateDebtMinutes : pool;
    return MonthlyMakeup(sameDayMakeupMinutes + carry, lateDebtMinutes - carry);
  }

  static int _floorMinutes(Duration d) {
    final s = d.inSeconds;
    return s > 0 ? s ~/ 60 : 0;
  }
}
