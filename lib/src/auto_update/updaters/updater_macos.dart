import 'dart:io';

import 'package:flutter_system_integration/src/auto_update/updaters/updater.dart';
import 'package:flutter_system_integration/src/log.dart';
import 'package:flutter_system_integration/src/version/version.dart';
import 'package:path/path.dart' as path;

final _log = createLogger("UpdaterMacOS");

class MacOSUpdateFailedException implements Exception {
  final String message;

  const MacOSUpdateFailedException(this.message);

  @override
  String toString() => "MacOSUpdateFailedException: $message";
}

class UpdaterMacOS implements Updater {
  static final _volumeRegex = RegExp("\\/Volumes\\/(.*)\n");

  final String _appName;

  UpdaterMacOS({required this._appName});

  @override
  Future<String> generateDownloadFileName(Version version) async =>
      "$_appName-$version-macOS-universal.dmg";

  @override
  Future<void> install(File downloadedFile) async {
    _log.fine("Mounting DMG ${downloadedFile.path}...");

    final dmgAttachResult = await Process.run("hdiutil", [
      "attach",
      "-nobrowse",
      "-readonly",
      downloadedFile.path,
    ], stdoutEncoding: systemEncoding);
    throwOnNonZeroExitCode(dmgAttachResult);

    final dmgAttachOutput = dmgAttachResult.stdout as String;
    final match = _volumeRegex.firstMatch(dmgAttachOutput);
    if (match == null) {
      throw MacOSUpdateFailedException(
        "failed to parse attach dmg output to determine volume:\n$dmgAttachOutput",
      );
    }
    final volumePath = "/Volumes/${match.group(1)!}";
    final sourceApp = path.join(volumePath, "$_appName.app");
    final targetApp = "/Applications/$_appName.app";
    final stagingApp = "/Applications/$_appName.app.update";

    Process.run("/bin/zsh", [
      "-c",
      "/bin/zsh -c \"sleep 2 && rm -rf $stagingApp && ditto \\\"$sourceApp\\\" $stagingApp && rm -rf $targetApp && mv $stagingApp $targetApp && xattr -r -d com.apple.quarantine $targetApp && sleep 1 && open $targetApp; hdiutil detach \\\"$volumePath\\\"\" & disown",
    ]);
    await Future.delayed(const Duration(milliseconds: 250), () => exit(0));
  }
}
