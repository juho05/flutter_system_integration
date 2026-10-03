import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_system_integration/src/auto_update/updaters/updater.dart';
import 'package:flutter_system_integration/src/log.dart';
import 'package:flutter_system_integration/src/version/version.dart';

final _log = createLogger("UpdaterWindows");

class UpdaterWindows extends Updater {
  final String _appName;
  final Future<void> Function()? _beforeExit;

  UpdaterWindows({required this._appName, this._beforeExit});

  @override
  Future<String> generateDownloadFileName(Version version) async =>
      "$_appName-$version-windows-x86-64.exe";

  /// Waits for the app to exit, runs the installer and removes it afterwards.
  ///
  /// The path is embedded as a single quoted PowerShell string, so the only
  /// character that needs escaping is the single quote.
  @visibleForTesting
  static List<String> installArguments(
    String installerPath,
    int appPid, {
    String installerArguments = "/SP-",
  }) {
    final installer = "'${installerPath.replaceAll("'", "''")}'";
    return [
      "-NoProfile",
      "-WindowStyle",
      "Hidden",
      "-Command",
      "Wait-Process -Id $appPid -Timeout 30 -ErrorAction SilentlyContinue; "
          // -Wait would also wait for the app the installer launches
          "\$p = Start-Process -FilePath $installer "
          "-ArgumentList '$installerArguments' -PassThru; "
          "\$p.WaitForExit(); "
          "Remove-Item -LiteralPath $installer -Force "
          "-ErrorAction SilentlyContinue",
    ];
  }

  @override
  Future<void> install(File downloadedFile) async {
    _log.fine("Running installer ${downloadedFile.path}...");
    // not started in the app directory so it doesn't keep the directory the
    // installer replaces in use
    await Process.start(
      "powershell",
      installArguments(downloadedFile.absolute.path, pid),
      workingDirectory: downloadedFile.parent.absolute.path,
    );
    await runBeforeExit(_beforeExit);
    exit(0);
  }
}
