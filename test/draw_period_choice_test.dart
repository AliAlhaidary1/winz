// Tests for the copy (replay) period-choice dialog.
//
// "The same" must return AUTO so the backend keeps every play in its original
// period instead of duplicating each play into both draws ("Both").

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:winz/src/data/database.dart';
import 'package:winz/src/providers/app_state.dart';
import 'package:winz/src/widgets/draw_period_choice.dart';

class FakeAppState extends AppState {
  FakeAppState() : super(AppDatabase.forTesting(baseUrl: 'http://test'));

  bool middayOpen = true;
  bool eveningOpen = true;

  @override
  Future<bool> isDrawTypeSellableNow(String drawType) async =>
      drawType == 'MIDDAY' ? middayOpen : eveningOpen;
}

Future<Completer<String?>> openDialog(
  WidgetTester tester,
  FakeAppState app,
) async {
  final completer = Completer<String?>();
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                completer.complete(await showDrawPeriodChoice(context));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  return completer;
}

Future<void> tapOpen(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('The same returns AUTO and there is no Both option',
      (tester) async {
    final app = FakeAppState();
    final completer = await openDialog(tester, app);
    await tapOpen(tester);

    expect(find.text('The same'), findsOneWidget);
    expect(find.textContaining('Both'), findsNothing);
    expect(find.text('Morning only'), findsOneWidget);
    expect(find.text('Evening only'), findsOneWidget);

    await tester.tap(find.text('The same'));
    await tester.pumpAndSettle();
    expect(await completer.future, 'AUTO');
  });

  testWidgets('Morning only returns MIDDAY', (tester) async {
    final app = FakeAppState();
    final completer = await openDialog(tester, app);
    await tapOpen(tester);

    await tester.tap(find.text('Morning only'));
    await tester.pumpAndSettle();
    expect(await completer.future, 'MIDDAY');
  });

  testWidgets('Evening only returns EVENING', (tester) async {
    final app = FakeAppState();
    final completer = await openDialog(tester, app);
    await tapOpen(tester);

    await tester.tap(find.text('Evening only'));
    await tester.pumpAndSettle();
    expect(await completer.future, 'EVENING');
  });

  testWidgets('The same stays available when only one draw is open',
      (tester) async {
    final app = FakeAppState()..eveningOpen = false;
    final completer = await openDialog(tester, app);
    await tapOpen(tester);

    expect(find.text('The same'), findsOneWidget);
    await tester.tap(find.text('The same'));
    await tester.pumpAndSettle();
    expect(await completer.future, 'AUTO');
  });
}
