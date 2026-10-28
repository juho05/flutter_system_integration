import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockUpgradeMessagesRepository extends Mock
    implements UpgradeMessagesRepository {}

const _message = UpgradeMessage(version: Version(major: 2), message: "Text");

void main() {
  setUpAll(() => registerFallbackValue(<UpgradeMessage>[]));

  late MockUpgradeMessagesRepository repo;

  setUp(() {
    repo = MockUpgradeMessagesRepository();
  });

  test('messages -> notifies', () async {
    when(() => repo.getStartupMessages()).thenAnswer((_) async => [_message]);
    final vm = UpgradeMessagesViewModel(repository: repo);
    var notifications = 0;
    vm.addListener(() => notifications++);

    await vm.check();

    expect(vm.messages, [_message]);
    expect(notifications, 1);
    vm.dispose();
  });

  test('no messages -> no notify', () async {
    when(() => repo.getStartupMessages()).thenAnswer((_) async => []);
    final vm = UpgradeMessagesViewModel(repository: repo);
    var notifications = 0;
    vm.addListener(() => notifications++);

    await vm.check();

    expect(vm.messages, isEmpty);
    expect(notifications, 0);
    vm.dispose();
  });

  test('exception -> no messages', () async {
    when(() => repo.getStartupMessages()).thenThrow(Exception("broken"));
    final vm = UpgradeMessagesViewModel(repository: repo);

    await vm.check();

    expect(vm.messages, isEmpty);
    vm.dispose();
  });

  test('error -> no messages', () async {
    when(
      () => repo.getStartupMessages(),
    ).thenAnswer((_) async => throw TypeError());
    final vm = UpgradeMessagesViewModel(repository: repo);

    await vm.check();

    expect(vm.messages, isEmpty);
    vm.dispose();
  });

  test('second check() is a no-op', () async {
    when(() => repo.getStartupMessages()).thenAnswer((_) async => []);
    final vm = UpgradeMessagesViewModel(repository: repo);

    await vm.check();
    await vm.check();

    verify(() => repo.getStartupMessages()).called(1);
    vm.dispose();
  });

  test('acknowledge clears messages without writing', () async {
    when(() => repo.getStartupMessages()).thenAnswer((_) async => [_message]);
    final vm = UpgradeMessagesViewModel(repository: repo);
    await vm.check();
    var notifications = 0;
    vm.addListener(() => notifications++);

    vm.acknowledge();

    expect(vm.messages, isEmpty);
    expect(notifications, 1);
    verifyNever(() => repo.markShown(any()));
    vm.dispose();
  });

  test('acknowledge without messages does not notify', () {
    final vm = UpgradeMessagesViewModel(repository: repo);
    var notifications = 0;
    vm.addListener(() => notifications++);

    vm.acknowledge();

    expect(notifications, 0);
    vm.dispose();
  });
}
