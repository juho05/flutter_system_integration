package de.julianh.flutter_system_integration

import android.app.Activity
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.content.IntentCompat
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.concurrent.Executors

internal class ApkInstaller(private val context: Context) : PluginRegistry.ActivityResultListener {
    companion object {
        private const val REQUEST_CODE_INSTALL_PERMISSION = 0x5f1a
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val statusAction = "${context.packageName}.flutter_system_integration.INSTALL_STATUS"
    private val providerAuthority = "${context.packageName}.flutter_system_integration.apkprovider"
    private val intentApkDir = File(context.cacheDir, "flutter_system_integration_apk")

    private var activityBinding: ActivityPluginBinding? = null
    private val activity: Activity? get() = activityBinding?.activity

    private var permissionResult: MethodChannel.Result? = null

    private var installResult: MethodChannel.Result? = null
    private var installSessionId: Int? = null
    private var statusReceiver: BroadcastReceiver? = null

    init {
        // Leftover of a previous intent based install. Recent files might still be read by the installer.
        executor.execute {
            val threshold = System.currentTimeMillis() - 60 * 60 * 1000
            intentApkDir.listFiles()?.filter { it.lastModified() < threshold }?.forEach { it.delete() }
        }
    }

    fun attachToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    fun detachFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    fun dispose() {
        unregisterStatusReceiver()
        executor.shutdown()
        permissionResult = null
        installResult = null
        installSessionId = null
    }

    fun requestInstallPermission(result: MethodChannel.Result) {
        if (canRequestPackageInstalls()) {
            result.success(true)
            return
        }
        if (permissionResult != null) {
            result.error("ALREADY_RUNNING", "Install permission request is already running", null)
            return
        }
        val activity = activity
            ?: return result.error("NO_ACTIVITY", "Requesting the install permission requires an activity", null)

        val withPackage = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${context.packageName}"),
        )
        permissionResult = result
        try {
            activity.startActivityForResult(withPackage, REQUEST_CODE_INSTALL_PERMISSION)
        } catch (_: ActivityNotFoundException) {
            // Some vendor ROMs only provide the global list of apps.
            try {
                activity.startActivityForResult(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES),
                    REQUEST_CODE_INSTALL_PERMISSION,
                )
            } catch (e: ActivityNotFoundException) {
                permissionResult = null
                result.error("NO_SETTINGS_ACTIVITY", "Cannot open install permission settings: $e", null)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE_INSTALL_PERMISSION) return false
        permissionResult?.success(canRequestPackageInstalls())
        permissionResult = null
        return true
    }

