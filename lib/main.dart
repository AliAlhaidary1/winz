import 'package:flutter/material.dart';

import 'src/data/database.dart';
import 'src/app.dart';
import 'src/services/session_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SessionStore.load();
  final db = AppDatabase();
  runApp(YeLotteryApp(db: db));
}
