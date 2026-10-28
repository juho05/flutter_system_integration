import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_system_integration/src/auto_update/updaters/updater.dart';
import 'package:flutter_system_integration/src/log.dart';
import 'package:flutter_system_integration/src/version/version.dart';

final _log = createLogger("UpdaterAndroid");

class AndroidUpdateFailedException implements Exception {
  final String message;

  /// The `PackageInstaller.STATUS_*` code reported by Android, if any.
  final int? status;

  AndroidUpdateFailedException(this.message, {this.status});

  @override
  String toString() =>
      "AndroidUpdateFailedException: $message${status != null ? " (status $status)" : ""}";
}

class UpdaterAndroid extends Updater {
  static const _channel = MethodChannel(
    "flutter_system_integration/apk_installer",
  );

  final _deviceInfo = DeviceInfoPlugin();
  final String _appName;

  UpdaterAndroid({required this._appName});

  @override
  Future<String> generateDownloadFileName(Version version) async =>
      (await generateDownloadFileNames(version)).first;

  @override
  Future<List<String>> generateDownloadFileNames(Version version) async {
    String? arch;
    try {
      arch = await _getArchitecture();
    } on Exception catch (e, st) {
      _log.warning(
        "Failed to get system architecture. Using universal APK",
        e,
        st,
      );
    }
    final universal = "$_appName-$version-android.apk";
    if (arch == null) {
      return [universal, "$_appName-$version-android-arm64v8.apk"];
    }
    return ["$_appName-$version-android-$arch.apk", universal];
  }

  @override
  Future<bool> needsInstallPermission() async =>
      await _channel.invokeMethod<bool>("hasInstallPermission") != true;

  @override
  Future<bool> requestInstallPermission() async =>
      await _channel.invokeMethod<bool>("requestInstallPermission") == true;

  @override
  Future<void> install(File downloadedFile) async {
    try {
      if (!await requestInstallPermission()) {
        throw AndroidUpdateFailedException(
          "User declined APK install permission",
        );
      }
      final method = await _channel.invokeMethod<String>("install", {
        "path": downloadedFile.path,
      });
      _log.fine("Installed APK via $method");
    } on PlatformException catch (e) {
      if (e.code == "INSTALL_ABORTED") throw const UpdateCancelledException();
      throw AndroidUpdateFailedException(
        "${e.code}: ${e.message}",
        status: e.details is int ? e.details as int : null,
      );
    }
  }

  Future<String?> _getArchitecture() async {
    final androidInfo = await _deviceInfo.androidInfo;
    final abis = androidInfo.supportedAbis;
    // supportedAbis is ordered by device preference
    for (final abi in abis) {
      switch (abi) {
        case "arm64-v8a":
          return "arm64v8";
        case "armeabi-v7a":
          return "arm32v7";
        case "x86_64":
          return "x64";
      }
    }
    _log.warning("Couldn't find known ABI in list: $abis. Using universal APK");
    return null;
  }
}
