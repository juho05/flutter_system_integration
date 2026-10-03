import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_system_integration/src/appimage/appimage_repository.dart';
import 'package:flutter_system_integration/src/auto_update/updaters/updater.dart';
import 'package:flutter_system_integration/src/auto_update/updaters/updater_android.dart';
import 'package:flutter_system_integration/src/auto_update/updaters/updater_linux_appimage.dart';
import 'package:flutter_system_integration/src/auto_update/updaters/updater_macos.dart';
import 'package:flutter_system_integration/src/auto_update/updaters/updater_windows.dart';
import 'package:flutter_system_integration/src/config.dart';
import 'package:flutter_system_integration/src/github/github_service.dart';
import 'package:flutter_system_integration/src/log.dart';
import 'package:flutter_system_integration/src/version/version.dart';
import 'package:flutter_system_integration/src/version/version_repository.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';

final _log = createLogger("AutoUpdateRepository");

enum AutoUpdateStatus {
  initial,
  checkingVersion,
  downloading,
  installing,
  success,
  failure,
}

class AutoUpdateRepository extends ChangeNotifier {
  static bool get autoUpdatesSupported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isWindows ||
          Platform.isMacOS ||
          AppImageRepository.isAppImage) &&
      const bool.fromEnvironment("VERSION_CHECK", defaultValue: true);

  final SystemIntegrationConfig _config;
  final VersionRepository _versionRepository;
  final GitHubService _github;
  final http.Client? _http;

  late final Updater _updater;

  AutoUpdateStatus _status = AutoUpdateStatus.initial;
  AutoUpdateStatus get status => _status;

  final BehaviorSubject<double> _downloadProgress = BehaviorSubject.seeded(0);
  ValueStream<double> get downloadProgress => _downloadProgress.stream;

  /// [beforeExit] is called on Windows and macOS right before the app exits
  /// to let the installer run. Use it to release resources that must not be
  /// alive when the process exits, e.g. a tray icon. It does not have to exit
  /// the app itself, the app exits once it completes, throws or takes longer
  /// than a few seconds.
  AutoUpdateRepository({
    required this._config,
    required this._versionRepository,
    required this._github,
    http.Client? httpClient,
    Future<void> Function()? beforeExit,
  }) : _http = httpClient {
    final appName = _config.appName;
    if (Platform.isAndroid) {
      _log.fine("update platform: Android");
      _updater = UpdaterAndroid(appName: appName);
    } else if (Platform.isWindows) {
      _log.fine("update platform: Windows");
      _updater = UpdaterWindows(appName: appName, beforeExit: beforeExit);
    } else if (Platform.isMacOS) {
      _log.fine("update platform: macOS");
      _updater = UpdaterMacOS(appName: appName, beforeExit: beforeExit);
    } else if (AppImageRepository.isAppImage) {
      _log.fine("update platform: Linux (AppImage)");
      _updater = UpdaterLinuxAppImage(appName: appName);
    } else {
      throw UnsupportedError("auto updates are not supported on this platform");
    }
  }

  /// Whether the user has to grant a permission before an update can be
  /// installed. Currently only the case on Android.
  Future<bool> needsInstallPermission() => _updater.needsInstallPermission();

  /// Asks the user to grant the install permission, on Android by opening the
  /// system settings. Returns whether it was granted.
  Future<bool> requestInstallPermission() =>
      _updater.requestInstallPermission();

  /// Downloads and installs the latest version.
  ///
  /// Errors are logged and reflected in [status] instead of being thrown.
  /// On Windows and macOS the app exits to let the installer run.
  Future<void> update() async {
    if (status != AutoUpdateStatus.initial &&
        status != AutoUpdateStatus.failure) {
      _log.warning("Cannot start auto update when it's already running.");
      return;
    }

    _log.info("Performing auto update...");
    _setStatus(AutoUpdateStatus.checkingVersion);

    try {
      final latestVersionTag = await _versionRepository.getLatestVersionTag(
        force: true,
      );
      if (latestVersionTag == null ||
          await VersionRepository.getCurrentVersion() >=
              Version.parse(latestVersionTag)) {
        _setStatus(AutoUpdateStatus.initial);
        return;
      }

      final file = await _download(latestVersionTag);

      _log.fine("Installing ${file.path}...");
      _setStatus(AutoUpdateStatus.installing);
      try {
        await _updater.install(file);
      } finally {
        if (await file.exists()) {
          _log.fine("Removing installer file ${file.path}...");
          await file.delete();
        }
      }

      _log.info("Auto update successful!");
      _setStatus(AutoUpdateStatus.success);
    } on UpdateCancelledException {
      _log.info("Auto update cancelled by user");
      _setStatus(AutoUpdateStatus.initial);
    } on Exception catch (e, st) {
      _log.severe("Auto update failed", e, st);
      _setStatus(AutoUpdateStatus.failure);
    }
  }

  void _setStatus(AutoUpdateStatus status) {
    _status = status;
    notifyListeners();
  }

  Future<File> _download(String tag) async {
    final fileName = await _updater.generateDownloadFileName(
      Version.parse(tag),
    );
    final uri = _github.generateReleaseDownloadLink(
      owner: _config.githubOwner,
      repo: _config.githubRepo,
      tag: tag,
      fileName: fileName,
    );

    _log.fine("Downloading $uri...");
    _downloadProgress.add(0);
    _setStatus(AutoUpdateStatus.downloading);

    final targetDir = Directory(
      path.join(
        (await _downloadParentDirectory()).absolute.path,
        "auto_update_downloads",
      ),
    );
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    final outputFile = File(path.join(targetDir.path, fileName)).absolute;
    final userAgent = await _github.userAgent;

    if (_http != null) {
      await _downloadFile(
        _http,
        uri,
        userAgent,
        outputFile.path,
        _downloadProgress.add,
      );
      return outputFile;
    }

    // The event loop of the main isolate is tied to the platform thread which
    // limits the throughput of the response stream.
    final progress = ReceivePort();
    progress.listen((p) => _downloadProgress.add(p as double));
    try {
      await Isolate.run(
        _downloadTask(uri, userAgent, outputFile.path, progress.sendPort),
      );
    } finally {
      progress.close();
    }
    return outputFile;
  }

  /// /tmp is shared between all users on Linux, a directory left behind there
  /// by one user could not be replaced by another.
  Future<Directory> _downloadParentDirectory() => Platform.isLinux
      ? getApplicationCacheDirectory()
      : getTemporaryDirectory();

  @override
  void dispose() {
    _downloadProgress.close();
    super.dispose();
  }
}

