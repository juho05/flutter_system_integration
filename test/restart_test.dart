@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp("restart_test");
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  for (final name in [
    "App.AppImage",
    "My App.AppImage",
    "App-1.0.0-linux-x86-64 (1).AppImage",
    "App \$HOME 'a' \"b\" & ; `c`.AppImage",
  ]) {
    test('restart command executes "$name"', () async {
      final marker = File(path.join(dir.path, "marker"));
      final script = File(path.join(dir.path, name));
      await script.writeAsString('#!/bin/sh\nprintf started > "\$MARKER"\n');
      await Process.run("chmod", ["+x", script.path]);

      final arguments = Restart.appImageRestartArguments(script.path);
      // skip the delay that gives the old instance time to exit
      arguments[1] = arguments[1].replaceFirst("sleep 2", "sleep 0");
      final result = await Process.run(
        "/bin/bash",
        arguments,
        environment: {"MARKER": marker.path},
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(await marker.readAsString(), "started");
    });
  }
}
