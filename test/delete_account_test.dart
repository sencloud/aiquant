import 'package:fincept_app/screens/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('注销账号：说明删除范围，3 秒后才能确认', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDialog<bool>(
              context: context, builder: (_) => const DeleteAccountDialog()),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(find.textContaining('私人钓点'), findsOneWidget);
    final confirm = find.byKey(const Key('delete-account-confirm'));
    expect(tester.widget<TextButton>(confirm).onPressed, isNull);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.widget<TextButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
