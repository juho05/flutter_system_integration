import 'package:flutter/foundation.dart';
import 'package:flutter_system_integration/src/auto_update/auto_update_repository.dart';
import 'package:rxdart/rxdart.dart';

/// View model of an install update page.
class InstallUpdateViewModel extends ChangeNotifier {
  final AutoUpdateRepository _repo;

  AutoUpdateStatus get status => _repo.status;
  ValueStream<double> get downloadProgress => _repo.downloadProgress;

  InstallUpdateViewModel({required AutoUpdateRepository autoUpdateRepository})
    : _repo = autoUpdateRepository {
    _repo.addListener(notifyListeners);
  }

  Future<bool> needsInstallPermission() => _repo.needsInstallPermission();

  Future<bool> requestInstallPermission() => _repo.requestInstallPermission();

  Future<void> installUpdate() async {
    await _repo.update();
  }

  @override
  void dispose() {
    _repo.removeListener(notifyListeners);
    super.dispose();
  }
}
