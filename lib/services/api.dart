import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/format.dart';
import '../models/models.dart';

/// Semua akses data ke Supabase.
class Api {
  Api._();
  static final instance = Api._();

  SupabaseClient get _db => Supabase.instance.client;
  String get uid => _db.auth.currentUser!.id;

  // ---------------- Auth ----------------
  Future<void> signIn(String email, String password) =>
      _db.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> signUp(String email, String password, String fullName) =>
      _db.auth.signUp(email: email, password: password, data: {'full_name': fullName});

  Future<void> signOut() => _db.auth.signOut();

  // ---------------- Profil & karyawan ----------------
  Future<Profile?> myProfile() async {
    final row = await _db.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  Future<List<Profile>> employees() async {
    final rows = await _db.from('profiles').select().order('full_name');
    return rows.map(Profile.fromJson).toList();
  }

  Future<void> updateEmployee(Profile p) =>
      _db.from('profiles').update(p.toUpdateJson()).eq('id', p.id);

  Future<Set<String>> employeeLocationIds(String employeeId) async {
    final rows = await _db
        .from('employee_locations')
        .select('location_id')
        .eq('employee_id', employeeId);
    return rows.map((r) => r['location_id'] as String).toSet();
  }

  Future<void> setEmployeeLocations(String employeeId, Set<String> locationIds) async {
    await _db.from('employee_locations').delete().eq('employee_id', employeeId);
    if (locationIds.isEmpty) return;
    await _db.from('employee_locations').insert([
      for (final id in locationIds) {'employee_id': employeeId, 'location_id': id},
    ]);
  }

  // ---------------- Pengaturan ----------------
  Future<CompanySettings> settings() async {
    final row = await _db.from('company_settings').select().eq('id', 1).single();
    return CompanySettings.fromJson(row);
  }

  Future<void> updateSettings(CompanySettings s) =>
      _db.from('company_settings').update(s.toJson()).eq('id', 1);

  // ---------------- Lokasi ----------------
  Future<List<WorkLocation>> locations({bool activeOnly = false}) async {
    var query = _db.from('work_locations').select();
    if (activeOnly) query = query.eq('is_active', true);
    final rows = await query.order('name');
    return rows.map(WorkLocation.fromJson).toList();
  }

  /// Lokasi yang berlaku untuk karyawan login (penugasan, atau semua lokasi aktif).
  Future<List<WorkLocation>> myLocations() async {
    final assigned = await employeeLocationIds(uid);
    final all = await locations(activeOnly: true);
    if (assigned.isEmpty) return all;
    return all.where((l) => assigned.contains(l.id)).toList();
  }

  Future<void> saveLocation(WorkLocation l) => _db.from('work_locations').upsert(l.toJson());

  Future<void> deleteLocation(String id) => _db.from('work_locations').delete().eq('id', id);

  // ---------------- Jadwal ----------------
  Future<List<WorkSchedule>> schedules() async {
    final rows = await _db.from('work_schedules').select().order('name');
    return rows.map(WorkSchedule.fromJson).toList();
  }

  Future<WorkSchedule?> schedule(String id) async {
    final row = await _db.from('work_schedules').select().eq('id', id).maybeSingle();
    return row == null ? null : WorkSchedule.fromJson(row);
  }

  Future<void> saveSchedule(WorkSchedule s) => _db.from('work_schedules').upsert(s.toJson());

  Future<void> deleteSchedule(String id) => _db.from('work_schedules').delete().eq('id', id);

  // ---------------- Absensi ----------------
  Future<Attendance?> latestAttendance() async {
    final row = await _db
        .from('attendances')
        .select()
        .eq('employee_id', uid)
        .order('check_in_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : Attendance.fromJson(row);
  }

  Future<List<Attendance>> attendances(DateTime month, {String? employeeId}) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0);
    var query = _db
        .from('attendances')
        .select('*, employee:profiles!attendances_employee_id_fkey(full_name)')
        .gte('work_date', toDbDate(start))
        .lte('work_date', toDbDate(end));
    if (employeeId != null) query = query.eq('employee_id', employeeId);
    final rows = await query.order('work_date', ascending: false);
    return rows.map(Attendance.fromJson).toList();
  }