Future<void> Function() _downloadTask(
  Uri uri,
  String userAgent,
  String outputPath,
  SendPort progress,
) => () async {
  final client = http.Client();
  try {
    await _downloadFile(client, uri, userAgent, outputPath, progress.send);
  } finally {
    client.close();
  }
};

Future<void> _downloadFile(
  http.Client client,
  Uri uri,
  String userAgent,
  String outputPath,
  void Function(double progress) onProgress,
) async {
  final request = http.Request("GET", uri)..headers["User-Agent"] = userAgent;
  final response = await client.send(request);
  if (response.statusCode != 200) {
    await response.stream.drain<void>();
    throw GitHubUnexpectedStatusCode(response.statusCode);
  }

  final totalBytes = response.contentLength;
  final outputFile = File(outputPath);
  final sink = outputFile.openWrite();
  try {
    int downloadedBytes = 0;
    int lastPercent = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      downloadedBytes += chunk.length;
      if (totalBytes != null && totalBytes > 0) {
        final percent = downloadedBytes * 100 ~/ totalBytes;
        if (percent != lastPercent) {
          lastPercent = percent;
          onProgress(downloadedBytes / totalBytes);
        }
      }
    }
    await sink.close();
  } catch (_) {
    await sink.close();
    if (await outputFile.exists()) await outputFile.delete();
    rethrow;
  }
}
