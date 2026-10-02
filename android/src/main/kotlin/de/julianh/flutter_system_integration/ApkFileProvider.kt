package de.julianh.flutter_system_integration

import androidx.core.content.FileProvider

// Own subclass so the manifest entry does not clash with other FileProviders of the app.
class ApkFileProvider : FileProvider()
