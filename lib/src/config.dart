import 'dart:io';

import 'package:flutter/foundation.dart';

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
  /// `SHEETOPIA_DISABLE_VERSION_CHECK` and
  /// `SHEETOPIA_DISABLE_APPIMAGE_INTEGRATION`.
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

  Uri get releasesUrl =>
      Uri.https("github.com", "/$githubOwner/$githubRepo/releases");

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
