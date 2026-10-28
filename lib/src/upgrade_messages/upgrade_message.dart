import 'dart:convert';

import 'package:flutter_system_integration/src/log.dart';
import 'package:flutter_system_integration/src/version/version.dart';

final _log = createLogger("UpgradeMessage");

class UpgradeMessage {
  final Version version;
  final String? title;
  final String message;

  const UpgradeMessage({
    required this.version,
    this.title,
    required this.message,
  });

  /// Parses an upgrade messages file:
  ///
  /// ```json
  /// {
  ///   "messages": [
  ///     { "version": "2.0.0", "title": "Optional", "message": "..." }
  ///   ]
  /// }
  /// ```
  /// Throws a [FormatException] if the file is not a JSON object.
  static List<UpgradeMessage> parseFile(String content) {
    if (content.trim().isEmpty) return [];
    final json = jsonDecode(content);
    if (json is! Map<String, dynamic>) {
      throw const FormatException("upgrade messages file is not an object");
    }
    final entries = json["messages"];
    if (entries is! List<dynamic>) return [];
    final messages = <UpgradeMessage>[];
    for (final entry in entries) {
      final message = _tryParse(entry);
      if (message == null) {
        _log.warning("skipping invalid upgrade message: $entry");
        continue;
      }
      messages.add(message);
    }
    return messages;
  }

  static UpgradeMessage? _tryParse(Object? entry) {
    if (entry is! Map<String, dynamic>) return null;
    final version = entry["version"];
    final title = entry["title"];
    final message = entry["message"];
    if (version is! String || message is! String) return null;
    if (title != null && title is! String) return null;
    try {
      return UpgradeMessage(
        version: Version.parse(version),
        title: title as String?,
        message: message,
      );
    } on InvalidVersion {
      return null;
    }
  }

  @override
  String toString() => "UpgradeMessage($version)";
}
