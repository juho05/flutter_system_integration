package de.julianh.flutter_system_integration

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class FlutterSystemIntegrationPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var installer: ApkInstaller

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        installer = ApkInstaller(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, "flutter_system_integration/apk_installer")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        installer.dispose()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        installer.attachToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        installer.detachFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        installer.attachToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        installer.detachFromActivity()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasInstallPermission" -> result.success(installer.canRequestPackageInstalls())
            "requestInstallPermission" -> installer.requestInstallPermission(result)
            "install" -> {
                val path = call.argument<String>("path")
                    ?: return result.error("INVALID_ARGUMENT", "path is required", null)
                installer.install(path, result)
            }
            else -> result.notImplemented()
        }
    }
}
