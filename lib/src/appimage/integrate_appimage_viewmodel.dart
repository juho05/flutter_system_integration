import 'package:flutter/foundation.dart';
import 'package:flutter_system_integration/src/appimage/appimage_repository.dart';

class IntegrateAppImageViewModel extends ChangeNotifier {
  final AppImageRepository _repo;

  bool _askToIntegrate = false;
  bool get askToIntegrate => _askToIntegrate;

  IntegrateAppImageViewModel({required AppImageRepository appImageRepository})
    : _repo = appImageRepository;

  Future<void> check() async {
    if (!await _repo.shouldIntegrate()) return;
    _askToIntegrate = true;
    notifyListeners();
  }

  /// Must not notify listeners because it is called during build.
  void shownDialog() {
    _askToIntegrate = false;
  }

  Future<void> disable() async {
    _askToIntegrate = false;
    await _repo.disableIntegration();
  }

  Future<void> integrate() async {
    _askToIntegrate = false;
    await _repo.integrate();
  }
}
