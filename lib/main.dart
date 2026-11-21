import 'package:flutter/material.dart';

import 'src/data/database.dart';
import 'src/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  runApp(YeLotteryApp(db: db));
}
