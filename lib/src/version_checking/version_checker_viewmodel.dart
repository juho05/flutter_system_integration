import 'package:flutter/foundation.dart';
import 'package:flutter_system_integration/src/key_value_store.dart';
import 'package:flutter_system_integration/src/log.dart';
import 'package:flutter_system_integration/src/version/version.dart';
import 'package:flutter_system_integration/src/version/version_repository.dart';
import 'package:flutter_system_integration/src/version_checking/version_checking_settings.dart';

final _log = createLogger("VersionCheckerViewModel");

/// Checks for a new version on startup at most once per day and detects
/// successful updates.
///
/// The settings switch only disables the check for a new version. Disabling
/// version checking externally disables both.
class VersionCheckerViewModel extends ChangeNotifier {
  static const String _keyLastDisplayedDialog = "version.last_displayed_dialog";
  static const String _keyIgnoreVersion = "version.ignore_version";

  final KeyValueStore _keyValue;
  final VersionRepository _versionRepo;
  final VersionCheckingSettings _settings;

  bool _checked = false;

  Version? _current;
  Version? get current => _current;
  Version? _latest;
  Version? get latest => _latest;
  bool get newVersionAvailable => _current != null && _latest != null;

  bool isOpen = false;
  bool showUpdateSuccessful = false;

  VersionCheckerViewModel({
    required this._keyValue,
    required this._versionRepo,
    required this._settings,
  }) {
    if (_settings.externallyDisabled) {
      _checked = true;
      _log.info("version checking is disabled externally");
    }
  }

  Future<void> check() async {
    if (_checked) return;
    _checked = true;

    _current = await VersionRepository.getCurrentVersion();
    final prevCurrent = await VersionRepository.getPreviousVersion(_keyValue);
    if (prevCurrent != null && _current! > prevCurrent) {
      showUpdateSuccessful = true;
      notifyListeners();
    }

    if (!_settings.enabled) {
      _log.info("version checking is disabled in the settings");
      return;
    }

    final lastDisplayed = await _keyValue.loadDateTime(_keyLastDisplayedDialog);
    if (lastDisplayed != null &&
        DateTime.now().difference(lastDisplayed) < const Duration(days: 1)) {
      return;
    }

    try {
      final latest = await _versionRepo.getLatestVersion();
      if (latest == null) {
        _log.warning("No latest version found");
        return;
      }
      final ignoreVersion = await _keyValue.loadString(_keyIgnoreVersion);
      if (ignoreVersion != null && Version.parse(ignoreVersion) == latest) {
        _log.finest("Ignored latest version: $ignoreVersion");
        return;
      }
      await _keyValue.remove(_keyIgnoreVersion);

      _log.fine("[Version check] latest: $latest; current: $_current");

      if (latest > _current!) {
        _latest = latest;
        notifyListeners();
      }
    } on Exception catch (e, st) {
      _log.severe("Failed to check for new version", e, st);
    }
  }

  Future<void> displayedVersionDialog() async {
    isOpen = false;
    _current = null;
    _latest = null;
    await _keyValue.store(_keyLastDisplayedDialog, DateTime.now());
  }

  Future<void> ignoreVersion() async {
    if (_latest == null) return;
    await _keyValue.store(_keyIgnoreVersion, _latest.toString());
  }
}
