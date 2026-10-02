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

class UpdaterMacOS extends Updater {
  static final _teamIdRegex = RegExp(r"^TeamIdentifier=(.*)$", multiLine: true);

  /// Replaces the app bundle once the app has exited. Runs as the current
  /// user or as root. Restores the previous bundle and removes the staging
  /// copy on any failure.
  ///
  /// Arguments: pid, source app, target app
  static const _swapScript = r'''
pid="$1"; src="$2"; target="$3"
staging="$target.update"
backup="$target.old"
cleanup() {
  set +e
  [ -e "$target" ] || mv "$backup" "$target"
  rm -rf "$staging"
  [ -e "$target" ] && rm -rf "$backup"
}
cleanup
trap 'status=$?; cleanup; echo "$(date): swap as uid $(id -u) exited with status $status"' EXIT
trap 'exit 1' HUP INT TERM
while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
set -e
ditto "$src" "$staging"
if [ "$(id -u)" = 0 ]; then
  chown -R "$(stat -f %u:%g "$target")" "$staging"
fi
xattr -dr com.apple.quarantine "$staging" 2>/dev/null || true
mv "$target" "$backup"
mv "$staging" "$target"
''';

  /// Starts the swap script as root in the background and prints its pid.
  /// Must run as a direct child of the app, otherwise the admin prompt is
  /// attributed to launchd instead of the app.
  ///
  /// Arguments: admin prompt, swap script, pid, source app, target app,
  /// log file
  static const _privilegedLaunchScript = r'''
on run argv
  set cmd to "/bin/sh -c " & quoted form of item 2 of argv & " swap"
  repeat with i from 3 to 5
    set cmd to cmd & " " & quoted form of item i of argv
  end repeat
  set cmd to cmd & " </dev/null >>" & quoted form of item 6 of argv & " 2>&1 & echo $!"
  do shell script cmd with prompt (item 1 of argv) with administrator privileges
end run
''';

  /// Runs the swap script or waits for the privileged one, then detaches
  /// the DMG and relaunches the app as the current user.
  ///
  /// Arguments: pid of privileged swap (empty to swap as current user),
  /// pid, source app, target app, dmg file, mount point, log file,
  /// swap script
  static const _helperScript = r'''
swappid="$1"; pid="$2"; src="$3"; target="$4"; dmg="$5"; mnt="$6"
log="$7"; swap="$8"
exec </dev/null >>"$log" 2>&1
if [ -n "$swappid" ]; then
  echo "$(date): waiting for privileged update of $target"
  while ps -p "$swappid" >/dev/null; do sleep 0.2; done
else
  echo "$(date): updating $target"
  /bin/sh -c "$swap" swap "$pid" "$src" "$target"
fi
hdiutil detach "$mnt" || hdiutil detach -force "$mnt"
rmdir "$mnt" "$(dirname "$mnt")"
rm -f "$dmg"
open "$target"
''';

  final String _appName;

  UpdaterMacOS({required this._appName});

  @override
  Future<String> generateDownloadFileName(Version version) async =>
      "$_appName-$version-macOS-universal.dmg";

  @override
  Future<void> install(File downloadedFile) async {
    final targetApp = _currentAppBundle();
    final workDir = await Directory.systemTemp.createTemp(
      "${_appName}_update_",
    );
    final mountPoint = Directory(path.join(workDir.path, "mnt"));
    await mountPoint.create();

    _log.fine("Mounting DMG ${downloadedFile.path} at ${mountPoint.path}...");
    final attachResult = await Process.run("hdiutil", [
      "attach",
      "-nobrowse",
      "-readonly",
      "-noautoopen",
      "-mountpoint",
      mountPoint.path,
      downloadedFile.path,
    ]);
    throwOnNonZeroExitCode(attachResult);

    try {
      final sourceApp = path.join(mountPoint.path, "$_appName.app");
      if (!await Directory(sourceApp).exists()) {
        throw MacOSUpdateFailedException("DMG does not contain $_appName.app");
      }
      await _verifySignature(sourceApp, targetApp);

      final logFile = await _createLogFile();
      var swapPid = "";
      if (!await _isWritableByCurrentUser(targetApp)) {
        swapPid = await _startPrivilegedSwap(sourceApp, targetApp, logFile);
      }

      _log.fine("Starting update helper, log: ${logFile.path}...");
      await Process.start("/bin/sh", [
        "-c",
        _helperScript,
        "updater",
        swapPid,
        "$pid",
        sourceApp,
        targetApp,
        downloadedFile.path,
        mountPoint.path,
        logFile.path,
        _swapScript,
      ], mode: ProcessStartMode.detached);
      exit(0);
    } catch (_) {
      await Process.run("hdiutil", ["detach", "-force", mountPoint.path]);
      await workDir.delete(recursive: true);
      rethrow;
    }
  }

  /// Throws if the user cancels the admin prompt.
  Future<String> _startPrivilegedSwap(
    String sourceApp,
    String targetApp,
    File logFile,
  ) async {
    _log.fine("Requesting admin privileges...");
    final result = await Process.run("/usr/bin/osascript", [
      for (final line in _privilegedLaunchScript.trim().split("\n")) ...[
        "-e",
        line,
      ],
      "$_appName wants to install an update.",
      _swapScript,
      "$pid",
      sourceApp,
      targetApp,
      logFile.path,
    ]);
    throwOnNonZeroExitCode(result);
    final swapPid = (result.stdout as String).trim();
    if (int.tryParse(swapPid) == null) {
      throw MacOSUpdateFailedException(
        "unexpected output of privileged launch: $swapPid",
      );
    }
    return swapPid;
  }

  static String _currentAppBundle() {
    final bundle = path.dirname(
      path.dirname(path.dirname(Platform.resolvedExecutable)),
    );
    if (path.extension(bundle) != ".app") {
      throw MacOSUpdateFailedException(
        "not running from an app bundle: $bundle",
      );
    }
    if (bundle.contains("/AppTranslocation/")) {
      throw const MacOSUpdateFailedException(
        "app is translocated, move it to the Applications folder first",
      );
    }
    return bundle;
  }

  Future<void> _verifySignature(String newApp, String currentApp) async {
    _log.fine("Verifying signature of $newApp...");
    throwOnNonZeroExitCode(
      await Process.run("codesign", ["--verify", "--deep", "--strict", newApp]),
    );
    final newTeam = await _teamIdentifier(newApp);
    final currentTeam = await _teamIdentifier(currentApp);
    if (newTeam != currentTeam) {
      throw MacOSUpdateFailedException(
        "team identifier mismatch: current $currentTeam, new $newTeam",
      );
    }
  }

  Future<String?> _teamIdentifier(String app) async {
    final result = await Process.run("codesign", ["-dv", "--verbose=2", app]);
    throwOnNonZeroExitCode(result);
    return _teamIdRegex.firstMatch(result.stderr as String)?.group(1);
  }

  /// Bundles owned by another user can't be fully replaced without admin
  /// rights even if the parent directory is writable.
  Future<bool> _isWritableByCurrentUser(String app) async {
    final result = await Process.run("/bin/sh", [
      "-c",
      r'[ -w "$(dirname "$1")" ] && [ -O "$1" ] && [ -w "$1" ]',
      "check",
      app,
    ]);
    return result.exitCode == 0;
  }

  Future<File> _createLogFile() async {
    final logDir = Directory(
      path.join(Platform.environment["HOME"]!, "Library", "Logs", _appName),
    );
    await logDir.create(recursive: true);
    return File(path.join(logDir.path, "update.log"));
  }
}
