import 'package:intl/intl.dart';

final currencyFmt = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
final dateFmt = DateFormat('MM/dd/yyyy hh:mm a');
final dateOnlyFmt = DateFormat('MM/dd/yyyy');

String fmtDate(int millis) => dateFmt.format(DateTime.fromMillisecondsSinceEpoch(millis));
String fmtMoney(num v) => currencyFmt.format(v);
