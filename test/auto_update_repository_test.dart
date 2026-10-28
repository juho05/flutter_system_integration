import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_system_integration/src/auto_update/updaters/updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MockVersionRepository extends Mock implements VersionRepository {}

class MockUpgradeMessagesRepository extends Mock
    implements UpgradeMessagesRepository {}

class MockUpdater extends Mock implements Updater {}

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

const _pathProviderChannel = MethodChannel("plugins.flutter.io/path_provider");

final _message = UpgradeMessage(version: Version.parse("2.0.0"), message: "");

// Running version as set by PackageInfo mock: 1.2.0
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'org.example.test',
      version: '1.2.0',
      buildNumber: '1',
      buildSignature: '',
    );
    registerFallbackValue(const Version(major: 0));
    registerFallbackValue(File(""));
    registerFallbackValue(<UpgradeMessage>[]);
  });

  late MockVersionRepository versionRepo;
  late MockUpgradeMessagesRepository upgradeMessages;
  late MockUpdater updater;
  late List<http.BaseRequest> downloads;
  late Directory tempDir;

  setUp(() async {
    versionRepo = MockVersionRepository();
    upgradeMessages = MockUpgradeMessagesRepository();
    updater = MockUpdater();
    downloads = [];
    when(
      () => versionRepo.getLatestVersionTag(force: true),
    ).thenAnswer((_) async => "v2.0.0");
    when(
      () => upgradeMessages.fetchMessagesForUpdate(any()),
    ).thenAnswer((_) async => [_message]);
    when(
      () => updater.generateDownloadFileNames(any()),
    ).thenAnswer((_) async => ["Test-2.0.0.bin"]);
    when(() => updater.install(any())).thenAnswer((_) async {});

    tempDir = await Directory.systemTemp.createTemp("auto_update_test");
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _pathProviderChannel,
          (_) async => tempDir.path,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    await tempDir.delete(recursive: true);
  });

  AutoUpdateRepository build({bool withUpgradeMessages = true}) =>
      AutoUpdateRepository(
        config: _config,
        versionRepository: versionRepo,
        github: GitHubService(
          config: _config,
          httpClient: MockClient((_) async => http.Response("", 500)),
        ),
        upgradeMessagesRepository: withUpgradeMessages ? upgradeMessages : null,
        httpClient: MockClient((request) async {
          downloads.add(request);
          return http.Response.bytes(utf8.encode("installer"), 200);
        }),
        updater: updater,
      );

  group('prepareUpdate', () {
    test('newer version -> tag and messages, status initial', () async {
      final repo = build();

      final future = repo.prepareUpdate();
      expect(repo.status, AutoUpdateStatus.checkingVersion);
      final pending = await future;

      expect(pending!.tag, "v2.0.0");
      expect(pending.messages, [_message]);
      expect(repo.status, AutoUpdateStatus.initial);
      verify(() => upgradeMessages.fetchMessagesForUpdate("v2.0.0")).called(1);
      repo.dispose();
    });

    test('no newer version -> null, messages not fetched', () async {
      when(
        () => versionRepo.getLatestVersionTag(force: true),
      ).thenAnswer((_) async => "v1.2.0");
      final repo = build();

      expect(await repo.prepareUpdate(), isNull);
      expect(repo.status, AutoUpdateStatus.initial);
      verifyNever(() => upgradeMessages.fetchMessagesForUpdate(any()));
      repo.dispose();
    });

    test('no tag -> null', () async {
      when(
        () => versionRepo.getLatestVersionTag(force: true),
      ).thenAnswer((_) async => null);
      final repo = build();

      expect(await repo.prepareUpdate(), isNull);
      expect(repo.status, AutoUpdateStatus.initial);
      repo.dispose();
    });

    test('without upgrade messages repository -> no messages', () async {
      final repo = build(withUpgradeMessages: false);

      final pending = await repo.prepareUpdate();

      expect(pending!.tag, "v2.0.0");
      expect(pending.messages, isEmpty);
      repo.dispose();
    });

    test('fetching messages fails -> null, status failure', () async {
      when(
        () => upgradeMessages.fetchMessagesForUpdate(any()),
      ).thenThrow(const SocketException("offline"));
      final repo = build();

      expect(await repo.prepareUpdate(), isNull);
      expect(repo.status, AutoUpdateStatus.failure);
      repo.dispose();
    });

    test('can be retried after failure', () async {
      when(
        () => versionRepo.getLatestVersionTag(force: true),
      ).thenThrow(const SocketException("offline"));
      final repo = build();
      await repo.prepareUpdate();
      when(
        () => versionRepo.getLatestVersionTag(force: true),
      ).thenAnswer((_) async => "v2.0.0");

      expect(await repo.prepareUpdate(), isNotNull);
      repo.dispose();
    });

    test('while running -> null', () async {
      final repo = build();

      final first = repo.prepareUpdate();
      expect(await repo.prepareUpdate(), isNull);
      await first;

      verify(() => versionRepo.getLatestVersionTag(force: true)).called(1);
      repo.dispose();
    });
  });

  group('update', () {
    const pending = PendingUpdate(tag: "v2.0.0");

    test('downloads the release file and installs it', () async {
      final repo = build();
      File? installed;
      when(() => updater.install(any())).thenAnswer((invocation) async {
        installed = invocation.positionalArguments.single as File;
        expect(await installed!.readAsString(), "installer");
      });

      await repo.update(pending);

      expect(
        downloads.single.url.toString(),
        "https://github.com/owner/repo/releases/download/v2.0.0/"
        "Test-2.0.0.bin",
      );
      verify(() => updater.generateDownloadFileNames(Version.parse("v2.0.0")));
      expect(installed, isNotNull);
      expect(await installed!.exists(), isFalse);
      expect(repo.status, AutoUpdateStatus.success);
      repo.dispose();
    });

    test('sets status synchronously, second call is ignored', () async {
      final fileNames = Completer<List<String>>();
      when(
        () => updater.generateDownloadFileNames(any()),
      ).thenAnswer((_) => fileNames.future);
      final repo = build();

      final first = repo.update(pending);
      expect(repo.status, AutoUpdateStatus.downloading);
      await repo.update(pending);
      expect(await repo.prepareUpdate(), isNull);
      fileNames.complete(["Test-2.0.0.bin"]);
      await first;

      verify(() => updater.generateDownloadFileNames(any())).called(1);
      verifyNever(() => versionRepo.getLatestVersionTag(force: true));
      expect(downloads, hasLength(1));
      repo.dispose();
    });

    test('install fails -> status failure', () async {
      when(
        () => updater.install(any()),
      ).thenThrow(const FileSystemException("broken"));
      final repo = build();

      await repo.update(pending);

      expect(repo.status, AutoUpdateStatus.failure);
      repo.dispose();
    });

    test('cancelled by user -> status initial', () async {
      when(
        () => updater.install(any()),
      ).thenThrow(const UpdateCancelledException());
      final repo = build();

      await repo.update(pending);

      expect(repo.status, AutoUpdateStatus.initial);
      repo.dispose();
    });
  });

  test('markUpgradeMessagesShown delegates to repository', () async {
    when(() => upgradeMessages.markShown(any())).thenAnswer((_) async {});
    final repo = build();

    await repo.markUpgradeMessagesShown(
      PendingUpdate(tag: "v2.0.0", messages: [_message]),
    );

    verify(() => upgradeMessages.markShown([_message])).called(1);
    repo.dispose();
  });
}
