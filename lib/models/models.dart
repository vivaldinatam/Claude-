import 'package:flutter/material.dart';

import '../core/attendance_calculator.dart';
import '../core/format.dart';

DateTime? _ts(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
DateTime _date(dynamic v) => DateTime.parse(v as String);
double? _dbl(dynamic v) => v == null ? null : (v as num).toDouble();
int _int(dynamic v) => v == null ? 0 : (v as num).toInt();

class CompanySettings {
  final String companyName;
  final String timezone;
  final MakeupMode makeupMode;
  final int maxGpsAccuracyM;

  const CompanySettings({
    required this.companyName,
    required this.timezone,
    required this.makeupMode,
    required this.maxGpsAccuracyM,
  });

  factory CompanySettings.fromJson(Map<String, dynamic> j) => CompanySettings(
    companyName: j['company_name'] as String,
    timezone: j['timezone'] as String,
    makeupMode: makeupModeFromDb(j['makeup_mode'] as String),
    maxGpsAccuracyM: _int(j['max_gps_accuracy_m']),
  );

  Map<String, dynamic> toJson() => {
    'company_name': companyName,
    'timezone': timezone,
    'makeup_mode': makeupModeToDb(makeupMode),
    'max_gps_accuracy_m': maxGpsAccuracyM,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
}

class WorkLocation {
  final String? id;
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final int radiusM;
  final bool isActive;

  const WorkLocation({
    this.id,
    required this.name,
    this.address,
    required this.latitude,
    required this.longitude,
    this.radiusM = 100,
    this.isActive = true,
  });

  factory WorkLocation.fromJson(Map<String, dynamic> j) => WorkLocation(
    id: j['id'] as String,
    name: j['name'] as String,
    address: j['address'] as String?,
    latitude: _dbl(j['latitude'])!,
    longitude: _dbl(j['longitude'])!,
    radiusM: _int(j['radius_m']),
    isActive: j['is_active'] as bool,
  );

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'radius_m': radiusM,
    'is_active': isActive,
  };
}

class WorkSchedule {
  final String? id;
  final String name;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final int lateToleranceMin;
  final List<int> workDays;
  final int minOvertimeMin;
  final bool makeupEnabled;

  const WorkSchedule({
    this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    this.lateToleranceMin = 0,
    this.workDays = const [1, 2, 3, 4, 5],
    this.minOvertimeMin = 30,
    this.makeupEnabled = true,
  });

  factory WorkSchedule.fromJson(Map<String, dynamic> j) => WorkSchedule(
    id: j['id'] as String,
    name: j['name'] as String,
    startTime: parseDbTime(j['start_time'] as String),
    endTime: parseDbTime(j['end_time'] as String),
    lateToleranceMin: _int(j['late_tolerance_min']),
    workDays: (j['work_days'] as List).map((e) => (e as num).toInt()).toList(),
    minOvertimeMin: _int(j['min_overtime_min']),
    makeupEnabled: j['makeup_enabled'] as bool,
  );

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'start_time': toDbTime(startTime),
    'end_time': toDbTime(endTime),
    'late_tolerance_min': lateToleranceMin,
    'work_days': workDays,
    'min_overtime_min': minOvertimeMin,
    'makeup_enabled': makeupEnabled,
  };

  String get hoursLabel => '${fmtTimeOfDay(startTime)} - ${fmtTimeOfDay(endTime)}';
  String get daysLabel => (workDays.toList()..sort()).map((d) => dayNames[d]).join(', ');
}

class Profile {
  final String id;
  final String fullName;
  final String? email;
  final String? employeeCode;
  final String? phone;
  final String? position;
  final String role;
  final String? scheduleId;
  final int annualLeaveQuota;
  final bool isActive;

  const Profile({
    required this.id,
    required this.fullName,
    this.email,
    this.employeeCode,
    this.phone,
    this.position,
    required this.role,
    this.scheduleId,
    required this.annualLeaveQuota,
    required this.isActive,
  });

