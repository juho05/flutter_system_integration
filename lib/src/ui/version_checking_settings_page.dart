import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_system_integration/src/ui/common.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

final _log = Logger("$systemIntegrationLoggerName.VersionCheckingSettingsPage");

enum _NewVersionDialogChoice { close, view, install }

class VersionCheckingSettingsPage extends StatefulWidget {
  final SystemIntegrationConfig config;
  final VersionCheckingSettings settings;
  final VersionRepository versionRepository;

  /// Navigates to the install update page, e.g. [InstallUpdatePage].
  ///
  /// The install option is hidden if this is null.
  final void Function(BuildContext context)? onInstallUpdate;

  /// Defaults to [showSnackBarMessage].
  final ShowMessageCallback showMessage;

  const VersionCheckingSettingsPage({
    super.key,
    required this.config,
    required this.settings,
    required this.versionRepository,
    this.onInstallUpdate,
    this.showMessage = showSnackBarMessage,
  });

  @override
  State<VersionCheckingSettingsPage> createState() =>
      _VersionCheckingSettingsPageState();
}

class _VersionCheckingSettingsPageState
    extends State<VersionCheckingSettingsPage> {
  late final VersionCheckingViewModel _viewModel = VersionCheckingViewModel(
    settings: widget.settings,
    repository: widget.versionRepository,
  );

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _checkNow() async {
    final ({Version current, Version? latest}) result;
    try {
      result = await _viewModel.check();
    } on Exception catch (e, st) {
      _log.severe("Failed to fetch latest version", e, st);
      if (!mounted) return;
      widget.showMessage(context, "Failed to fetch latest version!");
      return;
    }
    if (!mounted) return;
    final (:current, :latest) = result;
    if (latest == null) return;
    if (latest <= current) {
      widget.showMessage(
        context,
        "You are already running the latest version: v$current!",
      );
      return;
    }

    final onInstallUpdate = widget.onInstallUpdate;
    final choice = await showAdaptiveDialog<_NewVersionDialogChoice>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog.adaptive(
        title: const Text("New version available"),
        content: Text("Current: v$current\nLatest: v$latest"),
        actions: [
          AdaptiveDialogAction(
            onPressed: () =>
                Navigator.pop(context, _NewVersionDialogChoice.view),
            child: const Text("View"),
          ),
          if (AutoUpdateRepository.autoUpdatesSupported &&
              onInstallUpdate != null)
            AdaptiveDialogAction(
              onPressed: () =>
                  Navigator.pop(context, _NewVersionDialogChoice.install),
              child: const Text("Install"),
            ),
          AdaptiveDialogAction(
            onPressed: () =>
                Navigator.pop(context, _NewVersionDialogChoice.close),
            child: const Text("Close"),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _NewVersionDialogChoice.close || null:
        break;
      case _NewVersionDialogChoice.view:
        launchUrl(widget.config.releasesUrl);
      case _NewVersionDialogChoice.install:
        onInstallUpdate?.call(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Version Checking")),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            final checkNowLabel = Text(
              _viewModel.checking ? "Checking..." : "Check now",
            );
            return ListView(
              padding: const EdgeInsets.all(8),
              children: [
                SwitchListTile(
                  onChanged: _viewModel.updateEnabled,
                  value: _viewModel.enabled,
                  title: const Text("Check for new versions"),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Theme.of(context).brightness == Brightness.dark
                      ? FilledButton.tonalIcon(
                          onPressed: _viewModel.checking ? null : _checkNow,
                          icon: const Icon(Icons.update),
                          label: checkNowLabel,
                        )
                      : FilledButton.icon(
                          onPressed: _viewModel.checking ? null : _checkNow,
                          icon: const Icon(Icons.update),
                          label: checkNowLabel,
                        ),
                ),
                const SizedBox(height: 32),
                InfoText(
                  "Enabling version checking will periodically contact the GitHub API to check for new versions of "
                  "${widget.config.appName} and display a dialog on startup if a new version is found.",
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
