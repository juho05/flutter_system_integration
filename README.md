# flutter_system_integration

Version checking, auto updates and AppImage desktop integration for Flutter apps distributed via GitHub releases.

## Features

- **Version checking**: fetches the latest full release tag from GitHub (cached for 3 hours), remembers ignored versions and detects successful updates.
- **Auto updates** on Android (APK), Windows (Inno Setup installer), macOS (DMG) and Linux (AppImage), including a ready-made `InstallUpdatePage` that shows the download progress.
- **AppImage integration**: moves the AppImage to `~/.local/bin/<executableName>` and creates a `.desktop` file so the app appears in launchers and gets a window icon on Wayland.
- **Upgrade messages**: important notes for users upgrading to a specific version, shown before installing an update and on the first launch after an upgrade.
- **Settings pages**: `VersionCheckingSettingsPage` and `AppImageSettingsPage`. They are built purely on the public API, so you can write your own pages with the same view models.

## Release asset names

Auto updates download release assets from the GitHub release of the latest tag. The assets must be named:

| Platform | Asset name                                                           |
|----------|----------------------------------------------------------------------|
| Android  | `<appName>-<version>-android-<arm64v8\|arm32v7\|x64>.apk`            |
| Windows  | `<appName>-<version>-windows-x86-64.exe`                             |
| macOS    | `<appName>-<version>-macOS-universal.dmg` containing `<appName>.app` |
| Linux    | `<appName>-<version>-linux-x86-64.AppImage`                          |

On Android, the universal `<appName>-<version>-android.apk` containing all ABIs can be added as well. It is downloaded if the device ABI is unknown or the release has no APK for it. If the ABI is unknown and there is no universal APK, the `arm64v8` APK is downloaded.

On macOS, `<appName>-<version>-macOS.dmg` is downloaded if the release has no `-universal` DMG.

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
  // optional, see "Upgrade messages"
  upgradeMessagesAsset: "assets/upgrade_messages.json",
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

// works even if version checking is disabled
final upgradeMessagesRepository = UpgradeMessagesRepository(
  config: systemIntegrationConfig,
  keyValue: keyValueStore,
  // leave out in builds that must not contact external servers
  github: AutoUpdateRepository.autoUpdatesSupported(systemIntegrationConfig)
      ? github
      : null,
);
final upgradeMessages = UpgradeMessagesViewModel(
  repository: upgradeMessagesRepository,
)..check();

if (AutoUpdateRepository.autoUpdatesSupported(systemIntegrationConfig)) {
  final autoUpdateRepository = AutoUpdateRepository(
    config: systemIntegrationConfig,
    versionRepository: versionRepository,
    github: github,
    upgradeMessagesRepository: upgradeMessagesRepository,
    // optional, called before the app exits to run the installer
    beforeExit: () async => disposeTrayIcon(),
  );
}
```

`VersionCheckerViewModel`, `UpgradeMessagesViewModel` and `IntegrateAppImageViewModel` only hold state. Showing the "new version available", upgrade messages and "integrate AppImage?" dialogs is up to the app.

### Upgrade messages

Messages are defined in a JSON file that is bundled as an asset:

```json
{
  "messages": [
    { "version": "2.0.0", "title": "Optional title", "message": "Your settings were reset." }
  ]
}
```

Add a message to the file before releasing its version and keep the messages of older versions in it. Messages are shown in one dialog with a heading per version, oldest first:

- **Before installing**: `InstallUpdatePage` fetches the file from the repository at the tag of the new version and asks the user whether to continue if it contains messages for versions after the running one. The file is read from `upgradeMessagesRepoPath`, which defaults to `upgradeMessagesAsset`.
- **On startup**: `UpgradeMessagesViewModel.messages` contains the messages of the versions after the previous launch up to the running one that were not confirmed before installing. Only the bundled asset is read. Show them with `showUpgradeMessagesDialog(context, messages)`, which has a single OK button, then call `acknowledge()`. Fresh installs show no messages. Messages are shown at most once per upgrade: the running version is recorded on startup, so they are lost if the app exits before showing them.

If the file fetched before installing is not valid JSON, it is ignored and the update is installed without showing messages. Network errors fail the update. Unknown keys in the file are ignored and invalid entries are skipped, so new fields can be added later without breaking older versions that read the file before installing. Never change the type of an existing field.

Custom install pages call `prepareUpdate()` of `InstallUpdateViewModel`, show `PendingUpdate.messages` with `showUpgradeMessagesDialog(context, messages, confirm: true)`, call `confirmUpgradeMessages()` if the user agreed and then `installUpdate()`.

### Disabling

- `--dart-define=VERSION_CHECK=false` disables version checking and auto updates at build time.
- `<envPrefix>_DISABLE_VERSION_CHECK=1` disables version checking and auto updates at runtime.
- `<envPrefix>_DISABLE_APPIMAGE_INTEGRATION=1` disables the AppImage integration prompt.

### Testing against a fake GitHub

`<envPrefix>_GITHUB_API_URL` and `<envPrefix>_GITHUB_WEB_URL` replace `https://api.github.com` and `https://github.com`, so version checks and update downloads can be served by a local server. On Android, set the system properties `debug.<envprefix>.github_api_url` and `debug.<envprefix>.github_web_url` (lowercase prefix) with `adb shell setprop` instead and restart the app.

### Logging

The package logs with [`package:logging`](https://pub.dev/packages/logging). All logger names start with `systemIntegrationLoggerName`. Forward the records to your logger:

```dart
Logger.root.level = Level.ALL;
Logger.root.onRecord.listen((record) => myLog(record));
```
