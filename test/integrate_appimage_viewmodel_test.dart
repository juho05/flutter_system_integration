import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAppImageRepository extends Mock implements AppImageRepository {}

void main() {
  late MockAppImageRepository repo;

  setUp(() {
    repo = MockAppImageRepository();
  });

  IntegrateAppImageViewModel buildViewModel() =>
      IntegrateAppImageViewModel(appImageRepository: repo);

  group('check', () {
    test(
      'shouldIntegrate true sets askToIntegrate true and notifies',
      () async {
        when(() => repo.shouldIntegrate()).thenAnswer((_) async => true);
        var notifications = 0;
        final vm = buildViewModel();
        vm.addListener(() => notifications++);

        await vm.check();

        expect(vm.askToIntegrate, isTrue);
        expect(notifications, 1);
        vm.dispose();
      },
    );

    test(
      'shouldIntegrate false leaves askToIntegrate false and no notify',
      () async {
        when(() => repo.shouldIntegrate()).thenAnswer((_) async => false);
        var notifications = 0;
        final vm = buildViewModel();
        vm.addListener(() => notifications++);

        await vm.check();

        expect(vm.askToIntegrate, isFalse);
        expect(notifications, 0);
        vm.dispose();
      },
    );
  });

  group('shownDialog', () {
    test('sets askToIntegrate to false', () async {
      when(() => repo.shouldIntegrate()).thenAnswer((_) async => true);
      final vm = buildViewModel();
      await vm.check();
      expect(vm.askToIntegrate, isTrue);

      vm.shownDialog();

      expect(vm.askToIntegrate, isFalse);
      vm.dispose();
    });

    // shownDialog() is called from inside the Consumer builder during build, so
    // it must not notify or it would trigger a rebuild loop.
    test('does not notify listeners', () async {
      when(() => repo.shouldIntegrate()).thenAnswer((_) async => true);
      final vm = buildViewModel();
      await vm.check();
      var notifications = 0;
      vm.addListener(() => notifications++);

      vm.shownDialog();

      expect(notifications, 0);
      vm.dispose();
    });
  });

  group('disable', () {
    test('sets askToIntegrate false and calls disableIntegration', () async {
      when(() => repo.shouldIntegrate()).thenAnswer((_) async => true);
      when(() => repo.disableIntegration()).thenAnswer((_) async {});
      final vm = buildViewModel();
      await vm.check();

      await vm.disable();

      expect(vm.askToIntegrate, isFalse);
      verify(() => repo.disableIntegration()).called(1);
      vm.dispose();
    });
  });

  group('integrate', () {
    test('success sets askToIntegrate false', () async {
      when(() => repo.shouldIntegrate()).thenAnswer((_) async => true);
      when(() => repo.integrate()).thenAnswer((_) async {});
      final vm = buildViewModel();
      await vm.check();

      await vm.integrate();

      expect(vm.askToIntegrate, isFalse);
      verify(() => repo.integrate()).called(1);
      vm.dispose();
    });

    test('failure sets askToIntegrate false and rethrows', () async {
      when(() => repo.shouldIntegrate()).thenAnswer((_) async => true);
      when(() => repo.integrate()).thenThrow(Exception('failed'));
      final vm = buildViewModel();
      await vm.check();

      await expectLater(vm.integrate(), throwsException);

      expect(vm.askToIntegrate, isFalse);
      vm.dispose();
    });
  });
}
