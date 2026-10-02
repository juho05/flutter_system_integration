import 'dart:io';

import 'package:flutter_system_integration/src/auto_update/auto_update_repository.dart';
import 'package:flutter_system_integration/src/auto_update/install_update_viewmodel.dart';
import 'package:flutter_system_integration/src/restart.dart';
import 'package:material_ui/material_ui.dart';

/// Downloads and installs the latest version and shows the progress.
class InstallUpdatePage extends StatefulWidget {
  /// Must not be null if [AutoUpdateRepository.autoUpdatesSupported] is true.
  final AutoUpdateRepository? autoUpdateRepository;

  /// Called when the user wants to exit after a successful update on
  /// platforms that do not support restarting. Defaults to `exit(0)`.
  final VoidCallback? onExit;

  const InstallUpdatePage({
    super.key,
    required this.autoUpdateRepository,
    this.onExit,
  });

  @override
  State<InstallUpdatePage> createState() => _InstallUpdatePageState();
}

class _InstallUpdatePageState extends State<InstallUpdatePage> {
  InstallUpdateViewModel? _viewModel;

  @override
  void initState() {
    super.initState();
    if (AutoUpdateRepository.autoUpdatesSupported) {
      _viewModel = InstallUpdateViewModel(
        autoUpdateRepository: widget.autoUpdateRepository!,
      );
    }
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = _viewModel;
    return Scaffold(
      appBar: AppBar(title: const Text("Install Update")),
      body: SafeArea(
        child: viewModel == null
            ? const Center(
                child: Text(
                  "Auto updates are not supported on this platform/build.",
                ),
              )
            : ListenableBuilder(
                listenable: viewModel,
                builder: (context, _) => _buildContent(context, viewModel),
              ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, InstallUpdateViewModel viewModel) {
    final status = viewModel.status;
    final running =
        status == AutoUpdateStatus.checkingVersion ||
        status == AutoUpdateStatus.downloading ||
        status == AutoUpdateStatus.installing;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          switch (status) {
            AutoUpdateStatus.initial => const Icon(
              Icons.arrow_circle_down,
              size: 64,
            ),
            AutoUpdateStatus.checkingVersion ||
            AutoUpdateStatus.installing => const SizedBox.square(
              dimension: 64,
              child: CircularProgressIndicator.adaptive(),
            ),
            AutoUpdateStatus.downloading => _DownloadProgress(
              progress: viewModel.downloadProgress,
            ),
            AutoUpdateStatus.success => const Icon(
              Icons.check_circle_outline,
              size: 64,
            ),
            AutoUpdateStatus.failure => const Icon(
              Icons.error_outline,
              size: 64,
            ),
          },
          Text(switch (status) {
            AutoUpdateStatus.initial =>
              "Click the button below to install the latest version.",
            AutoUpdateStatus.checkingVersion => "Checking version...",
            AutoUpdateStatus.downloading => "Downloading...",
            AutoUpdateStatus.installing => "Installing...",
            AutoUpdateStatus.success => "Update successful!",
            AutoUpdateStatus.failure => "Update failed!",
          }, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (status == AutoUpdateStatus.initial ||
              status == AutoUpdateStatus.failure)
            FilledButton(
              onPressed: viewModel.installUpdate,
              child: Text(
                status == AutoUpdateStatus.failure ? "Retry" : "Install",
              ),
            ),
          if (running)
            const FilledButton(onPressed: null, child: Text("Installing...")),
          if (status == AutoUpdateStatus.success)
            FilledButton(
              onPressed: () {
                if (Restart.supported) {
                  Restart.restart();
                } else if (widget.onExit != null) {
                  widget.onExit!();
                } else {
                  exit(0);
                }
              },
              child: Text(Restart.supported ? "Restart" : "Exit"),
            ),
        ],
      ),
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  final Stream<double> progress;

  const _DownloadProgress({required this.progress});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: progress,
      builder: (context, snapshot) {
        final progress = snapshot.data;
        return SizedBox.square(
          dimension: 64,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(value: progress),
              if (progress != null)
                Center(
                  child: Text(
                    "${(progress * 100).round()} %",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
