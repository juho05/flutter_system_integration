import 'dart:io';

import 'package:flutter_system_integration/src/appimage/appimage_repository.dart';
import 'package:flutter_system_integration/src/auto_update/updaters/updater.dart';
import 'package:flutter_system_integration/src/log.dart';
import 'package:flutter_system_integration/src/version/version.dart';

final _log = createLogger("UpdaterLinuxAppImage");

class UpdaterLinuxAppImage extends Updater {
  final String _appName;

  UpdaterLinuxAppImage({required this._appName});

  @override
  Future<String> generateDownloadFileName(Version version) async =>
      "$_appName-$version-linux-x86-64.AppImage";

  @override
  Future<void> install(File downloadedFile) async {
    final appImageFile = AppImageRepository.appImageFile;
    // delete existing file first to prevent "Text file busy" error
    await appImageFile.delete();
    await downloadedFile.copy(appImageFile.path);

    try {
      await Process.run("chmod", ["+x", appImageFile.path], runInShell: true);
    } on Exception catch (e, st) {
      _log.severe("Failed to make updated AppImage executable", e, st);
    }
  }
}
