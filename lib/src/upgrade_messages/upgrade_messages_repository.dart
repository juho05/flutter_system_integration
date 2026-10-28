import 'package:flutter/services.dart';
import 'package:flutter_system_integration/src/config.dart';
import 'package:flutter_system_integration/src/github/github_service.dart';
import 'package:flutter_system_integration/src/key_value_store.dart';
import 'package:flutter_system_integration/src/log.dart';
import 'package:flutter_system_integration/src/upgrade_messages/upgrade_message.dart';
import 'package:flutter_system_integration/src/version/version.dart';
import 'package:flutter_system_integration/src/version/version_repository.dart';

final _log = createLogger("UpgradeMessagesRepository");

/// Loads upgrade messages and remembers which ones were shown.
///
/// Messages are shown before installing an update with `InstallUpdatePage`
/// and on the first launch after an upgrade, unless they were already shown
/// before installing. Fresh installs show no messages.
class UpgradeMessagesRepository {
  static const _keyShown = "upgrade_messages.shown";

  final SystemIntegrationConfig _config;
  final KeyValueStore _keyValue;
  final GitHubService? _github;
  final AssetBundle _bundle;

  /// [github] is only needed to fetch the messages before installing an
  /// update. Builds without auto updates can leave it out.
  UpgradeMessagesRepository({
    required this._config,
    required this._keyValue,
    this._github,
    AssetBundle? bundle,
  }) : _bundle = bundle ?? rootBundle;

  /// oldest first
  Future<List<UpgradeMessage>> getStartupMessages() async {
    final asset = _config.upgradeMessagesAsset;
    if (asset == null) return [];

    final previous = await VersionRepository.getPreviousVersion(_keyValue);
    final current = await VersionRepository.getCurrentVersion();
    final shown = await _loadShown();
    if (shown.any((v) => v <= current)) {
      await _storeShown(shown.where((v) => v > current));
    }
    if (previous == null || previous >= current) return [];

    final List<UpgradeMessage> messages;
    try {
      messages = UpgradeMessage.parseFile(await _bundle.loadString(asset));
    } on Object catch (e, st) {
      // a missing asset throws a FlutterError
      _log.severe("Failed to load bundled upgrade messages", e, st);
      return [];
    }
    return _filter(messages, from: previous, to: current, shown: shown);
  }

  /// Fetches the messages of the versions after the current one up to the
  /// version of [tag] that were not shown yet, oldest first.
  ///
  /// The file is read from the repository at [tag]. A missing or invalid
  /// file means there are no messages, other errors are thrown.
  Future<List<UpgradeMessage>> fetchMessagesForUpdate(String tag) async {
    final repoPath = _config.upgradeMessagesRepoPath;
    if (repoPath == null) return [];
    if (_github == null || _config.versionCheckExternallyDisabled) {
      throw StateError("fetching upgrade messages is not allowed");
    }

    final String content;
    try {
      content = await _github.getRepositoryFileContent(
        owner: _config.githubOwner,
        repo: _config.githubRepo,
        path: repoPath,
        ref: tag,
      );
    } on GitHubUnexpectedStatusCode catch (e) {
      if (e.status != 404) rethrow;
      _log.fine("no upgrade messages file at $tag");
      return [];
    }
    final List<UpgradeMessage> messages;
    try {
      messages = UpgradeMessage.parseFile(content);
    } on FormatException catch (e, st) {
      _log.severe("Invalid upgrade messages file at $tag", e, st);
      return [];
    }
    return _filter(
      messages,
      from: await VersionRepository.getCurrentVersion(),
      to: Version.parse(tag),
      shown: await _loadShown(),
    );
  }

  Future<void> markShown(Iterable<UpgradeMessage> messages) async {
    if (messages.isEmpty) return;
    final current = await VersionRepository.getCurrentVersion();
    final shown = await _loadShown();
    shown.addAll(messages.map((m) => m.version));
    await _storeShown(shown.where((v) => v > current));
  }

  List<UpgradeMessage> _filter(
    List<UpgradeMessage> messages, {
    required Version from,
    required Version to,
    required Set<Version> shown,
  }) =>
      messages
          .where(
            (m) =>
                m.version > from &&
                m.version <= to &&
                !shown.contains(m.version),
          )
          .toList()
        ..sort((a, b) => a.version.compareTo(b.version));

  Future<Set<Version>> _loadShown() async {
    final shown = await _keyValue.loadObject(
      _keyShown,
      _ShownVersions.fromJson,
    );
    return {...?shown?.versions};
  }

  Future<void> _storeShown(Iterable<Version> versions) =>
      _keyValue.store(_keyShown, _ShownVersions(versions.toList()));
}

class _ShownVersions {
  final List<Version> versions;

  const _ShownVersions(this.versions);

  factory _ShownVersions.fromJson(Map<String, dynamic> json) => _ShownVersions([
    for (final v in json["versions"] as List<dynamic>? ?? [])
      Version.fromJson(v as Map<String, dynamic>),
  ]);

  Map<String, dynamic> toJson() => {
    "versions": [for (final v in versions) v.toJson()],
  };
}
