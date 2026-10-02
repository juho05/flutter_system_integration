import 'dart:io';

import 'package:android_package_installer/android_package_installer.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_system_integration/src/auto_update/updaters/updater.dart';
import 'package:flutter_system_integration/src/log.dart';
import 'package:flutter_system_integration/src/version/version.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';

final _log = createLogger("UpdaterAndroid");

class AndroidUpdateFailedException implements Exception {
  final PackageInstallerStatus status;
  final String message;

  AndroidUpdateFailedException(this.message, this.status);

  @override
  String toString() => "AndroidUpdateFailedException: ${status.name}: $message";
}

class UpdaterAndroid implements Updater {
  static const _defaultArch = "arm64v8";

  final _deviceInfo = DeviceInfoPlugin();
  final String _appName;

  UpdaterAndroid({required this._appName});

  @override
  Future<String> generateDownloadFileName(Version version) async {
    String arch;
    try {
      arch = await _getArchitecture();
    } on Exception catch (e, st) {
      _log.severe(
        "Failed to get system architecture. Defaulting to $_defaultArch",
        e,
        st,
      );
      arch = _defaultArch;
    }
    return "$_appName-$version-android-$arch.apk";
  }

  @override
  Future<void> install(File downloadedFile) async {
    if (await _isMIUIDevice()) {
      if (!await _requestInstallApkPermission()) {
        throw AndroidUpdateFailedException(
          "User declined APK install permission",
          PackageInstallerStatus.failureAborted,
        );
      }
      return await _openApk(downloadedFile);
    }
    return await _installApk(downloadedFile);
  }

  Future<void> _installApk(File downloadedFile) async {
    final statusCode = await AndroidPackageInstaller.installApk(
      apkFilePath: downloadedFile.path,
    );
    if (statusCode == null) {
      throw AndroidUpdateFailedException(
        "Unknown APK install status, assuming failure",
        PackageInstallerStatus.unknown,
      );
    }
    final status = PackageInstallerStatus.byCode(statusCode);
    if (status != PackageInstallerStatus.success) {
      throw AndroidUpdateFailedException("Failed to install APK", status);
    }
  }

  Future<bool> _requestInstallApkPermission() async {
    if (await Permission.requestInstallPackages.isGranted) {
      return true;
    }
    return (await Permission.requestInstallPackages.request()).isGranted;
  }

  Future<void> _openApk(File downloadedFile) async {
    final result = await OpenFile.open(
      downloadedFile.path,
      type: "application/vnd.android.package-archive",
    );
    if (result.type != ResultType.done) {
      throw AndroidUpdateFailedException(
        "Failed to open APK file",
        PackageInstallerStatus.failure,
      );
    }
  }

  Future<bool> _isMIUIDevice() async {
    final androidInfo = await _deviceInfo.androidInfo;
    return androidInfo.manufacturer.toLowerCase() == "xiaomi";
  }

  Future<String> _getArchitecture() async {
    final androidInfo = await _deviceInfo.androidInfo;
    final abis = androidInfo.supportedAbis;
    if (abis.contains("arm64-v8a")) {
      return "arm64v8";
    }
    if (abis.contains("armeabi-v7a")) {
      return "arm32v7";
    }
    if (abis.contains("x86_64")) {
      return "x64";
    }
    _log.warning(
      "Couldn't find known ABI in list: $abis. Defaulting to $_defaultArch",
    );
    return _defaultArch;
  }
}
