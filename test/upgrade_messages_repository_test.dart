import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _asset = "assets/upgrade_messages.json";

const _config = SystemIntegrationConfig(
  appName: "Test",
  executableName: "test",
  envPrefix: "TEST",
  githubOwner: "owner",
  githubRepo: "repo",
  desktopId: "org.example.test",
  desktopIconAsset: "assets/icon.png",
  desktopCategories: ["Utility"],
  upgradeMessagesAsset: _asset,
);

const _configWithoutMessages = SystemIntegrationConfig(
  appName: "Test",
  executableName: "test",
  envPrefix: "TEST",
  githubOwner: "owner",
  githubRepo: "repo",
  desktopId: "org.example.test",
  desktopIconAsset: "assets/icon.png",
  desktopCategories: ["Utility"],
);

class _MemoryKeyValueStore implements KeyValueStore {
  final Map<String, Object?> values = {};

  @override
  Future<void> store<T>(String key, T value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<String?> loadString(String key) async => values[key] as String?;

  @override
  Future<bool?> loadBool(String key) async => values[key] as bool?;

  @override
  Future<DateTime?> loadDateTime(String key) async => values[key] as DateTime?;

  @override
  Future<T?> loadObject<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final value = values[key];
    if (value == null) return null;
    // round trip through JSON like a real store
    return fromJson(jsonDecode(jsonEncode(value)) as Map<String, dynamic>);
  }
}

class _FakeBundle extends CachingAssetBundle {
  String? content;
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    loads++;
    final content = this.content;
    if (key != _asset || content == null) {
      throw FlutterError("Unable to load asset: $key");
    }
    return ByteData.sublistView(utf8.encode(content));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      super.loadString(key, cache: false);
}

