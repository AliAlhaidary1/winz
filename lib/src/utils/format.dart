import 'package:intl/intl.dart';

final currencyFmt = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
final dateFmt = DateFormat('MM/dd/yyyy hh:mm a');
final dateOnlyFmt = DateFormat('MM/dd/yyyy');

int _asMillis(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

/// Coerce a JSON/API value to a [double].
///
/// MySQL/DRY returns DECIMAL money columns as strings such as `"0.50"`, so a
/// bare `as num` cast throws at runtime. Accepts [num], numeric [String] and
/// null (treated as `0.0`).
double asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0.0;
}

/// Coerce a JSON/API value to an [int] (timestamps, counts, sizes).
///
/// Accepts [num], numeric [String] and null (treated as `0`).
int asInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

String fmtDate(dynamic millis) =>
    dateFmt.format(DateTime.fromMillisecondsSinceEpoch(_asMillis(millis)));

/// MySQL returns DECIMAL columns as strings (e.g. "0.50"), so accept both
/// numbers and numeric strings everywhere instead of throwing at runtime.
String fmtMoney(dynamic v) {
  if (v is num) return currencyFmt.format(v);
  final parsed = double.tryParse(v?.toString() ?? '');
  return currencyFmt.format(parsed ?? 0);
}

String fmtMoneyNullable(dynamic v) => fmtMoney(v);
