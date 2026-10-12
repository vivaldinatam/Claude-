import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _date = DateFormat('EEEE, d MMMM yyyy', 'id_ID');
final _shortDate = DateFormat('d MMM yyyy', 'id_ID');
final _time = DateFormat('HH:mm', 'id_ID');
final _month = DateFormat('MMMM yyyy', 'id_ID');
final _dbDate = DateFormat('yyyy-MM-dd');

String fmtDate(DateTime d) => _date.format(d);
String fmtShortDate(DateTime d) => _shortDate.format(d);
String fmtTime(DateTime? d) => d == null ? '--:--' : _time.format(d.toLocal());
String fmtMonth(DateTime d) => _month.format(d);
String toDbDate(DateTime d) => _dbDate.format(d);

/// 85 -> "1 jam 25 menit"
String fmtMinutes(int minutes) {
  if (minutes <= 0) return '0 menit';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m menit';
  if (m == 0) return '$h jam';
  return '$h jam $m menit';
}

/// "08:00:00" -> TimeOfDay(8, 0)
TimeOfDay parseDbTime(String value) {
  final parts = value.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

String toDbTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

String fmtTimeOfDay(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

const dayNames = {1: 'Sen', 2: 'Sel', 3: 'Rab', 4: 'Kam', 5: 'Jum', 6: 'Sab', 7: 'Min'};
