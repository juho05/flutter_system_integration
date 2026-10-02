import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_system_integration/src/ui/common.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

final _log = Logger("$systemIntegrationLoggerName.AppImageSettingsPage");

class AppImageSettingsPage extends StatefulWidget {
  final SystemIntegrationConfig config;
  final AppImageRepository appImageRepository;

  /// Defaults to [showSnackBarMessage].
  final ShowMessageCallback showMessage;

  const AppImageSettingsPage({
    super.key,
    required this.config,
    required this.appImageRepository,
    this.showMessage = showSnackBarMessage,
  });

  @override
  State<AppImageSettingsPage> createState() => _AppImageSettingsPageState();
}

class _AppImageSettingsPageState extends State<AppImageSettingsPage> {
  late final AppImageSettingsViewModel _viewModel = AppImageSettingsViewModel(
    appImageRepository: widget.appImageRepository,
  );

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _integrate() async {
    try {
      await _viewModel.integrate();
    } on Exception catch (e, st) {
      _log.severe("Failed to integrate AppImage", e, st);
      if (!mounted) return;
      widget.showMessage(context, "Failed to integrate AppImage!");
      return;
    }
    Restart.restart();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium!;
    final config = widget.config;
    return Scaffold(
      appBar: AppBar(title: const Text("AppImage Integration")),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            final integrated = _viewModel.integrated;
            return ListView(
              padding: const EdgeInsets.all(8),
              children: [
                Row(
                  children: [
                    const Text("Integrated: "),
                    Text(
                      integrated == null
                          ? "checking..."
                          : (integrated ? "YES" : "NO"),
                      style: integrated != null
                          ? textStyle.copyWith(
                              color: integrated ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                            )
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: (integrated ?? false)
                      ? OutlinedButton.icon(
                          onPressed: _integrate,
                          icon: const Icon(Icons.install_desktop),
                          label: const Text("Re-Integrate"),
                        )
                      : FilledButton.icon(
                          onPressed: integrated != null ? _integrate : null,
                          icon: const Icon(Icons.install_desktop),
                          label: const Text("Integrate"),
                        ),
                ),
                const SizedBox(height: 32),
                InfoText(
                  "Integrating the ${config.appName} AppImage will move it to ~/.local/bin/${config.executableName} "
                  "and create a .desktop file to make it appear in app launchers and to give it a window icon on Wayland.",
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
