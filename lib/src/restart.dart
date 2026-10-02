import 'dart:io';

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

  static Future<void> _restartAppImage() async {
    _log.info("Restarting application...");

    Process.run("/bin/bash", [
      "-c",
      "/bin/bash -c \"sleep 2 && ${AppImageRepository.appImageFile.path.replaceAll(" ", "\\ ")}\" & disown",
    ]);

    await Future.delayed(const Duration(milliseconds: 250), () => exit(0));
  }
}
