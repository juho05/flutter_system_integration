import 'package:flutter/foundation.dart';
import 'package:flutter_system_integration/src/config.dart';
import 'package:flutter_system_integration/src/key_value_store.dart';
import 'package:flutter_system_integration/src/log.dart';

final _log = createLogger("VersionCheckingSettings");

class VersionCheckingSettings extends ChangeNotifier {
  static const String _enabledKey = "version_checking.enabled";

  final SystemIntegrationConfig _config;
  final KeyValueStore _keyValue;

  bool get _enabledDefault => !_config.versionCheckExternallyDisabled;

  late bool _enabled = _enabledDefault;

  bool get enabled => _enabled;

  VersionCheckingSettings({required this._config, required this._keyValue});

  Future<void> load() async {
    _log.finest("loading version checking settings");
    _enabled =
        (await _keyValue.loadBool(_enabledKey) ?? _enabledDefault) &&
        !_config.versionCheckExternallyDisabled;
    notifyListeners();
  }

  void reset() {
    _log.fine("resetting version checking settings");
    _enabled = _enabledDefault;
    notifyListeners();
    _keyValue.remove(_enabledKey);
  }

  set enabled(bool enabled) {
    if (enabled == _enabled || _config.versionCheckExternallyDisabled) return;
    _log.fine("version checking enabled: $enabled");
    _enabled = enabled;
    notifyListeners();
    _keyValue.store(_enabledKey, enabled);
  }
}