  Map<String, dynamic> _positionParams(Position p, String? note) => {
    'p_lat': p.latitude,
    'p_lng': p.longitude,
    'p_accuracy': p.accuracy,
    'p_is_mocked': p.isMocked,
    'p_note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
  };

  Future<Attendance> checkIn(Position p, {String? note}) async {
    final row = await _db.rpc('check_in', params: _positionParams(p, note));
    return Attendance.fromJson(row as Map<String, dynamic>);
  }

  Future<Attendance> checkOut(Position p, {String? note}) async {
    final row = await _db.rpc('check_out', params: _positionParams(p, note));
    return Attendance.fromJson(row as Map<String, dynamic>);
  }

  // ---------------- Izin / sakit / cuti ----------------
  static const _leaveSelect = '*, employee:profiles!leave_requests_employee_id_fkey(full_name)';

  Future<List<LeaveRequest>> myLeaves() async {
    final rows = await _db
        .from('leave_requests')
        .select(_leaveSelect)
        .eq('employee_id', uid)
        .order('start_date', ascending: false);
    return rows.map(LeaveRequest.fromJson).toList();
  }

  Future<List<LeaveRequest>> leavesByStatus(String status) async {
    final rows = await _db
        .from('leave_requests')
        .select(_leaveSelect)
        .eq('status', status)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(LeaveRequest.fromJson).toList();
  }

  Future<void> submitLeave({
    required String type,
    required DateTime start,
    required DateTime end,
    required String reason,
    String? attachmentUrl,
  }) => _db.from('leave_requests').insert({
    'employee_id': uid,
    'type': type,
    'start_date': toDbDate(start),
    'end_date': toDbDate(end),
    'reason': reason,
    'attachment_url': (attachmentUrl?.trim().isEmpty ?? true) ? null : attachmentUrl!.trim(),
  });

  Future<void> cancelLeave(String id) => _db.from('leave_requests').delete().eq('id', id);

  Future<void> reviewLeave(String id, bool approve, {String? note}) =>
      _db.rpc('review_leave', params: {'p_id': id, 'p_approve': approve, 'p_note': note});

  // ---------------- Lembur ----------------
  static const _otSelect = '*, employee:profiles!overtime_requests_employee_id_fkey(full_name)';

  Future<List<OvertimeRequest>> myOvertimes() async {
    final rows = await _db
        .from('overtime_requests')
        .select(_otSelect)
        .eq('employee_id', uid)
        .order('work_date', ascending: false);
    return rows.map(OvertimeRequest.fromJson).toList();
  }

  Future<List<OvertimeRequest>> overtimesByStatus(String status) async {
    final rows = await _db
        .from('overtime_requests')
        .select(_otSelect)
        .eq('status', status)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(OvertimeRequest.fromJson).toList();
  }

  Future<void> submitOvertime({
    required DateTime date,
    required int minutes,
    required String reason,
  }) => _db.from('overtime_requests').insert({
    'employee_id': uid,
    'work_date': toDbDate(date),
    'requested_minutes': minutes,
    'reason': reason,
  });

  Future<void> cancelOvertime(String id) => _db.from('overtime_requests').delete().eq('id', id);

  Future<void> reviewOvertime(String id, bool approve, {int? minutes, String? note}) => _db.rpc(
    'review_overtime',
    params: {'p_id': id, 'p_approve': approve, 'p_approved_minutes': minutes, 'p_note': note},
  );

  // ---------------- Rekap ----------------
  Future<List<MonthlyRecap>> monthlyRecap(DateTime month, {String? employeeId}) async {
    final rows = await _db.rpc(
      'monthly_recap',
      params: {
        'p_month': toDbDate(DateTime(month.year, month.month, 1)),
        'p_employee_id': employeeId,
      },
    ) as List<dynamic>;
    return rows.map((r) => MonthlyRecap.fromJson(r as Map<String, dynamic>)).toList();
  }
}

/// Ambil pesan error yang ramah dari exception Supabase / lainnya.
String errorMessage(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) {
    if (e.message.contains('Invalid login credentials')) return 'Email atau kata sandi salah.';
    if (e.message.contains('Email not confirmed')) {
      return 'Email belum dikonfirmasi. Cek kotak masuk email Anda.';
    }
    return e.message;
  }
  return e.toString().replaceFirst('Exception: ', '');
}
