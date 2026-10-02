import 'package:flutter/foundation.dart';
import 'package:flutter_system_integration/src/appimage/appimage_repository.dart';

class AppImageSettingsViewModel extends ChangeNotifier {
  final AppImageRepository _repo;

  bool? _integrated;
  bool? get integrated => _integrated;

  AppImageSettingsViewModel({required AppImageRepository appImageRepository})
    : _repo = appImageRepository {
    _repo.isIntegrated().then((value) {
      _integrated = value;
      notifyListeners();
    });
  }

  Future<void> integrate() async {
    await _repo.integrate();
  }
}
