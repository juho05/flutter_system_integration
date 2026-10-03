/// Version checking, auto updates and AppImage desktop integration for
/// Flutter apps distributed via GitHub releases.
library;

export 'src/appimage/appimage_repository.dart';
export 'src/appimage/appimage_settings_viewmodel.dart';
export 'src/appimage/integrate_appimage_viewmodel.dart';
export 'src/auto_update/auto_update_repository.dart';
export 'src/auto_update/install_update_viewmodel.dart';
export 'src/auto_update/updaters/updater.dart'
    show NonZeroExitException, UpdateCancelledException;
export 'src/auto_update/updaters/updater_android.dart'
    show AndroidUpdateFailedException;
export 'src/auto_update/updaters/updater_macos.dart'
    show MacOSUpdateFailedException;
export 'src/config.dart';
export 'src/github/github_service.dart';
export 'src/key_value_store.dart';
export 'src/log.dart' show systemIntegrationLoggerName;
export 'src/restart.dart';
export 'src/ui/appimage_settings_page.dart';
export 'src/ui/common.dart' show ShowMessageCallback, showSnackBarMessage;
export 'src/ui/install_update_page.dart';
export 'src/ui/version_checking_settings_page.dart';
export 'src/version/version.dart';
export 'src/version/version_repository.dart';
export 'src/version_checking/version_checker_viewmodel.dart';
export 'src/version_checking/version_checking_settings.dart';
export 'src/version_checking/version_checking_viewmodel.dart';
