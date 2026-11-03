package com.roxum

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.res.ColorStateList
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import androidx.annotation.NonNull
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.io.FileOutputStream
import java.io.OutputStream
import java.util.Collections
import java.util.concurrent.atomic.AtomicLong
import com.google.android.play.core.splitcompat.SplitCompat

class MainActivity : FlutterActivity() {
    private val TAG = "MainActivity"
    private val CORE_CHANNEL = "com.roxum"
    private val SAF_CHANNEL = "roxum/saf"
    private val PFD_CHANNEL = "roxum/pfd"
    private val PFD_EVENTS_CHANNEL = "roxum/pfd_events"
    private val PICK_DIR_REQUEST = 9001

    private var pendingSafResult: MethodChannel.Result? = null
    private var pfdEventSink: EventChannel.EventSink? = null
    private val pendingOpenFiles = Collections.synchronizedList(mutableListOf<String>())
    private lateinit var splitInstallService: SplitInstallService

    private data class ProgressDialogHandle(
        val dialog: AlertDialog,
        val titleView: TextView,
        val progressBar: ProgressBar,
        val percentView: TextView,
    )

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(newBase)
        SplitCompat.installActivity(this)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        splitInstallService = SplitInstallService(applicationContext)
        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CORE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getLibraryPath" -> result.success(applicationInfo.nativeLibraryDir)
                "consumePendingOpenFiles" -> {
                    val files = pendingOpenFiles.toList()
                    pendingOpenFiles.clear()
                    result.success(files)
                }
                "getExtMediaPath" -> {
                    val mediaDir = context.getExternalMediaDirs().firstOrNull()
                    result.success(mediaDir?.absolutePath ?: "")
                }
                else ->
                    result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SAF_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                "pickSafDir" -> {
                    if (pendingSafResult != null) {
                        result.error("BUSY", "Picker already active", null)
                        return@setMethodCallHandler
                    }
                    pendingSafResult = result
                    launchSafPicker()
                }

                "cloneSafDir" -> {
                    val uriStr = call.argument<String>("uri")
                    if (uriStr == null) {
                        result.error("NO_URI", "Missing SAF uri", null)
                        return@setMethodCallHandler
                    }
                    val progress = showProgressDialog("Importing folder...")
                    Thread {
                        try {
                            val path = cloneSafDir(Uri.parse(uriStr), progress)
                            runOnUiThread {
                                dismissProgressDialog(progress)
                                result.success(path)
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                dismissProgressDialog(progress)
                                result.error("CLONE_FAILED", e.message, null)
                            }
                        }
                    }.start()
                }

