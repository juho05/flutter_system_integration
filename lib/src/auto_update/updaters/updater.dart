import 'dart:io';

import 'package:flutter_system_integration/src/log.dart';
import 'package:flutter_system_integration/src/version/version.dart';

final _log = createLogger("Updater");

abstract class Updater {
  Future<String> generateDownloadFileName(Version version);

  Future<void> install(File downloadedFile);

  /// Whether the user has to grant a permission before [install] can succeed.
  Future<bool> needsInstallPermission() async => false;

  /// Asks the user to grant the install permission. Returns whether it was
  /// granted.
  Future<bool> requestInstallPermission() async => true;
}

/// Runs [beforeExit] without letting it prevent the exit that follows. The
/// update helper is already running at this point and waits for the app to
/// exit.
Future<void> runBeforeExit(Future<void> Function()? beforeExit) async {
  if (beforeExit == null) return;
  try {
    await beforeExit().timeout(const Duration(seconds: 5));
  } catch (e, st) {
    _log.warning("beforeExit callback failed", e, st);
  }
}

/// Thrown by [Updater.install] if the user cancelled the installation.
class UpdateCancelledException implements Exception {
  const UpdateCancelledException();

  @override
  String toString() => "update was cancelled by the user";
}

class NonZeroExitException implements Exception {
  final int exitCode;
  final dynamic errOut;

  const NonZeroExitException(this.exitCode, this.errOut);

  @override
  String toString() => "process exited with status code $exitCode: \n$errOut";
}

void throwOnNonZeroExitCode(ProcessResult result) {
  if (result.exitCode != 0) {
    throw NonZeroExitException(result.exitCode, result.stderr);
  }
}