    fun canRequestPackageInstalls(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()

    /** Responds with the used method, `session` or `intent`. */
    fun install(path: String, result: MethodChannel.Result) {
        if (isMiuiWithOptimization()) {
            installWithIntent(path, result)
        } else {
            installWithSession(path, result)
        }
    }

    // MIUI and HyperOS break the PackageInstaller session API while MIUI optimization is enabled,
    // see https://github.com/vvb2060/PackageInstallerTest. Same detection as Droid-ify and Aurora Store.
    private fun isMiuiWithOptimization(): Boolean {
        if (getSystemProperty("ro.miui.ui.version.name").isNullOrEmpty()) return false
        val optimization = getSystemProperty("persist.sys.miui_optimization")
        if (optimization == "0" || optimization == "false") return false
        return try {
            val isXOptMode = Class.forName("android.miui.AppOpsUtils").getDeclaredMethod("isXOptMode")
            // XOptMode means MIUI optimization is disabled.
            isXOptMode.invoke(null) != true
        } catch (_: Exception) {
            true
        }
    }

    private fun getSystemProperty(key: String): String? = try {
        Class.forName("android.os.SystemProperties")
            .getDeclaredMethod("get", String::class.java)
            .invoke(null, key) as String
    } catch (_: Exception) {
        null
    }

    private fun installWithSession(path: String, result: MethodChannel.Result) {
        if (installResult != null) {
            result.error("ALREADY_RUNNING", "An installation is already running", null)
            return
        }
        installResult = result
        registerStatusReceiver()

        executor.execute {
            val packageInstaller = context.packageManager.packageInstaller
            var sessionId: Int? = null
            try {
                val file = File(path)
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                params.setSize(file.length())
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    params.setInstallReason(PackageManager.INSTALL_REASON_USER)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    // HyperOS rejects silent self updates with "Permission denied".
                    params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
                }

                val id = packageInstaller.createSession(params)
                sessionId = id
                mainHandler.post { installSessionId = id }

                packageInstaller.openSession(id).use { session ->
                    file.inputStream().use { input ->
                        session.openWrite("package", 0, file.length()).use { output ->
                            input.copyTo(output, 64 * 1024)
                            session.fsync(output)
                        }
                    }

                    var flags = PendingIntent.FLAG_UPDATE_CURRENT
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        // The installer adds the status extras to the intent.
                        flags = flags or PendingIntent.FLAG_MUTABLE
                    }
                    val pendingIntent = PendingIntent.getBroadcast(
                        context,
                        id,
                        Intent(statusAction).setPackage(context.packageName),
                        flags,
                    )
                    session.commit(pendingIntent.intentSender)
                }
            } catch (e: Exception) {
                sessionId?.let {
                    try {
                        packageInstaller.abandonSession(it)
                    } catch (_: Exception) {
                    }
                }
                mainHandler.post {
                    finishInstall { it.error("INSTALL_FAILED", "Failed to create install session: $e", null) }
                }
            }
        }
    }

    private fun registerStatusReceiver() {
        unregisterStatusReceiver()
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                onInstallStatus(intent)
            }
        }
        ContextCompat.registerReceiver(
            context,
            receiver,
            IntentFilter(statusAction),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        statusReceiver = receiver
    }

    private fun unregisterStatusReceiver() {
        statusReceiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
            }
        }
        statusReceiver = null
    }

    private fun onInstallStatus(intent: Intent) {
        val sessionId = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)
        if (installResult == null || sessionId != installSessionId) return

        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmIntent = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_INTENT, Intent::class.java)
                if (confirmIntent == null) {
                    finishInstall { it.error("INSTALL_FAILED", "Missing confirmation intent", status) }
                    return
                }
                try {
                    startActivity(confirmIntent)
                } catch (e: Exception) {
                    finishInstall { it.error("INSTALL_FAILED", "Failed to show install confirmation: $e", status) }
                }
            }

            PackageInstaller.STATUS_SUCCESS -> finishInstall { it.success("session") }

            else -> {
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    ?: "Installation failed with status $status"
                finishInstall { it.error("INSTALL_FAILED", message, status) }
            }
        }
    }

    private fun finishInstall(respond: (MethodChannel.Result) -> Unit) {
        val result = installResult ?: return
        installResult = null
        installSessionId = null
        unregisterStatusReceiver()
        respond(result)
    }

    private fun installWithIntent(path: String, result: MethodChannel.Result) {
        executor.execute {
            val uri = try {
                // Copy the APK so the installer can still read it after the caller deleted the original.
                intentApkDir.deleteRecursively()
                intentApkDir.mkdirs()
                val target = File(intentApkDir, "update.apk")
                File(path).copyTo(target, overwrite = true)
                FileProvider.getUriForFile(context, providerAuthority, target)
            } catch (e: Exception) {
                mainHandler.post { result.error("INSTALL_FAILED", "Failed to prepare APK: $e", null) }
                return@execute
            }

            mainHandler.post {
                val intent = Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, APK_MIME_TYPE)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                try {
                    startActivity(intent)
                    result.success("intent")
                } catch (e: ActivityNotFoundException) {
                    result.error("INSTALL_FAILED", "No app can install APK files: $e", null)
                }
            }
        }
    }

    private fun startActivity(intent: Intent) {
        val activity = activity
        if (activity != null) {
            activity.startActivity(intent)
        } else {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}
