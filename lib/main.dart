import 'package:flutter/material.dart';
import 'src/data/database.dart';
import 'src/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  // trigger creation
  await db.customSelect('SELECT 1').get();
  runApp(YeLotteryApp(db: db));
}
