/// Helpers for the configured draw timezone.
///
/// The app stores a timezone name in `app_config.draw_timezone` (default
/// `America/New_York`) but Dart's core library has no time-zone database.
/// Instead of silently treating every wall-clock time as device-local time,
/// we convert New York wall times to real UTC epochs using the US DST rules
/// (second Sunday of March -> first Sunday of November).  Unknown zones keep
/// the legacy device-local behaviour so nothing breaks for custom values.
class MarketTimezone {
  static const defaultTimezone = 'America/New_York';

  static bool isNewYork(String? tz) {
    final t = (tz ?? '').trim().toLowerCase();
    return t.isEmpty ||
        t == 'america/new_york' ||
        t == 'us/eastern' ||
        t == 'est' ||
        t == 'edt';
  }

  static DateTime _nthSunday(int year, int month, int nth) {
    var d = DateTime(year, month, 1);
    final weekday = d.weekday; // Mon=1 .. Sun=7
    final daysUntilSunday = (7 - weekday) % 7;
    d = d.add(Duration(days: daysUntilSunday + (nth - 1) * 7));
    return DateTime(year, month, d.day);
  }

  /// UTC offset in hours for a New York wall-clock date (-5 EST, -4 EDT).
  static int newYorkOffsetHours(DateTime wallDate) {
    final dstStart = _nthSunday(wallDate.year, 3, 2);
    final dstEnd = _nthSunday(wallDate.year, 11, 1);
    final d = DateTime(wallDate.year, wallDate.month, wallDate.day);
    if (!d.isBefore(dstStart) && d.isBefore(dstEnd)) return -4;
    return -5;
  }

  /// Convert a wall-clock date/time in [tz] to an absolute epoch.
  static int epochForWallTime(DateTime date, int hour, int minute, String? tz) {
    if (!isNewYork(tz)) {
      return DateTime(
        date.year,
        date.month,
        date.day,
        hour,
        minute,
      ).millisecondsSinceEpoch;
    }
    final offset = newYorkOffsetHours(date);
    // Wall time = UTC + offset, therefore UTC = wall time - offset.
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
      hour - offset,
      minute,
    ).millisecondsSinceEpoch;
  }

  /// Convert an epoch back into wall-clock fields for [tz].
  /// The returned DateTime's hour/minute are the wall-clock values in the
  /// configured timezone (its UTC instant is meaningless for display).
  static DateTime wallTimeFromEpoch(int ms, String? tz) {
    final utc = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    if (!isNewYork(tz)) {
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    final offset = newYorkOffsetHours(utc);
    return DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
    ).add(Duration(hours: offset));
  }

  static String format12FromEpoch(int ms, String? tz) {
    final wall = wallTimeFromEpoch(ms, tz);
    final h = wall.hour;
    final m = wall.minute.toString().padLeft(2, '0');
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '${h12.toString().padLeft(2, '0')}:$m ${h < 12 ? 'AM' : 'PM'}';
  }
}
