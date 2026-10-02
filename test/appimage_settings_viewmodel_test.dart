import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAppImageRepository extends Mock implements AppImageRepository {}

void main() {
  late MockAppImageRepository repo;

  setUp(() {
    repo = MockAppImageRepository();
  });

  AppImageSettingsViewModel buildViewModel() =>
      AppImageSettingsViewModel(appImageRepository: repo);

  group('integrated', () {
    test('null synchronously after construction', () async {
      when(() => repo.isIntegrated()).thenAnswer((_) async => true);
      final vm = buildViewModel();
      expect(vm.integrated, isNull);
      await Future.delayed(Duration.zero);
      vm.dispose();
    });

    test(
      'after settle equals isIntegrated() result (true) and notifies',
      () async {
        when(() => repo.isIntegrated()).thenAnswer((_) async => true);
        var notifications = 0;
        final vm = buildViewModel();
        vm.addListener(() => notifications++);

        await Future.delayed(Duration.zero);

        expect(vm.integrated, isTrue);
        expect(notifications, 1);
        vm.dispose();
      },
    );

    test(
      'after settle equals isIntegrated() result (false) and notifies',
      () async {
        when(() => repo.isIntegrated()).thenAnswer((_) async => false);
        var notifications = 0;
        final vm = buildViewModel();
        vm.addListener(() => notifications++);

        await Future.delayed(Duration.zero);

        expect(vm.integrated, isFalse);
        expect(notifications, 1);
        vm.dispose();
      },
    );
  });

  group('integrate', () {
    test('failure is rethrown', () async {
      when(() => repo.isIntegrated()).thenAnswer((_) async => false);
      when(() => repo.integrate()).thenThrow(Exception('failed'));
      final vm = buildViewModel();
      await Future.delayed(Duration.zero);

      await expectLater(vm.integrate(), throwsException);
      vm.dispose();
    });
  });
}