                "syncImportedItem" -> {
                    val uriStr = call.argument<String>("sourceUri")
                    val localPath = call.argument<String>("localPath")
                    val isDirectory = call.argument<Boolean>("isDirectory") ?: false
                    if (uriStr == null || localPath == null) {
                        result.error("BAD_ARGS", "sourceUri and localPath are required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val sourceUri = Uri.parse(uriStr)
                        if (isDirectory) {
                            val tree = DocumentFile.fromTreeUri(this, sourceUri)
                                ?: throw IllegalArgumentException("Invalid SAF tree URI")
                            syncDirectoryToTree(File(localPath), tree)
                        } else {
                            syncFileToUri(File(localPath), sourceUri)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SYNC_FAILED", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PFD_EVENTS_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                pfdEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                pfdEventSink = null
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PFD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isModuleInstalled" -> {
                    val moduleName = call.argument<String>("moduleName")
                    if (moduleName.isNullOrBlank()) {
                        result.error("BAD_ARGS", "moduleName is required", null)
                        return@setMethodCallHandler
                    }
                    result.success(splitInstallService.isModuleInstalled(moduleName))
                }

                "installModule" -> {
                    val moduleName = call.argument<String>("moduleName")
                    if (moduleName.isNullOrBlank()) {
                        result.error("BAD_ARGS", "moduleName is required", null)
                        return@setMethodCallHandler
                    }

                    splitInstallService.installModule(moduleName) { state ->
                        runOnUiThread {
                            pfdEventSink?.success(state)
                        }
                    }

                    result.success(true)
                }

                "uninstallModule" -> {
                    val moduleName = call.argument<String>("moduleName")
                    if (moduleName.isNullOrBlank()) {
                        result.error("BAD_ARGS", "moduleName is required", null)
                        return@setMethodCallHandler
                    }
                    splitInstallService.uninstallModule(moduleName)
                    result.success(true)
                }

                "copyModuleAssetToPath" -> {
                    val moduleName = call.argument<String>("moduleName")
                    val assetName = call.argument<String>("assetName")
                    val targetPath = call.argument<String>("targetPath")
                    if (moduleName.isNullOrBlank() || assetName.isNullOrBlank() || targetPath.isNullOrBlank()) {
                        result.error("BAD_ARGS", "moduleName, assetName and targetPath are required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val copied = copyModuleAssetToPath(moduleName, assetName, targetPath)
                        if (!copied) {
                            result.error("ASSET_NOT_FOUND", "Could not find $assetName in module $moduleName assets", null)
                            return@setMethodCallHandler
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("COPY_FAILED", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        splitInstallService.unregisterListener()
        pfdEventSink = null
        super.onDestroy()
    }

    private fun launchSafPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        startActivityForResult(intent, PICK_DIR_REQUEST)
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != PICK_DIR_REQUEST) return

        val result = pendingSafResult
        pendingSafResult = null

        if (result == null || resultCode != Activity.RESULT_OK || data == null) {
            result?.success(null)
            return
        }

        val uri = data.data ?: run {
            result.success(null)
            return
        }

        contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION
        )

        result.success(uri.toString())
    }


    private fun cloneSafDir(treeUri: Uri, progress: ProgressDialogHandle): String {
        val src = DocumentFile.fromTreeUri(this, treeUri)
            ?: throw IllegalArgumentException("Invalid SAF tree URI")

        val projectsRoot = File("/storage/emulated/0/Android/media/$packageName/Projects")
        if (!projectsRoot.exists()) projectsRoot.mkdirs()

        val target = File(projectsRoot, src.name ?: "ImportedProject")
        val totalBytes = calculateDocumentBytes(src)
        val copiedBytes = AtomicLong(0L)
        updateProgressDialog(progress, "Importing folder...", 0L, totalBytes)
        copySafRecursive(src, target, progress, totalBytes, copiedBytes)
        writeSourceMetadata(
            File(target, ".roxum_source.json"),
            treeUri.toString(),
            src.name ?: target.name,
            "directory",
            target.absolutePath,
        )

        return target.absolutePath
    }

    private fun calculateDocumentBytes(src: DocumentFile): Long {
        return if (src.isDirectory) {
            src.listFiles().sumOf { calculateDocumentBytes(it) }
        } else {
            src.length().coerceAtLeast(0L)
        }
    }

    private fun copySafRecursive(
        src: DocumentFile,
        dest: File,
        progress: ProgressDialogHandle,
        totalBytes: Long?,
        copiedBytes: AtomicLong,
    ) {
        if (src.isDirectory) {
            if (!dest.exists()) dest.mkdirs()
            src.listFiles().forEach { child ->
                val childDest = File(dest, child.name ?: "unknown")
                copySafRecursive(child, childDest, progress, totalBytes, copiedBytes)
            }
        } else {
            dest.parentFile?.let {
                if (!it.exists()) it.mkdirs()
            }
            contentResolver.openInputStream(src.uri)?.use { input ->
                dest.outputStream().use { output ->
                    val buffer = ByteArray(256 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        val copied = copiedBytes.addAndGet(read.toLong())
                        updateProgressDialog(progress, "Importing folder...", copied, totalBytes)
                    }
                    output.flush()
                }
            }
        }
    }

    private fun syncFileToUri(localFile: File, sourceUri: Uri) {
        contentResolver.openOutputStream(sourceUri, "wt")?.use { output ->
            localFile.inputStream().use { input ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Unable to open SAF output stream")
    }

    private fun syncDirectoryToTree(localDir: File, targetRoot: DocumentFile) {
        targetRoot.listFiles().forEach { child ->
            child.delete()
        }

        localDir.listFiles()?.forEach { child ->
            if (child.name == ".roxum_source.json" || child.name?.endsWith(".roxum_source.json") == true) {
                return@forEach
            }

            if (child.isDirectory) {
                val childTarget = ensureChildDirectory(targetRoot, child.name ?: "unknown")
                syncDirectoryToTree(child, childTarget)
            } else {
                syncFileToDocument(child, targetRoot)
            }
        }
    }

    private fun ensureChildDirectory(parent: DocumentFile, name: String): DocumentFile {
        val existing = parent.findFile(name)
        if (existing != null) {
            if (existing.isDirectory) {
                return existing
            }
            existing.delete()
        }

        return parent.createDirectory(name)
            ?: throw IllegalStateException("Unable to create SAF directory: $name")
    }

    private fun syncFileToDocument(localFile: File, targetRoot: DocumentFile) {
        val name = localFile.name
        val existing = targetRoot.findFile(name)
        if (existing != null) {
            existing.delete()
        }

        val targetFile = targetRoot.createFile("application/octet-stream", name)
            ?: throw IllegalStateException("Unable to create SAF file: $name")

        contentResolver.openOutputStream(targetFile.uri, "wt")?.use { output ->
            localFile.inputStream().use { input ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Unable to open SAF output stream for $name")
    }

    private fun copyModuleAssetToPath(moduleName: String, assetName: String, targetPath: String): Boolean {
        splitInstallService.refreshSplitCompat()
        SplitCompat.installActivity(this)

        val candidates = listOf(
            "assets/$assetName",
            assetName,
            "$moduleName/$assetName",
        )

        val inputStream = candidates.firstNotNullOfOrNull { candidate ->
            runCatching { assets.open(candidate) }.getOrNull()
        } ?: throw Exception("Asset '$assetName' not found in any candidate path: ${candidates.joinToString()}")

        val outputFile = File(targetPath)
        outputFile.parentFile?.mkdirs()

        inputStream.use { input ->
            FileOutputStream(outputFile).use { output ->
                input.copyTo(output)
            }
        }

        return true
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return

        val action = intent.action ?: return
        val uris = mutableListOf<Uri>()

        when (action) {
            Intent.ACTION_VIEW -> {
                intent.data?.let { uris.add(it) }
            }

            Intent.ACTION_SEND -> {
                val streamUri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (streamUri != null) {
                    uris.add(streamUri)
                } else {
                    intent.data?.let { uris.add(it) }
                }
            }

            Intent.ACTION_SEND_MULTIPLE -> {
                val list = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                if (list != null) {
                    uris.addAll(list)
                }
            }
        }

        if (uris.isEmpty()) return

        uris.forEach { uri ->
            grantReadPermissionIfNeeded(intent, uri)
        }

        val progress = showProgressDialog("Importing shared file...")
        Thread {
            try {
                uris.forEachIndexed { index, uri ->
                    val title = if (uris.size == 1) {
                        "Importing shared file..."
                    } else {
                        "Importing shared file ${index + 1} of ${uris.size}..."
                    }
                    val importedPath = importUriToAppFile(uri, progress, title)
                    if (importedPath != null) {
                        pendingOpenFiles.add(importedPath)
                    }
                }
            } finally {
                runOnUiThread {
                    dismissProgressDialog(progress)
                }
            }
        }.start()
    }

    private fun grantReadPermissionIfNeeded(intent: Intent, uri: Uri) {
        val flags = intent.flags
        val hasReadPermission =
            (flags and Intent.FLAG_GRANT_READ_URI_PERMISSION) == Intent.FLAG_GRANT_READ_URI_PERMISSION
        if (!hasReadPermission) return

        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: SecurityException) {
        }
    }

    private fun importUriToAppFile(uri: Uri, progress: ProgressDialogHandle, title: String): String? {
        val targetRoot = File("/storage/emulated/0/Android/media/$packageName/Files")
        if (!targetRoot.exists()) targetRoot.mkdirs()

        val preferredName = queryDisplayName(uri)
            ?: uri.lastPathSegment
            ?: "shared_file"
        val sanitizedName = preferredName.replace('/', '_')
        val targetFile = buildUniqueFile(targetRoot, sanitizedName)
        val totalBytes = queryUriSize(uri)

        return try {
            copyUriToFile(uri, targetFile, progress, title, totalBytes) ?: return null
            writeSourceMetadata(
                File("${targetFile.absolutePath}.roxum_source.json"),
                uri.toString(),
                sanitizedName,
                "file",
                targetFile.absolutePath,
            )
            targetFile.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun queryUriSize(uri: Uri): Long? {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (index != -1 && cursor.moveToFirst() && !cursor.isNull(index)) {
                    cursor.getLong(index)
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun showProgressDialog(title: String): ProgressDialogHandle {
        val isDarkTheme = isDarkAppTheme()
        val backgroundStart = if (isDarkTheme) 0xff2b2b2b.toInt() else 0xfffafafa.toInt()
        val backgroundEnd = if (isDarkTheme) 0xff1a1a1a.toInt() else 0xfff0f0f0.toInt()
        val textColor = if (isDarkTheme) Color.WHITE else Color.parseColor("#1f1f1f")
        val secondaryTextColor = if (isDarkTheme) Color.parseColor("#d9d9d9") else Color.parseColor("#5a5a5a")
        val progressColor = Color.parseColor("#0e639c")

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 40, 48, 28)
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(backgroundStart, backgroundEnd),
            ).apply {
                cornerRadius = resources.displayMetrics.density * 20
            }
        }

        val titleView = TextView(this).apply {
            text = title
            textSize = 18f
            setTextColor(textColor)
        }

        val progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            isIndeterminate = true
            max = 1000
            progressTintList = ColorStateList.valueOf(progressColor)
            indeterminateTintList = ColorStateList.valueOf(progressColor)
        }

        val percentView = TextView(this).apply {
            text = "Working..."
            textSize = 13f
            setTextColor(secondaryTextColor)
        }

        container.addView(titleView)
        container.addView(
            progressBar,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = 24
                bottomMargin = 16
            },
        )
        container.addView(percentView)

        val dialog = AlertDialog.Builder(this)
            .setCancelable(false)
            .setView(container)
            .create()
        dialog.window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        dialog.show()

        return ProgressDialogHandle(dialog, titleView, progressBar, percentView)
    }

    private fun isDarkAppTheme(): Boolean {
        return try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.getString("flutter.savedAppTheme", null) != "light"
        } catch (_: Exception) {
            true
        }
    }

    private fun dismissProgressDialog(progress: ProgressDialogHandle) {
        if (progress.dialog.isShowing) {
            progress.dialog.dismiss()
        }
    }

    private fun updateProgressDialog(
        progress: ProgressDialogHandle,
        title: String,
        copiedBytes: Long,
        totalBytes: Long?,
    ) {
        runOnUiThread {
            progress.titleView.text = title
            if (totalBytes == null || totalBytes <= 0L) {
                progress.progressBar.isIndeterminate = true
                progress.percentView.text = "Working..."
                return@runOnUiThread
            }

            val clampedCopied = copiedBytes.coerceAtMost(totalBytes)
            val percent = ((clampedCopied * 1000L) / totalBytes).toInt()
            progress.progressBar.isIndeterminate = false
            progress.progressBar.progress = percent
            progress.percentView.text = "${clampedCopied * 100 / totalBytes}%"
        }
    }

    private fun copyUriToFile(
        uri: Uri,
        targetFile: File,
        progress: ProgressDialogHandle,
        title: String,
        totalBytes: Long?,
    ): String? {
        contentResolver.openInputStream(uri)?.use { input ->
            targetFile.outputStream().use { output ->
                copyStreamWithProgress(input, output, progress, title, totalBytes)
            }
        } ?: return null

        return targetFile.absolutePath
    }

    private fun copyStreamWithProgress(
        input: InputStream,
        output: OutputStream,
        progress: ProgressDialogHandle,
        title: String,
        totalBytes: Long?,
    ) {
        val buffer = ByteArray(256 * 1024)
        var copiedBytes = 0L
        updateProgressDialog(progress, title, copiedBytes, totalBytes)

        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            output.write(buffer, 0, read)
            copiedBytes += read.toLong()
            updateProgressDialog(progress, title, copiedBytes, totalBytes)
        }

        output.flush()
    }

    private fun writeSourceMetadata(
        metadataFile: File,
        sourceUri: String,
        name: String,
        type: String,
        localRootPath: String,
    ) {
        try {
            metadataFile.parentFile?.mkdirs()
            val payload = JSONObject()
                .put("sourceUri", sourceUri)
                .put("name", name)
                .put("type", type)
                .put("localRootPath", localRootPath)
                .put("syncedAt", System.currentTimeMillis())
            metadataFile.writeText(payload.toString())
        } catch (_: Exception) {
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index != -1 && cursor.moveToFirst()) {
                    cursor.getString(index)
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun buildUniqueFile(directory: File, baseName: String): File {
        val dotIndex = baseName.lastIndexOf('.')
        val name = if (dotIndex > 0) baseName.substring(0, dotIndex) else baseName
        val ext = if (dotIndex > 0) baseName.substring(dotIndex) else ""

        var candidate = File(directory, "$name$ext")
        var i = 1
        while (candidate.exists()) {
            candidate = File(directory, "$name-$i$ext")
            i++
        }
        return candidate
    }
}
