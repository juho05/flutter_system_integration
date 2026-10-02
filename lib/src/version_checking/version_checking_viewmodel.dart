import 'package:flutter/foundation.dart';
import 'package:flutter_system_integration/src/version/version.dart';
import 'package:flutter_system_integration/src/version/version_repository.dart';
import 'package:flutter_system_integration/src/version_checking/version_checking_settings.dart';

class VersionCheckingViewModel extends ChangeNotifier {
  final VersionCheckingSettings _settings;
  final VersionRepository _repository;

  bool _enabled = true;
  bool get enabled => _enabled;

  bool _checking = false;
  bool get checking => _checking;

  VersionCheckingViewModel({
    required this._settings,
    required this._repository,
  }) {
    _settings.addListener(_onSettingsChanged);
    _onSettingsChanged();
  }

  void _onSettingsChanged() {
    _enabled = _settings.enabled;
    notifyListeners();
  }

  void updateEnabled(bool enabled) {
    _settings.enabled = enabled;
  }

  Future<({Version current, Version? latest})> check() async {
    _checking = true;
    notifyListeners();
    try {
      final current = await VersionRepository.getCurrentVersion();
      final latest = await _repository.getLatestVersion(force: true);
      return (current: current, latest: latest);
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
