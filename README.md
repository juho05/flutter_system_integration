# flutter_system_integration

Version checking, auto updates and AppImage desktop integration for Flutter apps distributed via GitHub releases.

## Features

- **Version checking**: fetches the latest full release tag from GitHub (cached for 3 hours), remembers ignored versions and detects successful updates.
- **Auto updates** on Android (APK), Windows (Inno Setup installer), macOS (DMG) and Linux (AppImage), including a ready-made `InstallUpdatePage` that shows the download progress.
- **AppImage integration**: moves the AppImage to `~/.local/bin/<executableName>` and creates a `.desktop` file so the app appears in launchers and gets a window icon on Wayland.
- **Settings pages**: `VersionCheckingSettingsPage` and `AppImageSettingsPage`. They are built purely on the public API, so you can write your own pages with the same view models.

## Release asset names

Auto updates download release assets from the GitHub release of the latest tag. The assets must be named:

| Platform | Asset name                                                           |
|----------|----------------------------------------------------------------------|
| Android  | `<appName>-<version>-android-<arm64v8\|arm32v7\|x64>.apk`            |
| Windows  | `<appName>-<version>-windows-x86-64.exe`                             |
| macOS    | `<appName>-<version>-macOS-universal.dmg` containing `<appName>.app` |
| Linux    | `<appName>-<version>-linux-x86-64.AppImage`                          |

## Android

Auto updates require the app to declare the `REQUEST_INSTALL_PACKAGES` permission in its manifest. The package does not add it, so builds for stores that forbid it can leave it out. If the app is not yet allowed to install apps, `InstallUpdatePage` explains why before opening the "Install unknown apps" settings screen. Custom pages can do the same with `needsInstallPermission()` and `requestInstallPermission()` of `InstallUpdateViewModel`, otherwise the settings screen opens without explanation when installing. Updates are installed with the `PackageInstaller` session API. On MIUI and HyperOS with MIUI optimization enabled, which breaks that API, the APK is opened in the system installer instead.

## macOS

The update replaces the running `<appName>.app` bundle wherever it is installed. If the current user can't replace it, for example a standard user running an app installed by an admin, macOS asks for admin credentials. The app in the DMG must have a valid code signature with the same team identifier as the installed app. Ad-hoc signed apps are only replaced by other ad-hoc signed apps. Updates are refused while the app runs translocated, for example straight from the Downloads folder. The update log is written to `~/Library/Logs/<appName>/update.log`.

## Usage

Define a config:

```dart
const systemIntegrationConfig = SystemIntegrationConfig(
  appName: "MyApp",
  executableName: "myapp",
  envPrefix: "MYAPP",
  githubOwner: "me",
  githubRepo: "myapp",
  desktopId: "org.example.myapp",
  desktopIconAsset: "assets/icon/myapp.png",
  desktopCategories: ["Utility"],
);
```

Implement `KeyValueStore` with your app's persistent storage and create the repositories:

```dart
final github = GitHubService(config: systemIntegrationConfig);
final versionRepository = VersionRepository(
  config: systemIntegrationConfig,
  github: github,
  keyValue: keyValueStore,
);
final versionCheckingSettings = VersionCheckingSettings(
  config: systemIntegrationConfig,
  keyValue: keyValueStore,
);
await versionCheckingSettings.load();

final versionChecker = VersionCheckerViewModel(
  keyValue: keyValueStore,
  versionRepo: versionRepository,
  settings: versionCheckingSettings,
)..check();

if (AppImageRepository.isAppImage) {
  final appImageRepository = AppImageRepository(
    config: systemIntegrationConfig,
    keyValue: keyValueStore,
  );
  final integrateAppImage = IntegrateAppImageViewModel(
    appImageRepository: appImageRepository,
  )..check();
}

if (AutoUpdateRepository.autoUpdatesSupported) {
  final autoUpdateRepository = AutoUpdateRepository(
    config: systemIntegrationConfig,
    versionRepository: versionRepository,
    github: github,
  );
}
```

`VersionCheckerViewModel` and `IntegrateAppImageViewModel` only hold state. Showing the "new version available" and "integrate AppImage?" dialogs is up to the app.

### Disabling

- `--dart-define=VERSION_CHECK=false` disables version checking and auto updates at build time.
- `<envPrefix>_DISABLE_VERSION_CHECK=1` disables version checking at runtime.
- `<envPrefix>_DISABLE_APPIMAGE_INTEGRATION=1` disables the AppImage integration prompt.

### Logging

The package logs with [`package:logging`](https://pub.dev/packages/logging). All logger names start with `systemIntegrationLoggerName`. Forward the records to your logger:

```dart
Logger.root.level = Level.ALL;
Logger.root.onRecord.listen((record) => myLog(record));
```
