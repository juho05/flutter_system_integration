import 'package:flutter/foundation.dart';
import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rxdart/rxdart.dart';

class MockAutoUpdateRepository extends Mock implements AutoUpdateRepository {}

void main() {
  late MockAutoUpdateRepository repo;

  setUp(() {
    repo = MockAutoUpdateRepository();
    when(() => repo.status).thenReturn(AutoUpdateStatus.initial);
    when(
      () => repo.downloadProgress,
    ).thenAnswer((_) => BehaviorSubject.seeded(0.0).stream);
    when(() => repo.addListener(any())).thenReturn(null);
    when(() => repo.removeListener(any())).thenReturn(null);
  });

  InstallUpdateViewModel buildViewModel() =>
      InstallUpdateViewModel(autoUpdateRepository: repo);

  group('getters', () {
    test('status delegates to repo', () {
      when(() => repo.status).thenReturn(AutoUpdateStatus.downloading);
      final vm = buildViewModel();
      expect(vm.status, AutoUpdateStatus.downloading);
      vm.dispose();
    });

    test('downloadProgress delegates to repo', () {
      final subject = BehaviorSubject.seeded(0.5);
      when(() => repo.downloadProgress).thenAnswer((_) => subject.stream);
      final vm = buildViewModel();
      expect(vm.downloadProgress.value, 0.5);
      vm.dispose();
    });
  });

  group('repo notification forwarding', () {
    test('repo notification forwards to VM listeners', () {
      final vm = buildViewModel();
      var notifications = 0;
      vm.addListener(() => notifications++);

      final captured =
          verify(() => repo.addListener(captureAny())).captured.single
              as VoidCallback;
      captured();

      expect(notifications, 1);
      vm.dispose();
    });

    test('dispose removes listener from repo', () {
      final vm = buildViewModel();
      vm.dispose();
      verify(() => repo.removeListener(any())).called(1);
    });
  });

  group('installUpdate', () {
    test('delegates to repo.update', () async {
      when(() => repo.update()).thenAnswer((_) async {});
      final vm = buildViewModel();
      await vm.installUpdate();
      verify(() => repo.update()).called(1);
      vm.dispose();
    });
  });
}
