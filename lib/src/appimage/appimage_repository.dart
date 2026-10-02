import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_system_integration/src/config.dart';
import 'package:flutter_system_integration/src/key_value_store.dart';
import 'package:flutter_system_integration/src/log.dart';
import 'package:flutter_system_integration/src/version/version.dart';
import 'package:flutter_system_integration/src/version/version_repository.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

final _log = createLogger("AppImageRepository");

/// Integrates an AppImage into the desktop environment by moving it to
/// `~/.local/bin` and creating a .desktop file.
class AppImageRepository {
  static const integrationDisabledKey = "integrate_appimage_disabled";

  static bool get isAppImage =>
      !kIsWeb &&
      Platform.isLinux &&
      Platform.environment.containsKey("APPIMAGE");

  static File? _overrideAppImageFile;

  /// The currently running AppImage file.
  static File get appImageFile =>
      _overrideAppImageFile ?? File(Platform.environment["APPIMAGE"]!).absolute;

  static String get _home => Platform.environment["HOME"] ?? "~";

  static String get _binDirPath => path.join(_home, ".local", "bin");

  static String get _desktopFileDirPath =>
      path.join(_home, ".local", "share", "applications");

  final SystemIntegrationConfig _config;
  final KeyValueStore _keyValue;

  AppImageRepository({required this._config, required this._keyValue});

  String get _integratedAppImagePath =>
      path.join(_binDirPath, _config.executableName);

  Future<bool> shouldIntegrate() async {
    if (!isAppImage) {
      _log.finest("Skipping AppImage integration check: not an AppImage");
      return false;
    }

    if (_config.appImageIntegrationExternallyDisabled) {
      _log.finest(
        "Skipping AppImage integration check: disabled by env variable",
      );
      return false;
    }

    final currentVersion = await VersionRepository.getCurrentVersion();

    final disabled = await _keyValue.loadObject(
      integrationDisabledKey,
      Version.fromJson,
    );
    if (disabled != null && disabled == currentVersion) {
      _log.fine("AppImage integration is disabled for version $disabled");
      return false;
    }

    return !await isIntegrated();
  }

  Future<void> integrate() async {
    _log.fine("Integrating AppImage into system...");
    final iconDir = await getApplicationSupportDirectory();
    final iconPath = path.join(iconDir.path, "${_config.executableName}.png");

    _log.finest("Copying icon file...");
    final iconBytes = await rootBundle.load(_config.desktopIconAsset);
    await File(iconPath).writeAsBytes(Uint8List.sublistView(iconBytes));

    final appImagePath = _integratedAppImagePath;
    await Directory(_binDirPath).create(recursive: true);
    _log.finest("Moving AppImage...");
    _overrideAppImageFile = (await appImageFile.rename(appImagePath)).absolute;

    try {
      _log.finest("Ensuring AppImage is executable...");
      await Process.run("chmod", ["+x", appImagePath]);
    } catch (e, st) {
      _log.warning(
        "Failed to ensure that the integrated AppImage is executable",
        e,
        st,
      );
    }

    _log.finest("Creating desktop file...");
    final desktopFile = await File(
      path.join(_desktopFileDirPath, "${_config.desktopId}.desktop"),
    ).create(recursive: true);
    await desktopFile.writeAsString("""[Desktop Entry]
Icon=$iconPath
Exec=$appImagePath
Type=Application
Categories=${_config.desktopCategories.join(";")}
Name=${_config.appName}
StartupWMClass=${_config.desktopId}
Terminal=false
StartupNotify=true
""", flush: true);

    try {
      _log.finest("Updating desktop database...");
      await Process.run("update-desktop-database", [_desktopFileDirPath]);
    } catch (e, st) {
      _log.fine(
        "Failed to update desktop database, update-desktop-database is probably not installed",
        e,
        st,
      );
    }

    await _keyValue.remove(integrationDisabledKey);

    _log.info("Successfully integrated AppImage into system!");
  }

  /// Stops asking to integrate until the app is updated.
  Future<void> disableIntegration() async {
    final version = await VersionRepository.getCurrentVersion();
    await _keyValue.store(integrationDisabledKey, version);
    _log.fine("User disabled AppImage integration for version $version");
  }

  Future<bool> isIntegrated() async {
    _log.finest("The current AppImage path is: $appImageFile");

    if (!await appImageFile.exists()) {
      _log.severe(
        "APPIMAGE environment variable does not point to a valid file",
      );
      return true;
    }

    final desiredAppImageFile = File(_integratedAppImagePath);
    if (!await desiredAppImageFile.exists()) {
      _log.fine(
        "AppImage is not integrated because there is no AppImage at the desired system path",
      );
      return false;
    }

    final integrated = path.equals(appImageFile.path, desiredAppImageFile.path);
    if (integrated) {
      _log.fine("AppImage already integrated");
    } else {
      _log.fine(
        "AppImage not integrated because the current AppImage is not at the correct location",
      );
    }
    return integrated;
  }
}
