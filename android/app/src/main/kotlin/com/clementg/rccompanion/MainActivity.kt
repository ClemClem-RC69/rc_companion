package com.clementg.rccompanion

import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val STORAGE_CHANNEL = "com.clementg.rccompanion/offline_storage"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORAGE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStorageVolumes" -> {
                    try {
                        result.success(getStorageVolumes())
                    } catch (error: Exception) {
                        result.error(
                            "STORAGE_VOLUMES_ERROR",
                            "Impossible de lire les volumes de stockage Android.",
                            error.message,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getStorageVolumes(): List<Map<String, Any?>> {
        val directories = getExternalFilesDirs(null)
        val volumes = mutableListOf<Map<String, Any?>>()

        directories.forEachIndexed { index, directory ->
            if (directory == null) return@forEachIndexed

            val rcCompanionDirectory = File(directory, "RC Companion")
            val removable = Environment.isExternalStorageRemovable(directory)
            val state = Environment.getExternalStorageState(directory)
            val mounted = state == Environment.MEDIA_MOUNTED ||
                state == Environment.MEDIA_MOUNTED_READ_ONLY

            var totalBytes = 0L
            var freeBytes = 0L

            if (mounted) {
                try {
                    val stat = StatFs(directory.absolutePath)
                    totalBytes = stat.totalBytes
                    freeBytes = stat.availableBytes
                } catch (_: Exception) {
                }
            }

            volumes.add(
                mapOf(
                    "index" to index,
                    "path" to directory.absolutePath,
                    "rcCompanionPath" to rcCompanionDirectory.absolutePath,
                    "removable" to removable,
                    "state" to state,
                    "mounted" to mounted,
                    "writable" to (state == Environment.MEDIA_MOUNTED),
                    "totalBytes" to totalBytes,
                    "freeBytes" to freeBytes,
                ),
            )
        }

        return volumes
    }
}
