@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_system_integration/src/auto_update/updaters/updater_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp("updater_windows_test");
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// Stands in for the installer, writes its arguments to `marker.txt`.
  Future<File> createInstaller(String directoryName) async {
    final installerDir = Directory(path.join(dir.path, directoryName));
    await installerDir.create();
    final installer = File(path.join(installerDir.path, "installer.cmd"));
    await installer.writeAsString('@echo %*> "%~dp0marker.txt"\r\n');
    return installer;
  }

  for (final name in [
    "plain",
    "with space",
    "o'brien",
    "a''b 'c'",
    "dollar \$env;TEMP `tick` & (1)",
  ]) {
    test('install command runs and removes installer in "$name"', () async {
      final installer = await createInstaller(name);
      final marker = File(path.join(installer.parent.path, "marker.txt"));

      // the pid of an already exited process, there is nothing to wait for
      final exited = await Process.start("cmd", ["/c", "exit"]);
      await exited.exitCode;

      final result = await Process.run(
        "powershell",
        UpdaterWindows.installArguments(installer.path, exited.pid),
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect((await marker.readAsString()).trim(), "/SP-");
      expect(await installer.exists(), isFalse);
    });
  }

  test("install command does not wait for processes started by the "
      "installer", () async {
    final installerDir = Directory(path.join(dir.path, "launch"));
    await installerDir.create();
    final installer = File(path.join(installerDir.path, "installer.cmd"));
    // stands in for the app the installer launches when it is done
    await installer.writeAsString(
      '@start "" /b /d "%SystemRoot%" ping -n 20 127.0.0.1 >nul\r\n',
    );

    final exited = await Process.start("cmd", ["/c", "exit"]);
    await exited.exitCode;

    final stopwatch = Stopwatch()..start();
    final result = await Process.run(
      "powershell",
      UpdaterWindows.installArguments(installer.path, exited.pid),
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    expect(await installer.exists(), isFalse);
  });

  test("install command waits for the app to exit", () async {
    final installer = await createInstaller("wait");
    final marker = File(path.join(installer.parent.path, "marker.txt"));

    final app = await Process.start("powershell", [
      "-NoProfile",
      "-Command",
      "Start-Sleep -Seconds 4",
    ]);
    final install = Process.run(
      "powershell",
      UpdaterWindows.installArguments(installer.path, app.pid),
    );

    await Future.any([app.exitCode, install]);
    expect(await marker.exists(), isFalse);

    final result = await install;
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(await marker.exists(), isTrue);
  });
}
