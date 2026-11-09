import 'package:drive_track/app_locale.dart';
import 'package:drive_track/dt_page_route.dart';
import 'package:drive_track/hold_to_end_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() async {
    await LocaleController.instance.setLang(AppLang.zh);
  });

  test('no saved preference stays Chinese', () {
    expect(LocaleController.instance.lang, AppLang.zh);
    expect(const S(true).t('首页', 'Home'), '首页');
    expect(const S(false).t('首页', 'Home'), 'Home');
  });

  test('page transition is a short fade-slide', () {
    expect(kDtPageTransition.inMilliseconds, inInclusiveRange(300, 350));
    final route = DtPageRoute<void>(builder: (_) => const SizedBox());
    expect(route.transitionDuration, kDtPageTransition);
  });

  testWidgets('language switch rebuilds visible copy without restart', (tester) async {
    await LocaleController.instance.setLang(AppLang.zh);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => LocaleScope(
        controller: LocaleController.instance,
        child: child ?? const SizedBox.shrink(),
      ),
      home: Builder(builder: (context) {
        return Column(children: [
          Text(S.of(context).t('首页', 'Home')),
          const LanguageSwitch(),
        ]);
      }),
    ));
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pump();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('首页'), findsNothing);
    expect(LocaleController.instance.lang, AppLang.en);
  });

  testWidgets('hold to end fills only while held and cancels on release', (tester) async {
    var ended = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HoldToEndButton(
          label: '长按结束',
          onComplete: () => ended++,
          holdDuration: const Duration(milliseconds: 700),
        ),
      ),
    ));
    final gesture = await tester.startGesture(tester.getCenter(find.text('长按结束')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(ended, 0);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(ended, 0);

    final held = await tester.startGesture(tester.getCenter(find.text('长按结束')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(ended, 1);
    await held.up();
  });
}