  bool get isAdmin => role == 'admin';

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    fullName: j['full_name'] as String,
    email: j['email'] as String?,
    employeeCode: j['employee_code'] as String?,
    phone: j['phone'] as String?,
    position: j['position'] as String?,
    role: j['role'] as String,
    scheduleId: j['schedule_id'] as String?,
    annualLeaveQuota: _int(j['annual_leave_quota']),
    isActive: j['is_active'] as bool,
  );

  Map<String, dynamic> toUpdateJson() => {
    'full_name': fullName,
    'employee_code': (employeeCode?.isEmpty ?? true) ? null : employeeCode,
    'phone': phone,
    'position': position,
    'role': role,
    'schedule_id': scheduleId,
    'annual_leave_quota': annualLeaveQuota,
    'is_active': isActive,
  };

  Profile copyWith({
    String? fullName,
    String? employeeCode,
    String? phone,
    String? position,
    String? role,
    String? scheduleId,
    bool clearSchedule = false,
    int? annualLeaveQuota,
    bool? isActive,
  }) => Profile(
    id: id,
    fullName: fullName ?? this.fullName,
    email: email,
    employeeCode: employeeCode ?? this.employeeCode,
    phone: phone ?? this.phone,
    position: position ?? this.position,
    role: role ?? this.role,
    scheduleId: clearSchedule ? null : (scheduleId ?? this.scheduleId),
    annualLeaveQuota: annualLeaveQuota ?? this.annualLeaveQuota,
    isActive: isActive ?? this.isActive,
  );
}

class Attendance {
  final String id;
  final String employeeId;
  final DateTime workDate;
  final bool isWorkDay;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime checkInAt;
  final double? checkInDistanceM;
  final DateTime? checkOutAt;
  final double? checkOutDistanceM;
  final int lateMinutes;
  final int makeupMinutes;
  final int lateDebtMinutes;
  final int earlyLeaveMinutes;
  final int overtimeMinutes;
  final int workedMinutes;
  final String status;
  final String? employeeName;

  const Attendance({
    required this.id,
    required this.employeeId,
    required this.workDate,
    required this.isWorkDay,
    this.scheduledStart,
    this.scheduledEnd,
    required this.checkInAt,
    this.checkInDistanceM,
    this.checkOutAt,
    this.checkOutDistanceM,
    required this.lateMinutes,
    required this.makeupMinutes,
    required this.lateDebtMinutes,
    required this.earlyLeaveMinutes,
    required this.overtimeMinutes,
    required this.workedMinutes,
    required this.status,
    this.employeeName,
  });

  bool get isOpen => checkOutAt == null;

  factory Attendance.fromJson(Map<String, dynamic> j) => Attendance(
    id: j['id'] as String,
    employeeId: j['employee_id'] as String,
    workDate: _date(j['work_date']),
    isWorkDay: j['is_work_day'] as bool,
    scheduledStart: _ts(j['scheduled_start']),
    scheduledEnd: _ts(j['scheduled_end']),
    checkInAt: _ts(j['check_in_at'])!,
    checkInDistanceM: _dbl(j['check_in_distance_m']),
    checkOutAt: _ts(j['check_out_at']),
    checkOutDistanceM: _dbl(j['check_out_distance_m']),
    lateMinutes: _int(j['late_minutes']),
    makeupMinutes: _int(j['makeup_minutes']),
    lateDebtMinutes: _int(j['late_debt_minutes']),
    earlyLeaveMinutes: _int(j['early_leave_minutes']),
    overtimeMinutes: _int(j['overtime_minutes']),
    workedMinutes: _int(j['worked_minutes']),
    status: j['status'] as String,
    employeeName: (j['employee'] as Map<String, dynamic>?)?['full_name'] as String?,
  );

  String get statusLabel => switch (status) {
    'terlambat' => 'Terlambat',
    'libur_masuk' => 'Masuk hari libur',
    _ => 'Tepat waktu',
  };
}

const leaveTypeLabels = {'izin': 'Izin', 'sakit': 'Sakit', 'cuti': 'Cuti'};
const requestStatusLabels = {'pending': 'Menunggu', 'approved': 'Disetujui', 'rejected': 'Ditolak'};

class LeaveRequest {
  final String id;
  final String employeeId;
  final String type;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String? attachmentUrl;
  final String status;
  final String? reviewNote;
  final DateTime createdAt;
  final String? employeeName;

  const LeaveRequest({
    required this.id,
    required this.employeeId,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.reason,
    this.attachmentUrl,
    required this.status,
    this.reviewNote,
    required this.createdAt,
    this.employeeName,
  });

