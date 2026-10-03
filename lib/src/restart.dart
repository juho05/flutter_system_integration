import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_system_integration/src/appimage/appimage_repository.dart';
import 'package:flutter_system_integration/src/log.dart';

final _log = createLogger("Restart");

class Restart {
  static bool get supported => AppImageRepository.isAppImage;

  static Future<void> restart() async {
    if (AppImageRepository.isAppImage) {
      return _restartAppImage();
    }
    throw UnsupportedError("restarts are not supported on this platform");
  }

  /// The executable path is passed as `$0` so it never gets parsed by the
  /// shell.
  @visibleForTesting
  static List<String> appImageRestartArguments(String appImagePath) => [
    "-c",
    'sleep 2; exec "\$0"',
    appImagePath,
  ];

  static Future<void> _restartAppImage() async {
    _log.info("Restarting application...");

    // detached so the new instance does not inherit open file descriptors,
    // which would keep the mount of the old AppImage alive
    await Process.start(
      "/bin/bash",
      appImageRestartArguments(AppImageRepository.appImageFile.path),
      mode: ProcessStartMode.detached,
    );

    await Future.delayed(const Duration(milliseconds: 250), () => exit(0));
  }
}
