import 'dart:io';

import 'package:flutter_system_integration/src/appimage/appimage_repository.dart';
import 'package:flutter_system_integration/src/appimage/replace_file.dart';
import 'package:flutter_system_integration/src/auto_update/updaters/updater.dart';
import 'package:flutter_system_integration/src/version/version.dart';

class UpdaterLinuxAppImage extends Updater {
  final String _appName;
  final File? _appImageFile;

  UpdaterLinuxAppImage({required this._appName, this._appImageFile});

  @override
  Future<String> generateDownloadFileName(Version version) async =>
      "$_appName-$version-linux-x86-64.AppImage";

  @override
  Future<void> install(File downloadedFile) async {
    final appImageFile = _appImageFile ?? AppImageRepository.appImageFile;
    await replaceWithExecutableCopy(downloadedFile, appImageFile.path);
  }
}
