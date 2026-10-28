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

  /// Returns null if there is no newer version or preparing failed.
  Future<PendingUpdate?> prepareUpdate() => _repo.prepareUpdate();

  /// Call when the user confirmed the messages of [pending].
  Future<void> confirmUpgradeMessages(PendingUpdate pending) =>
      _repo.markUpgradeMessagesShown(pending);

  Future<void> installUpdate(PendingUpdate pending) => _repo.update(pending);

  @override
  void dispose() {
    _repo.removeListener(notifyListeners);
    super.dispose();
  }
}
