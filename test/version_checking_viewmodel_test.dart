import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MockVersionRepository extends Mock implements VersionRepository {}

const _config = SystemIntegrationConfig(
  appName: "Test",
  executableName: "test",
  envPrefix: "TEST",
  githubOwner: "owner",
  githubRepo: "repo",
  desktopId: "org.example.test",
  desktopIconAsset: "assets/icon.png",
  desktopCategories: ["Utility"],
);

class _FakeKeyValue extends Fake implements KeyValueStore {
  @override
  Future<void> store<T>(String key, T value) async {}
  @override
  Future<void> remove(String key) async {}
  @override
  Future<bool?> loadBool(String key) async => null;
  @override
  Future<String?> loadString(String key) async => null;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PackageInfo.setMockInitialValues(
      appName: 'crossonic',
      packageName: 'org.crossonic.app',
      version: '1.2.3',
      buildNumber: '1',
      buildSignature: '',
    );
    registerFallbackValue(const Version(major: 0));
  });

  late VersionCheckingSettings versionCheckingSettings;
  late MockVersionRepository repository;

  setUp(() {
    versionCheckingSettings = VersionCheckingSettings(
      config: _config,
      keyValue: _FakeKeyValue(),
    );
    repository = MockVersionRepository();
  });

  VersionCheckingViewModel buildViewModel() => VersionCheckingViewModel(
    settings: versionCheckingSettings,
    repository: repository,
  );

  group('constructor', () {
    test('reads enabled from settings and notifies', () {
      var notifications = 0;
      final vm = buildViewModel();
      vm.addListener(() => notifications++);

      expect(vm.enabled, versionCheckingSettings.enabled);
      versionCheckingSettings.notifyListeners();
      expect(notifications, greaterThanOrEqualTo(1));
      vm.dispose();
    });
  });

  group('settings notification', () {
    test('settings change re-reads enabled and notifies', () {
      final vm = buildViewModel();
      var notifications = 0;
      vm.addListener(() => notifications++);

      versionCheckingSettings.enabled = !versionCheckingSettings.enabled;

      expect(vm.enabled, versionCheckingSettings.enabled);
      expect(notifications, greaterThanOrEqualTo(1));
      vm.dispose();
    });
  });

  group('updateEnabled', () {
    test('sets enabled on underlying settings', () {
      final vm = buildViewModel();
      final current = versionCheckingSettings.enabled;
      vm.updateEnabled(!current);
      expect(versionCheckingSettings.enabled, !current);
      vm.dispose();
    });
  });

  group('check', () {
    test('toggles checking true then false, both edges notify', () async {
      when(
        () => repository.getLatestVersion(force: any(named: 'force')),
      ).thenAnswer((_) async => null);

      final vm = buildViewModel();
      final seen = <bool>[];
      vm.addListener(() => seen.add(vm.checking));

      await vm.check();

      expect(seen, containsAllInOrder([true, false]));
      expect(vm.checking, isFalse);
      vm.dispose();
    });

    test('getLatestVersion failure is rethrown', () async {
      when(
        () => repository.getLatestVersion(force: any(named: 'force')),
      ).thenThrow(Exception('network'));

      final vm = buildViewModel();

      await expectLater(vm.check(), throwsException);
      vm.dispose();
    });

    test('success returns (current, latest) when latest non-null', () async {
      final latest = const Version(major: 2, minor: 0);
      when(
        () => repository.getLatestVersion(force: any(named: 'force')),
      ).thenAnswer((_) async => latest);

      final vm = buildViewModel();
      final result = await vm.check();

      expect(result.current, const Version(major: 1, minor: 2, patch: 3));
      expect(result.latest, latest);
      vm.dispose();
    });

    test('success returns null latest when not available', () async {
      when(
        () => repository.getLatestVersion(force: any(named: 'force')),
      ).thenAnswer((_) async => null);

      final vm = buildViewModel();
      final result = await vm.check();

      expect(result.latest, isNull);
      vm.dispose();
    });

    test('checking always reset to false in finally even on throw', () async {
      when(
        () => repository.getLatestVersion(force: any(named: 'force')),
      ).thenThrow(Exception('unexpected'));

      final vm = buildViewModel();
      try {
        await vm.check();
      } catch (_) {}

      expect(vm.checking, isFalse);
      vm.dispose();
    });
  });

  group('dispose', () {
    test('removes listener so settings changes no longer notify', () {
      final vm = buildViewModel();
      var notifications = 0;
      vm.addListener(() => notifications++);
      vm.dispose();

      versionCheckingSettings.notifyListeners();

      expect(notifications, 0);
    });
  });
}
