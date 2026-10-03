@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_system_integration/src/auto_update/updaters/updater_linux_appimage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory dir;
  late File appImage;
  late File download;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp("updater_linux_appimage_test");
    appImage = File(path.join(dir.path, "App (1).AppImage"));
    await appImage.writeAsString("old");
    download = File(path.join(dir.path, "download", "App-1.1.0.AppImage"));
    await download.create(recursive: true);
    await download.writeAsString("new");
  });

  tearDown(() async {
    await Process.run("chmod", ["-R", "u+w", dir.path]);
    await dir.delete(recursive: true);
  });

  UpdaterLinuxAppImage buildUpdater() =>
      UpdaterLinuxAppImage(appName: "App", appImageFile: appImage);

  test('generateDownloadFileName uses app name and version', () async {
    expect(
      await buildUpdater().generateDownloadFileName(Version.parse("v1.2.3")),
      "App-1.2.3-linux-x86-64.AppImage",
    );
  });

  test('install replaces the AppImage with an executable copy', () async {
    await buildUpdater().install(download);

    expect(await appImage.readAsString(), "new");
    expect((await appImage.stat()).mode & 0x49, 0x49);
    expect(await File("${appImage.path}.new").exists(), isFalse);
    expect(await download.exists(), isTrue);
  });

  test('install keeps the old AppImage if the download is missing', () async {
    await download.delete();

    await expectLater(
      buildUpdater().install(download),
      throwsA(isA<FileSystemException>()),
    );

    expect(await appImage.readAsString(), "old");
    expect(await File("${appImage.path}.new").exists(), isFalse);
  });

  test(
    'install keeps the old AppImage if its directory is read-only',
    () async {
      await Process.run("chmod", ["a-w", dir.path]);

      await expectLater(
        buildUpdater().install(download),
        throwsA(isA<FileSystemException>()),
      );

      expect(await appImage.readAsString(), "old");
    },
  );

  test('install can be retried after a failure', () async {
    final content = await download.readAsBytes();
    await download.delete();
    await expectLater(buildUpdater().install(download), throwsA(anything));

    await download.writeAsBytes(content);
    await buildUpdater().install(download);

    expect(await appImage.readAsString(), "new");
  });
}
