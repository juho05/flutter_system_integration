import 'dart:io';

import 'package:flutter_system_integration/src/version/version.dart';

abstract class Updater {
  Future<String> generateDownloadFileName(Version version);

  Future<void> install(File downloadedFile);
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
