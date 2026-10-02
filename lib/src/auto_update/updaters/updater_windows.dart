import 'dart:io';

import 'package:flutter_system_integration/src/auto_update/updaters/updater.dart';
import 'package:flutter_system_integration/src/log.dart';
import 'package:flutter_system_integration/src/version/version.dart';

final _log = createLogger("UpdaterWindows");

class UpdaterWindows implements Updater {
  final String _appName;

  UpdaterWindows({required this._appName});

  @override
  Future<String> generateDownloadFileName(Version version) async =>
      "$_appName-$version-windows-x86-64.exe";

  @override
  Future<void> install(File downloadedFile) async {
    _log.fine("Running installer ${downloadedFile.path}...");
    Process.run("powershell", [
      "-Command",
      "Start-Sleep -Seconds 2; &'${downloadedFile.absolute.path}' /SP-",
    ]);
    await Future.delayed(const Duration(seconds: 1), () => exit(0));
  }
}
