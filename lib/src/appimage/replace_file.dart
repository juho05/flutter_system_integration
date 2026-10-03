import 'dart:io';

import 'package:flutter_system_integration/src/auto_update/updaters/updater.dart';

/// Atomically replaces [targetPath] with an executable copy of [source].
///
/// The copy is written next to the target and then renamed over it, so the
/// target is never missing or partially written. This also works while the
/// target is being executed.
Future<File> replaceWithExecutableCopy(File source, String targetPath) async {
  final tmp = File("$targetPath.new");
  try {
    await source.copy(tmp.path);
    throwOnNonZeroExitCode(await Process.run("chmod", ["+x", tmp.path]));
    return (await tmp.rename(targetPath)).absolute;
  } catch (_) {
    if (await tmp.exists()) await tmp.delete();
    rethrow;
  }
}
