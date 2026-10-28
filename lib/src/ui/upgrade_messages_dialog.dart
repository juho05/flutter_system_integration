import 'package:flutter/widget_previews.dart';
import 'package:flutter_system_integration/src/ui/common.dart';
import 'package:flutter_system_integration/src/upgrade_messages/upgrade_message.dart';
import 'package:flutter_system_integration/src/version/version.dart';
import 'package:material_ui/material_ui.dart';

/// Shows [messages] in one dialog with a heading per version, in the given
/// order.
///
/// With [confirm], the user is asked whether to continue with the update
/// and the result is true if they pressed yes. Otherwise there is a single
/// OK button and the result is true once it was pressed.
Future<bool> showUpgradeMessagesDialog(
  BuildContext context,
  List<UpgradeMessage> messages, {
  bool confirm = false,
}) async {
  final result = await showAdaptiveDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        UpgradeMessagesDialog(messages: messages, confirm: confirm),
  );
  return result == true;
}

class UpgradeMessagesDialog extends StatelessWidget {
  final List<UpgradeMessage> messages;
  final bool confirm;

  const UpgradeMessagesDialog({
    super.key,
    required this.messages,
    this.confirm = false,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: const Text("Important Changes"),
      content: DefaultTextStyle.merge(
        textAlign: TextAlign.start,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: [
              for (final m in messages)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(
                      m.title != null
                          ? "Version ${m.version}: ${m.title}"
                          : "Version ${m.version}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(m.message),
                  ],
                ),
              if (confirm)
                const Text("Do you want to continue with the update?"),
            ],
          ),
        ),
      ),
      actions: [
        if (confirm)
          AdaptiveDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("No"),
          ),
        AdaptiveDialogAction(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm ? "Yes" : "OK"),
        ),
      ],
    );
  }
}

final _previewMessages = [
  UpgradeMessage(
    version: Version.parse("2.0.0"),
    title: "New storage format",
    message:
        "Your data will be migrated on first start. This may take a few minutes.",
  ),
  UpgradeMessage(
    version: Version.parse("2.1.0"),
    message: "The settings page was moved into the main menu.",
  ),
];

final _manyPreviewMessages = [
  for (var i = 0; i < 12; i++)
    UpgradeMessage(
      version: Version.parse("3.$i.0"),
      title: i.isEven ? "Change number ${i + 1}" : null,
      message:
          "This release contains an important change that you should know "
          "about before updating.",
    ),
];

Widget _withPlatform(TargetPlatform platform, Widget child) => Builder(
  builder: (context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: MediaQuery.platformBrightnessOf(context),
      platform: platform,
    ),
    home: child,
  ),
);

@Preview(group: "Upgrade messages", name: "Material")
Widget upgradeMessagesDialogMaterialPreview() => _withPlatform(
  TargetPlatform.android,
  UpgradeMessagesDialog(messages: _previewMessages),
);

@Preview(group: "Upgrade messages", name: "Material, confirm")
Widget upgradeMessagesDialogMaterialConfirmPreview() => _withPlatform(
  TargetPlatform.android,
  UpgradeMessagesDialog(messages: _previewMessages, confirm: true),
);

@Preview(group: "Upgrade messages", name: "Cupertino")
Widget upgradeMessagesDialogCupertinoPreview() => _withPlatform(
  TargetPlatform.iOS,
  UpgradeMessagesDialog(messages: _previewMessages),
);

@Preview(group: "Upgrade messages", name: "Cupertino, confirm")
Widget upgradeMessagesDialogCupertinoConfirmPreview() => _withPlatform(
  TargetPlatform.iOS,
  UpgradeMessagesDialog(messages: _previewMessages, confirm: true),
);

@Preview(
  group: "Upgrade messages",
  name: "Material, many messages",
  size: Size(400, 600),
)
Widget upgradeMessagesDialogMaterialManyPreview() => _withPlatform(
  TargetPlatform.android,
  UpgradeMessagesDialog(messages: _manyPreviewMessages, confirm: true),
);

@Preview(
  group: "Upgrade messages",
  name: "Cupertino, many messages",
  size: Size(400, 600),
)
Widget upgradeMessagesDialogCupertinoManyPreview() => _withPlatform(
  TargetPlatform.iOS,
  UpgradeMessagesDialog(messages: _manyPreviewMessages, confirm: true),
);