  int get calendarDays => endDate.difference(startDate).inDays + 1;

  factory LeaveRequest.fromJson(Map<String, dynamic> j) => LeaveRequest(
    id: j['id'] as String,
    employeeId: j['employee_id'] as String,
    type: j['type'] as String,
    startDate: _date(j['start_date']),
    endDate: _date(j['end_date']),
    reason: j['reason'] as String,
    attachmentUrl: j['attachment_url'] as String?,
    status: j['status'] as String,
    reviewNote: j['review_note'] as String?,
    createdAt: _ts(j['created_at'])!,
    employeeName: (j['employee'] as Map<String, dynamic>?)?['full_name'] as String?,
  );
}

class OvertimeRequest {
  final String id;
  final String employeeId;
  final DateTime workDate;
  final int requestedMinutes;
  final int? approvedMinutes;
  final String reason;
  final String status;
  final String? reviewNote;
  final DateTime createdAt;
  final String? employeeName;

  const OvertimeRequest({
    required this.id,
    required this.employeeId,
    required this.workDate,
    required this.requestedMinutes,
    this.approvedMinutes,
    required this.reason,
    required this.status,
    this.reviewNote,
    required this.createdAt,
    this.employeeName,
  });

  factory OvertimeRequest.fromJson(Map<String, dynamic> j) => OvertimeRequest(
    id: j['id'] as String,
    employeeId: j['employee_id'] as String,
    workDate: _date(j['work_date']),
    requestedMinutes: _int(j['requested_minutes']),
    approvedMinutes: j['approved_minutes'] == null ? null : _int(j['approved_minutes']),
    reason: j['reason'] as String,
    status: j['status'] as String,
    reviewNote: j['review_note'] as String?,
    createdAt: _ts(j['created_at'])!,
    employeeName: (j['employee'] as Map<String, dynamic>?)?['full_name'] as String?,
  );
}

class MonthlyRecap {
  final String employeeId;
  final String fullName;
  final String? employeeCode;
  final int workDays;
  final int presentDays;
  final int lateCount;
  final int lateMinutes;
  final int makeupMinutes;
  final int lateDebtMinutes;
  final int earlyLeaveMinutes;
  final int overtimeMinutes;
  final int overtimeApprovedMinutes;
  final int izinDays;
  final int sakitDays;
  final int cutiDays;
  final int absentDays;
  final int leaveQuota;
  final int leaveUsedYear;
  final int leaveRemaining;

  const MonthlyRecap({
    required this.employeeId,
    required this.fullName,
    this.employeeCode,
    required this.workDays,
    required this.presentDays,
    required this.lateCount,
    required this.lateMinutes,
    required this.makeupMinutes,
    required this.lateDebtMinutes,
    required this.earlyLeaveMinutes,
    required this.overtimeMinutes,
    required this.overtimeApprovedMinutes,
    required this.izinDays,
    required this.sakitDays,
    required this.cutiDays,
    required this.absentDays,
    required this.leaveQuota,
    required this.leaveUsedYear,
    required this.leaveRemaining,
  });

  factory MonthlyRecap.fromJson(Map<String, dynamic> j) => MonthlyRecap(
    employeeId: j['employee_id'] as String,
    fullName: j['full_name'] as String,
    employeeCode: j['employee_code'] as String?,
    workDays: _int(j['work_days']),
    presentDays: _int(j['present_days']),
    lateCount: _int(j['late_count']),
    lateMinutes: _int(j['late_minutes']),
    makeupMinutes: _int(j['makeup_minutes']),
    lateDebtMinutes: _int(j['late_debt_minutes']),
    earlyLeaveMinutes: _int(j['early_leave_minutes']),
    overtimeMinutes: _int(j['overtime_minutes']),
    overtimeApprovedMinutes: _int(j['overtime_approved_minutes']),
    izinDays: _int(j['izin_days']),
    sakitDays: _int(j['sakit_days']),
    cutiDays: _int(j['cuti_days']),
    absentDays: _int(j['absent_days']),
    leaveQuota: _int(j['leave_quota']),
    leaveUsedYear: _int(j['leave_used_year']),
    leaveRemaining: _int(j['leave_remaining']),
  );
}
