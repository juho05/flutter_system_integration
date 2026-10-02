import 'dart:convert';

import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  ) async => values[key] as T?;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'org.example.test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  late _MemoryKeyValueStore keyValue;
  late List<http.Request> requests;
  late List<String> tags;

  setUp(() {
    keyValue = _MemoryKeyValueStore();
    requests = [];
    tags = ["v0.9.0", "v1.1.0-beta", "v1.0.0", "not-a-version"];
  });

  VersionRepository build() {
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode([
          for (final t in tags) {"name": t},
        ]),
        200,
      );
    });
    return VersionRepository(
      config: _config,
      github: GitHubService(config: _config, httpClient: client),
      keyValue: keyValue,
    );
  }

  test('returns highest full version tag', () async {
    final repo = build();

    expect(await repo.getLatestVersionTag(), "v1.0.0");
    expect(await repo.getLatestVersion(), const Version(major: 1));
    expect(requests.first.url.path, "/repos/owner/repo/tags");
    expect(requests.first.url.queryParameters, {"per_page": "30"});
    expect(requests.first.headers["User-Agent"], "Test v1.0.0");
  });

  test('uses cached tag within check interval', () async {
    final repo = build();

    await repo.getLatestVersionTag();
    await repo.getLatestVersionTag();

    expect(requests, hasLength(1));
  });

  test('force bypasses cache', () async {
    final repo = build();

    await repo.getLatestVersionTag();
    tags = ["v2.0.0"];

    expect(await repo.getLatestVersionTag(force: true), "v2.0.0");
    expect(requests, hasLength(2));
  });

  test('returns null without valid tags', () async {
    tags = ["foo", "v1.0.0-rc"];
    final repo = build();

    expect(await repo.getLatestVersionTag(), isNull);
  });

  test('unexpected status code throws', () async {
    final repo = VersionRepository(
      config: _config,
      github: GitHubService(
        config: _config,
        httpClient: MockClient((_) async => http.Response("", 500)),
      ),
      keyValue: keyValue,
    );

    expect(
      repo.getLatestVersionTag(),
      throwsA(isA<GitHubUnexpectedStatusCode>()),
    );
  });

  test('release download link', () {
    final github = GitHubService(config: _config);
    expect(
      github
          .generateReleaseDownloadLink(
            owner: "owner",
            repo: "repo",
            tag: "v1.0.0",
            fileName: "Test-1.0.0-linux-x86-64.AppImage",
          )
          .toString(),
      "https://github.com/owner/repo/releases/download/v1.0.0/Test-1.0.0-linux-x86-64.AppImage",
    );
  });
}