String _file(List<String> versions) => jsonEncode({
  "messages": [
    for (final v in versions) {"version": v, "message": "message $v"},
  ],
});

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
  });

  late _MemoryKeyValueStore keyValue;
  late _FakeBundle bundle;
  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;

  setUp(() {
    VersionRepository.resetPreviousVersion();
    keyValue = _MemoryKeyValueStore();
    bundle = _FakeBundle()
      ..content = _file(["2.0.0", "1.0.0", "1.2.0", "1.1.0", "1.3.0"]);
    requests = [];
    respond = (_) => http.Response(
      _file(["1.0.0", "1.2.0", "1.3.0", "2.0.0", "2.1.0"]),
      200,
    );
  });

  UpgradeMessagesRepository build({
    SystemIntegrationConfig config = _config,
    bool withGitHub = true,
  }) => UpgradeMessagesRepository(
    config: config,
    keyValue: keyValue,
    github: withGitHub
        ? GitHubService(
            config: config,
            httpClient: MockClient((request) async {
              requests.add(request);
              return respond(request);
            }),
          )
        : null,
    bundle: bundle,
  );

  void setPrevious(String version) =>
      keyValue.values["version.current"] = Version.parse(version);

  List<String> versionsOf(List<UpgradeMessage> messages) =>
      messages.map((m) => m.version.toString()).toList();

  group('parseFile', () {
    test('parses title and message', () {
      final messages = UpgradeMessage.parseFile(
        jsonEncode({
          "messages": [
            {"version": "v2.0.0", "title": "Title", "message": "Text"},
          ],
        }),
      );
      expect(messages.single.version, const Version(major: 2));
      expect(messages.single.title, "Title");
      expect(messages.single.message, "Text");
    });

    test('ignores unknown keys', () {
      final messages = UpgradeMessage.parseFile(
        jsonEncode({
          "formatVersion": 2,
          "messages": [
            {
              "version": "2.0.0",
              "message": "Text",
              "localized": {
                "de": {"message": "Text"},
              },
            },
          ],
        }),
      );
      expect(messages, hasLength(1));
    });

    test('skips invalid entries', () {
      final messages = UpgradeMessage.parseFile(
        jsonEncode({
          "messages": [
            "not an object",
            {"version": "2.0.0"},
            {"version": "invalid", "message": "Text"},
            {"version": "2.0.0", "message": "Text", "title": 1},
            {
              "version": "2.0.0",
              "message": {"en": "Text"},
            },
            {"version": "3.0.0", "message": "Text"},
          ],
        }),
      );
      expect(versionsOf(messages), ["3.0.0"]);
    });

    test('missing messages list -> empty', () {
      expect(UpgradeMessage.parseFile("{}"), isEmpty);
    });

    test('not an object -> FormatException', () {
      expect(
        () => UpgradeMessage.parseFile("[]"),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('getStartupMessages', () {
    test('fresh install -> none, records current version', () async {
      expect(await build().getStartupMessages(), isEmpty);
      expect(
        keyValue.values["version.current"],
        const Version(major: 1, minor: 2),
      );
    });

    test('upgrade -> messages after previous up to current, sorted', () async {
      setPrevious("1.0.0");
      final messages = await build().getStartupMessages();
      expect(versionsOf(messages), ["1.1.0", "1.2.0"]);
    });

    test('works without GitHub service', () async {
      setPrevious("1.0.0");
      final messages = await build(withGitHub: false).getStartupMessages();
      expect(versionsOf(messages), ["1.1.0", "1.2.0"]);
      expect(requests, isEmpty);
    });

    test('same version -> none', () async {
      setPrevious("1.2.0");
      expect(await build().getStartupMessages(), isEmpty);
    });

    test('downgrade -> none', () async {
      setPrevious("2.0.0");
      expect(await build().getStartupMessages(), isEmpty);
    });

    test('excludes messages shown before installing', () async {
      setPrevious("1.0.0");
      final repo = build();
      // shown before the update, while 1.0.0 was running
      keyValue.values["upgrade_messages.shown"] = {
        "versions": [Version.parse("1.2.0").toJson()],
      };

      expect(versionsOf(await repo.getStartupMessages()), ["1.1.0"]);
    });

    test('prunes shown versions up to current', () async {
      setPrevious("1.2.0");
      keyValue.values["upgrade_messages.shown"] = {
        "versions": [
          Version.parse("1.1.0").toJson(),
          Version.parse("1.3.0").toJson(),
        ],
      };

      await build().getStartupMessages();

      final shown = await keyValue.loadObject(
        "upgrade_messages.shown",
        (json) => json,
      );
      expect(shown!["versions"], [Version.parse("1.3.0").toJson()]);
    });

    test('no asset configured -> none, bundle not read', () async {
      setPrevious("1.0.0");
      final repo = build(config: _configWithoutMessages);
      expect(await repo.getStartupMessages(), isEmpty);
      expect(bundle.loads, 0);
    });

    test('missing asset -> none', () async {
      setPrevious("1.0.0");
      bundle.content = null;
      expect(await build().getStartupMessages(), isEmpty);
    });

    test('invalid asset -> none', () async {
      setPrevious("1.0.0");
      bundle.content = "not json";
      expect(await build().getStartupMessages(), isEmpty);
    });
  });

  group('fetchMessagesForUpdate', () {
    test(
      'requests file at tag, returns messages after current up to tag',
      () async {
        final messages = await build().fetchMessagesForUpdate("v2.0.0");

        expect(versionsOf(messages), ["1.3.0", "2.0.0"]);
        final request = requests.single;
        expect(
          request.url.toString(),
          "https://api.github.com/repos/owner/repo/contents/assets/"
          "upgrade_messages.json?ref=v2.0.0",
        );
        expect(request.headers["Accept"], "application/vnd.github.raw+json");
      },
    );

    test('excludes shown messages', () async {
      final repo = build();
      await repo.markShown([
        UpgradeMessage(version: Version.parse("1.3.0"), message: ""),
      ]);
      expect(versionsOf(await repo.fetchMessagesForUpdate("v2.0.0")), [
        "2.0.0",
      ]);
    });

    test('uses repo path override', () async {
      const config = SystemIntegrationConfig(
        appName: "Test",
        executableName: "test",
        envPrefix: "TEST",
        githubOwner: "owner",
        githubRepo: "repo",
        desktopId: "org.example.test",
        desktopIconAsset: "assets/icon.png",
        desktopCategories: ["Utility"],
        upgradeMessagesAsset: _asset,
        upgradeMessagesRepoPath: "app/assets/upgrade messages.json",
      );
      await build(config: config).fetchMessagesForUpdate("v2.0.0");
      expect(
        requests.single.url.path,
        "/repos/owner/repo/contents/app/assets/upgrade%20messages.json",
      );
    });

    test('404 -> none', () async {
      respond = (_) => http.Response("", 404);
      expect(await build().fetchMessagesForUpdate("v2.0.0"), isEmpty);
    });

    test('invalid file -> none', () async {
      respond = (_) => http.Response("not json", 200);
      expect(await build().fetchMessagesForUpdate("v2.0.0"), isEmpty);
    });

    test('decodes UTF-8 without charset in content type', () async {
      respond = (_) => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            "messages": [
              {"version": "2.0.0", "message": "Änderungen übernommen"},
            ],
          }),
        ),
        200,
        headers: {"content-type": "application/vnd.github.raw"},
      );
      final messages = await build().fetchMessagesForUpdate("v2.0.0");
      expect(messages.single.message, "Änderungen übernommen");
    });

    test('other status -> throws', () async {
      respond = (_) => http.Response("", 500);
      expect(
        () => build().fetchMessagesForUpdate("v2.0.0"),
        throwsA(isA<GitHubUnexpectedStatusCode>()),
      );
    });

    test('no asset configured -> none, no request', () async {
      final repo = build(config: _configWithoutMessages);
      expect(await repo.fetchMessagesForUpdate("v2.0.0"), isEmpty);
      expect(requests, isEmpty);
    });

    test('without GitHub service -> throws', () async {
      expect(
        () => build(withGitHub: false).fetchMessagesForUpdate("v2.0.0"),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('markShown', () {
    test('drops versions up to current', () async {
      await build().markShown([
        UpgradeMessage(version: Version.parse("1.1.0"), message: ""),
        UpgradeMessage(version: Version.parse("2.0.0"), message: ""),
      ]);
      final shown = await keyValue.loadObject(
        "upgrade_messages.shown",
        (json) => json,
      );
      expect(shown!["versions"], [Version.parse("2.0.0").toJson()]);
    });
  });
}
