import 'dart:async';

import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rxdart/rxdart.dart';

class MockAutoUpdateRepository extends Mock implements AutoUpdateRepository {}

final _messages = [
  UpgradeMessage(
    version: Version.parse("2.0.0"),
    title: "Title",
    message: "Settings were reset.",
  ),
];

void main() {
  setUpAll(() => registerFallbackValue(const PendingUpdate(tag: "")));

  late MockAutoUpdateRepository repo;

  setUp(() {
    repo = MockAutoUpdateRepository();
    when(() => repo.status).thenReturn(AutoUpdateStatus.initial);
    when(
      () => repo.downloadProgress,
    ).thenAnswer((_) => BehaviorSubject.seeded(0.0).stream);
    when(() => repo.addListener(any())).thenReturn(null);
    when(() => repo.removeListener(any())).thenReturn(null);
    when(() => repo.needsInstallPermission()).thenAnswer((_) async => false);
    when(() => repo.markUpgradeMessagesShown(any())).thenAnswer((_) async {});
    when(() => repo.update(any())).thenAnswer((_) async {});
  });

  Future<void> pumpPage(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(home: InstallUpdatePage(autoUpdateRepository: repo)),
  );

  Finder installButton() => find.widgetWithText(FilledButton, "Install");

  testWidgets('no messages -> installs without dialog', (tester) async {
    const pending = PendingUpdate(tag: "v2.0.0");
    when(() => repo.prepareUpdate()).thenAnswer((_) async => pending);
    await pumpPage(tester);

    await tester.tap(installButton());
    await tester.pumpAndSettle();

    expect(find.text("Important Changes"), findsNothing);
    verifyNever(() => repo.markUpgradeMessagesShown(any()));
    verify(() => repo.update(pending)).called(1);
  });

  testWidgets('messages confirmed -> marks shown and installs', (tester) async {
    final pending = PendingUpdate(tag: "v2.0.0", messages: _messages);
    when(() => repo.prepareUpdate()).thenAnswer((_) async => pending);
    await pumpPage(tester);

    await tester.tap(installButton());
    await tester.pumpAndSettle();
    expect(find.text("Version 2.0.0: Title"), findsOneWidget);
    expect(find.text("Settings were reset."), findsOneWidget);
    verifyNever(() => repo.update(any()));

    await tester.tap(find.text("Yes"));
    await tester.pumpAndSettle();

    verify(() => repo.markUpgradeMessagesShown(pending)).called(1);
    verify(() => repo.update(pending)).called(1);
  });

  testWidgets('messages declined -> does not install', (tester) async {
    final pending = PendingUpdate(tag: "v2.0.0", messages: _messages);
    when(() => repo.prepareUpdate()).thenAnswer((_) async => pending);
    await pumpPage(tester);

    await tester.tap(installButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text("No"));
    await tester.pumpAndSettle();

    expect(find.text("Important Changes"), findsNothing);
    verifyNever(() => repo.markUpgradeMessagesShown(any()));
    verifyNever(() => repo.update(any()));
  });

  testWidgets('no newer version -> shows message, does not install', (
    tester,
  ) async {
    when(() => repo.prepareUpdate()).thenAnswer((_) async => null);
    await pumpPage(tester);

    await tester.tap(installButton());
    await tester.pumpAndSettle();

    expect(
      find.text("You are already running the latest version!"),
      findsOneWidget,
    );
    verifyNever(() => repo.update(any()));
  });

  testWidgets('prepare fails -> no up to date message', (tester) async {
    when(() => repo.prepareUpdate()).thenAnswer((_) async {
      when(() => repo.status).thenReturn(AutoUpdateStatus.failure);
      return null;
    });
    await pumpPage(tester);

    await tester.tap(installButton());
    await tester.pumpAndSettle();

    expect(
      find.text("You are already running the latest version!"),
      findsNothing,
    );
    verifyNever(() => repo.update(any()));
  });

  testWidgets('no repository -> shows not supported', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: InstallUpdatePage(autoUpdateRepository: null)),
    );

    expect(
      find.text("Auto updates are not supported on this platform/build."),
      findsOneWidget,
    );
  });

  testWidgets('button is disabled while installing', (tester) async {
    final prepared = Completer<PendingUpdate?>();
    when(() => repo.prepareUpdate()).thenAnswer((_) => prepared.future);
    await pumpPage(tester);

    await tester.tap(installButton());
    await tester.pump();
    expect(tester.widget<FilledButton>(installButton()).onPressed, isNull);
    await tester.tap(installButton(), warnIfMissed: false);
    await tester.pump();
    verify(() => repo.prepareUpdate()).called(1);

    prepared.complete(null);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(installButton()).onPressed, isNotNull);
  });
}
