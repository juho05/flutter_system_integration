import 'package:flutter/foundation.dart';
import 'package:flutter_system_integration/src/log.dart';
import 'package:flutter_system_integration/src/upgrade_messages/upgrade_message.dart';
import 'package:flutter_system_integration/src/upgrade_messages/upgrade_messages_repository.dart';

final _log = createLogger("UpgradeMessagesViewModel");

class UpgradeMessagesViewModel extends ChangeNotifier {
  final UpgradeMessagesRepository _repository;

  bool _checked = false;

  List<UpgradeMessage> _messages = const [];

  /// oldest first
  List<UpgradeMessage> get messages => _messages;

  UpgradeMessagesViewModel({required this._repository});

  Future<void> check() async {
    if (_checked) return;
    _checked = true;
    try {
      final messages = await _repository.getStartupMessages();
      if (messages.isEmpty) return;
      _messages = messages;
      notifyListeners();
    } on Object catch (e, st) {
      _log.severe("Failed to load upgrade messages", e, st);
    }
  }

  void acknowledge() {
    if (_messages.isEmpty) return;
    _messages = const [];
    notifyListeners();
  }
}
