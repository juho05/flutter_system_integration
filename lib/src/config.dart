import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_system_integration/src/github/base_uri.dart';

class SystemIntegrationConfig {
  /// Display name, e.g. `Sheetopia`.
  ///
  /// Also used as the prefix of release asset names
  /// (`<appName>-<version>-<platform>.<ext>`), as the macOS app bundle name
  /// (`<appName>.app`) and in the HTTP user agent.
  final String appName;

  /// Name of the integrated AppImage in `~/.local/bin`.
  final String executableName;

  /// Prefix of environment variables, e.g. `SHEETOPIA` results in
  /// `SHEETOPIA_DISABLE_VERSION_CHECK`,
  /// `SHEETOPIA_DISABLE_APPIMAGE_INTEGRATION`, `SHEETOPIA_GITHUB_API_URL` and
  /// `SHEETOPIA_GITHUB_WEB_URL`.
  ///
  /// On Android, where apps can't be started with environment variables, the
  /// GitHub URLs are read from the system properties
  /// `debug.sheetopia.github_api_url` and `debug.sheetopia.github_web_url`
  /// instead, which are set via `adb shell setprop`.
  final String envPrefix;

  final String githubOwner;
  final String githubRepo;

  /// Used as the .desktop file name and `StartupWMClass`.
  final String desktopId;

  /// Asset key of the PNG icon used for the .desktop file.
  final String desktopIconAsset;

  final List<String> desktopCategories;

  const SystemIntegrationConfig({
    required this.appName,
    required this.executableName,
    required this.envPrefix,
    required this.githubOwner,
    required this.githubRepo,
    required this.desktopId,
    required this.desktopIconAsset,
    required this.desktopCategories,
  });

  Uri get releasesUrl => githubWebBaseUri.resolveUri(
    Uri(pathSegments: [githubOwner, githubRepo, "releases"]),
  );

  /// Base URL of the GitHub REST API. Overridable for testing against a fake
  /// server, see [envPrefix].
  Uri get githubApiBaseUri =>
      parseBaseUri(_override("GITHUB_API_URL") ?? "https://api.github.com");

  /// Base URL of the GitHub website release downloads are served from.
  /// Overridable for testing against a fake server, see [envPrefix].
  Uri get githubWebBaseUri =>
      parseBaseUri(_override("GITHUB_WEB_URL") ?? "https://github.com");

  String? _override(String name) {
    if (kIsWeb) return null;
    if (Platform.isAndroid) {
      final property = "debug.${envPrefix.toLowerCase()}.${name.toLowerCase()}";
      return _androidOverrides.putIfAbsent(
        property,
        () => _nonBlank(_androidSystemProperty(property)),
      );
    }
    return _nonBlank(Platform.environment["${envPrefix}_$name"]);
  }

  /// Whether version checking is disabled via environment variable,
  /// `--dart-define=VERSION_CHECK=false` or because the app runs on the web.
  bool get versionCheckExternallyDisabled {
    if (kIsWeb) return true;
    if (!const bool.fromEnvironment("VERSION_CHECK", defaultValue: true)) {
      return true;
    }
    return Platform.environment["${envPrefix}_DISABLE_VERSION_CHECK"] == "1";
  }

  bool get appImageIntegrationExternallyDisabled =>
      !kIsWeb &&
      Platform.environment["${envPrefix}_DISABLE_APPIMAGE_INTEGRATION"] == "1";
}

final _androidOverrides = <String, String?>{};

String? _nonBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _androidSystemProperty(String name) {
  try {
    final result = Process.runSync("getprop", [name]);
    if (result.exitCode != 0) return "";
    return result.stdout as String;
  } on ProcessException {
    return "";
  }
}
