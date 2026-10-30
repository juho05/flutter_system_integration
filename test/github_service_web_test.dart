@TestOn('browser')
library;

import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default http client can be created on the web', () {
    expect(
      () => GitHubService(
        config: const SystemIntegrationConfig(
          appName: "Test",
          executableName: "test",
          envPrefix: "TEST",
          githubOwner: "owner",
          githubRepo: "repo",
          desktopId: "org.example.test",
          desktopIconAsset: "assets/icon.png",
          desktopCategories: [],
        ),
      ),
      returnsNormally,
    );
  });
}
