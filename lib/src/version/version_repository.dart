import 'package:flutter_system_integration/src/config.dart';
import 'package:flutter_system_integration/src/github/github_service.dart';
import 'package:flutter_system_integration/src/key_value_store.dart';
import 'package:flutter_system_integration/src/log.dart';
import 'package:flutter_system_integration/src/version/version.dart';
import 'package:package_info_plus/package_info_plus.dart';

final _log = createLogger("VersionRepository");

class VersionRepository {
  static const _keyLastCheck = "version.last_check";
  static const _keyLatestVersionTag = "version.latest.tag";
  static const _keyLegacyLatestVersion = "version.latest";
  static const _minCheckInterval = Duration(hours: 3);

  static Version? _currentVersion;

  static Future<Version> getCurrentVersion() async {
    return _currentVersion ??= Version.parse(
      (await PackageInfo.fromPlatform()).version,
    );
  }

  final SystemIntegrationConfig _config;
  final GitHubService _github;
  final KeyValueStore _keyValue;

  VersionRepository({
    required this._config,
    required this._github,
    required this._keyValue,
  });

  Future<Version?> getLatestVersion({bool force = false}) async {
    final tag = await getLatestVersionTag(force: force);
    if (tag == null) {
      return null;
    }
    return Version.parse(tag);
  }

  Future<String?> getLatestVersionTag({bool force = false}) async {
    _log.finest("fetching latest version tag (force refresh: $force)");
    if (!force) {
      final lastCheck = await _keyValue.loadDateTime(_keyLastCheck);
      if (lastCheck != null &&
          DateTime.now().difference(lastCheck) < _minCheckInterval) {
        final latest = await _keyValue.loadString(_keyLatestVersionTag);
        if (latest != null) {
          _log.finest("returning cached version: $latest");
          return latest;
        }
        if (await _keyValue.loadString(_keyLegacyLatestVersion) == null) {
          _log.finest("no cached version available, returning null");
          return null;
        }
        await _keyValue.remove(_keyLegacyLatestVersion);
      }
    }

    _log.finest("fetching latest version tag from GitHub...");
    final tags =
        await _github.getRepositoryTagNames(
          owner: _config.githubOwner,
          repo: _config.githubRepo,
          pageSize: 30,
        ) ??
        [];
    (String, Version)? latest;
    for (final t in tags) {
      try {
        final v = Version.parse(t);
        if (!v.isFullVersion) continue;
        if (latest == null || v > latest.$2) latest = (t, v);
      } on InvalidVersion {
        continue;
      }
    }
    _log.fine("Fetched latest version: $latest");

    await _keyValue.store(_keyLastCheck, DateTime.now());
    if (latest != null) {
      _log.finest("storing latest version tag: ${latest.$1}");
      await _keyValue.store(_keyLatestVersionTag, latest.$1);
    } else {
      _log.finest("clearing latest version tag");
      await _keyValue.remove(_keyLatestVersionTag);
    }

    return latest?.$1;
  }
}
