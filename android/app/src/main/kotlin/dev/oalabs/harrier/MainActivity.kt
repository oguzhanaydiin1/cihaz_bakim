package dev.oalabs.harrier

import android.Manifest
import android.app.ActivityManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.location.LocationManager
import android.media.ExifInterface
import android.net.TrafficStats
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * Harrier Cleaner'ın Android tarafı. Dart, "harrier/android" kanalından buradaki işlemleri çağırır.
 *
 * Android'de başka uygulamaların dosyalarına klasör klasör erişilemez; fotoğraf, video ve müzik
 * dosyalarına MediaStore üzerinden erişilir. Silme, çöp kutusuna taşıma ve değiştirme işlemlerinde
 * Android kullanıcıya kendi onay penceresini gösterir (Android 11 ve üstü).
 */
class MainActivity : FlutterActivity() {
    private val worker = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())

    // Kullanıcı yanıtı bekleyen istekler (izin, silme onayı, kaldırma).
    private var pendingPermission: MethodChannel.Result? = null
    private var pendingRequest: MethodChannel.Result? = null
    private var pendingUninstall: Pair<MethodChannel.Result, String>? = null

    companion object {
        private const val REQ_PERMISSION = 7101
        private const val REQ_MEDIA_REQUEST = 7102
        private const val REQ_UNINSTALL = 7103
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "harrier/android").setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (e: Exception) {
                result.error("error", e.message ?: e.toString(), null)
            }
        }
    }

    /** Uzun süren işleri arka planda çalıştırır, sonucu ana iş parçacığında döndürür. */
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("error", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "filesDir" -> result.success(filesDir.absolutePath)
            "storage" -> result.success(storage())
            "mediaPermission" -> mediaPermission(call.argument<Boolean>("request") == true, result)
            "queryMedia" -> background(result) {
                queryMedia(
                    call.argument<List<String>>("kinds") ?: listOf("image"),
                    (call.argument<Number>("minSize") ?: 0).toLong(),
                    call.argument<Boolean>("jpegOnly") == true,
                )
            }
            "hash" -> background(result) {
                val limit = (call.argument<Number>("limit") ?: 0).toLong()
                (call.argument<List<String>>("uris") ?: emptyList()).map { hash(Uri.parse(it), limit) }
            }
            "gps" -> background(result) {
                (call.argument<List<String>>("uris") ?: emptyList()).map { gps(Uri.parse(it)) }
            }
            "readBytes" -> background(result) {
                readBytes(Uri.parse(call.argument<String>("uri")!!), call.argument<Boolean>("original") == true)
            }
            "writeBytes" -> background(result) {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                val bytes = call.argument<ByteArray>("bytes")!!
                contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) } != null
            }
            "copyToCache" -> background(result) {
                copyToCache(Uri.parse(call.argument<String>("uri")!!), call.argument<String>("name") ?: "photo.jpg")
            }
            "clearWork" -> background(result) { File(cacheDir, "hc_work").deleteRecursively() }
            "insertImage" -> background(result) {
                insertImage(
                    call.argument<String>("src")!!,
                    call.argument<String>("name")!!,
                    call.argument<String>("relativePath") ?: "Pictures/",
                    (call.argument<Number>("dateTaken") ?: 0).toLong(),
                )
            }
            "backupCopy" -> background(result) {
                backupCopy(Uri.parse(call.argument<String>("uri")!!), call.argument<String>("name") ?: "photo.jpg")
            }
            "overwrite" -> background(result) {
                overwrite(Uri.parse(call.argument<String>("uri")!!), call.argument<String>("src")!!)
            }
            "deleteOwn" -> background(result) {
                (call.argument<List<String>>("uris") ?: emptyList()).sumOf {
                    try {
                        contentResolver.delete(Uri.parse(it), null, null)
                    } catch (e: Exception) {
                        0
                    }
                }
            }
            "request" -> mediaRequest(call.argument<String>("type") ?: "delete", call.argument<List<String>>("uris") ?: emptyList(), result)
            "battery" -> result.success(battery())
            "system" -> result.success(system())
            "live" -> result.success(live())
            "apps" -> background(result) { apps() }
            "uninstall" -> uninstall(call.argument<String>("pkg")!!, result)
            "permissions" -> background(result) { permissions() }
            "open" -> result.success(open(call.argument<String>("url") ?: ""))
            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------------------------------
    // Depolama ve izinler
    // ---------------------------------------------------------------------------------------

    private fun storage(): Map<String, Long> {
        val stat = StatFs(Environment.getDataDirectory().path)
        return mapOf("total" to stat.totalBytes, "free" to stat.availableBytes)
    }

    private fun mediaPermissions(): List<String> = when {
        Build.VERSION.SDK_INT >= 33 -> listOf(
            Manifest.permission.READ_MEDIA_IMAGES,
            Manifest.permission.READ_MEDIA_VIDEO,
            Manifest.permission.READ_MEDIA_AUDIO,
        )
        Build.VERSION.SDK_INT >= 30 -> listOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        else -> listOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE)
    }

    private fun granted(p: String) = checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    private fun permissionState(): Map<String, Any> {
        val full = mediaPermissions().all { granted(it) }
        val partial = !full && Build.VERSION.SDK_INT >= 34 && granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
        return mapOf(
            "granted" to (full || partial),
            "partial" to partial,
            "location" to granted(Manifest.permission.ACCESS_MEDIA_LOCATION),
        )
    }

    private fun mediaPermission(request: Boolean, result: MethodChannel.Result) {
        val state = permissionState()
        if (!request || (state["granted"] == true && state["partial"] == false && state["location"] == true)) {
            result.success(state)
            return
        }
        if (pendingPermission != null) {
            result.error("busy", "İzin penceresi zaten açık", null)
            return
        }
        val wanted = mediaPermissions().toMutableList()
        if (Build.VERSION.SDK_INT >= 34) wanted.add(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
        wanted.add(Manifest.permission.ACCESS_MEDIA_LOCATION)
        requestPermissions(wanted.toTypedArray(), REQ_PERMISSION)
        pendingPermission = result
    }

    @Deprecated("FlutterActivity hâlâ bu yolu kullanıyor")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_PERMISSION) {
            val r = pendingPermission
            pendingPermission = null
            r?.success(permissionState())
        }
    }

    // ---------------------------------------------------------------------------------------
    // Medya
    // ---------------------------------------------------------------------------------------

    private fun collection(kind: String): Uri = when (kind) {
        "video" -> MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        "audio" -> MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        else -> MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
    }

    private fun queryMedia(kinds: List<String>, minSize: Long, jpegOnly: Boolean): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        for (kind in kinds) {
            val base = collection(kind)
            val projection = arrayListOf(
                MediaStore.MediaColumns._ID,
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.RELATIVE_PATH,
                MediaStore.MediaColumns.SIZE,
                MediaStore.MediaColumns.DATE_MODIFIED,
                MediaStore.MediaColumns.DATE_ADDED,
                MediaStore.MediaColumns.MIME_TYPE,
            )
            if (kind != "audio") projection.add(MediaStore.MediaColumns.DATE_TAKEN)
            var selection = "${MediaStore.MediaColumns.SIZE} >= ?"
            val args = arrayListOf(minSize.toString())
            if (jpegOnly) {
                selection += " AND ${MediaStore.MediaColumns.MIME_TYPE} = ?"
                args.add("image/jpeg")
            }
            contentResolver.query(base, projection.toTypedArray(), selection, args.toTypedArray(), null)?.use { c ->
                val iId = c.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val iName = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val iPath = c.getColumnIndexOrThrow(MediaStore.MediaColumns.RELATIVE_PATH)
                val iSize = c.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                val iMod = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
                val iAdded = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED)
                val iTaken = c.getColumnIndex(MediaStore.MediaColumns.DATE_TAKEN)
                val iMime = c.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
                while (c.moveToNext()) {
                    val id = c.getLong(iId)
                    out.add(
                        mapOf(
                            "uri" to ContentUris.withAppendedId(base, id).toString(),
                            "name" to (c.getString(iName) ?: "$id"),
                            "dir" to (c.getString(iPath) ?: ""),
                            "size" to c.getLong(iSize),
                            "modified" to c.getLong(iMod) * 1000,
                            "added" to c.getLong(iAdded) * 1000,
                            "taken" to (if (iTaken < 0 || c.isNull(iTaken)) 0L else c.getLong(iTaken)),
                            "mime" to (c.getString(iMime) ?: ""),
                            "kind" to kind,
                        ),
                    )
                }
            }
        }
        return out
    }

    /** SHA-1 özeti; [limit] > 0 ise yalnızca ilk [limit] bayt okunur. Okunamazsa null. */
    private fun hash(uri: Uri, limit: Long): String? = try {
        contentResolver.openInputStream(uri)?.use { input ->
            val digest = MessageDigest.getInstance("SHA-1")
            val buffer = ByteArray(1 shl 20)
            var remaining = if (limit > 0) limit else Long.MAX_VALUE
            while (remaining > 0) {
                val n = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                if (n <= 0) break
                digest.update(buffer, 0, n)
                remaining -= n
            }
            digest.digest().joinToString("") { "%02x".format(it) }
        }
    } catch (e: Exception) {
        null
    }

    /** Fotoğraftaki konum: [enlem, boylam]; konum yoksa ya da okunamazsa null. */
    private fun gps(uri: Uri): List<Double>? = try {
        val source = if (granted(Manifest.permission.ACCESS_MEDIA_LOCATION)) MediaStore.setRequireOriginal(uri) else uri
        contentResolver.openInputStream(source)?.use { input ->
            val exif = ExifInterface(input)
            val ll = FloatArray(2)
            @Suppress("DEPRECATION")
            if (exif.getLatLong(ll) && !(ll[0] == 0f && ll[1] == 0f)) listOf(ll[0].toDouble(), ll[1].toDouble()) else null
        }
    } catch (e: Exception) {
        null
    }

    private fun readBytes(uri: Uri, original: Boolean): ByteArray? {
        val source = if (original && granted(Manifest.permission.ACCESS_MEDIA_LOCATION)) MediaStore.setRequireOriginal(uri) else uri
        return contentResolver.openInputStream(source)?.use { it.readBytes() }
    }

    private fun copyToCache(uri: Uri, name: String): String? {
        val dir = File(cacheDir, "hc_work").apply { mkdirs() }
        val safe = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val file = File(dir, "${System.nanoTime()}_$safe")
        contentResolver.openInputStream(uri)?.use { input -> file.outputStream().use { input.copyTo(it) } } ?: return null
        return file.absolutePath
    }

    /**
     * Orijinal fotoğrafın birebir kopyasını "Pictures/Harrier Cleaner Yedek/" albümüne kaydeder.
     * Kopyanın sahibi bu uygulamadır; kullanıcı albümü silince yer açılır. Başarısızsa null.
     */
    private fun backupCopy(source: Uri, name: String): String? {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, contentResolver.getType(source) ?: "image/jpeg")
            put(MediaStore.MediaColumns.RELATIVE_PATH, "Pictures/Harrier Cleaner Yedek/")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val target = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = contentResolver.insert(target, values) ?: return null
        try {
            val copied = contentResolver.openInputStream(source)?.use { input ->
                contentResolver.openOutputStream(uri, "w")?.use { input.copyTo(it) }
            } ?: throw IllegalStateException("kopyalanamadı")
            if (copied <= 0) throw IllegalStateException("boş kopya")
            contentResolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            return null
        }
        return uri.toString()
    }

    /**
     * Fotoğrafın içeriğini olduğu yerde değiştirir: adı, klasörü ve galerideki yeri aynı kalır.
     * Android 11+ için önce "write" onayı alınmış olmalıdır.
     */
    private fun overwrite(uri: Uri, src: String): Boolean {
        val file = File(src)
        if (!file.exists() || file.length() == 0L) return false
        contentResolver.openOutputStream(uri, "wt")?.use { out -> file.inputStream().use { it.copyTo(out) } } ?: return false
        return true
    }

    /** Küçültülmüş fotoğrafı orijinalin klasörüne, aynı adla ve çekim tarihiyle ekler. */
    private fun insertImage(src: String, name: String, relativePath: String, dateTaken: Long): String? {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
            put(MediaStore.MediaColumns.RELATIVE_PATH, if (relativePath.endsWith("/")) relativePath else "$relativePath/")
            if (dateTaken > 0) put(MediaStore.MediaColumns.DATE_TAKEN, dateTaken)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val target = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = contentResolver.insert(target, values) ?: return null
        try {
            contentResolver.openOutputStream(uri, "w")?.use { out -> File(src).inputStream().use { it.copyTo(out) } }
                ?: throw IllegalStateException("yazılamadı")
            contentResolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            return null
        }
        return uri.toString()
    }

    /**
     * Silme, çöp kutusuna taşıma ya da değiştirme için kullanıcı onayı.
     * Android 11 ve üstünde sistem penceresi açılır; onaylanırsa silme/taşıma işlemini sistem yapar.
     * Android 10'da (eski depolama düzeni) silme doğrudan yapılır, değiştirme için onay gerekmez.
     */
    private fun mediaRequest(type: String, uriStrings: List<String>, result: MethodChannel.Result) {
        val uris = uriStrings.map { Uri.parse(it) }
        if (uris.isEmpty()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < 30) {
            if (type == "write") {
                result.success(true)
                return
            }
            background(result) {
                var deleted = 0
                for (u in uris) {
                    try {
                        deleted += contentResolver.delete(u, null, null)
                    } catch (e: Exception) {
                    }
                }
                deleted > 0
            }
            return
        }
        if (pendingRequest != null) {
            result.error("busy", "Onay penceresi zaten açık", null)
            return
        }
        val pi = when (type) {
            "trash" -> MediaStore.createTrashRequest(contentResolver, uris, true)
            "write" -> MediaStore.createWriteRequest(contentResolver, uris)
            else -> MediaStore.createDeleteRequest(contentResolver, uris)
        }
        @Suppress("DEPRECATION")
        startIntentSenderForResult(pi.intentSender, REQ_MEDIA_REQUEST, null, 0, 0, 0)
        pendingRequest = result
    }

    @Deprecated("FlutterActivity hâlâ bu yolu kullanıyor")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQ_MEDIA_REQUEST -> {
                val r = pendingRequest
                pendingRequest = null
                r?.success(resultCode == RESULT_OK)
            }
            REQ_UNINSTALL -> {
                val p = pendingUninstall
                pendingUninstall = null
                if (p != null) p.first.success(!isInstalled(p.second))
            }
        }
    }

    // ---------------------------------------------------------------------------------------
    // Pil ve cihaz
    // ---------------------------------------------------------------------------------------

    private fun battery(): Map<String, Any?>? {
        val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return null
        if (!intent.getBooleanExtra(BatteryManager.EXTRA_PRESENT, true)) return null
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        val bm = getSystemService(BATTERY_SERVICE) as BatteryManager
        val counter = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER) // µAh
        val cycles = if (Build.VERSION.SDK_INT >= 34) intent.getIntExtra(BatteryManager.EXTRA_CYCLE_COUNT, -1) else -1
        val health = when (intent.getIntExtra(BatteryManager.EXTRA_HEALTH, BatteryManager.BATTERY_HEALTH_UNKNOWN)) {
            BatteryManager.BATTERY_HEALTH_GOOD -> "good"
            BatteryManager.BATTERY_HEALTH_OVERHEAT -> "overheat"
            BatteryManager.BATTERY_HEALTH_DEAD -> "dead"
            BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "overvoltage"
            BatteryManager.BATTERY_HEALTH_COLD -> "cold"
            BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "failure"
            else -> "unknown"
        }
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        val pct = if (level >= 0 && scale > 0) level * 100 / scale else -1
        return mapOf(
            "level" to pct,
            "temperature" to intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE).let { if (it == Int.MIN_VALUE) null else it / 10.0 },
            "voltage" to intent.getIntExtra(BatteryManager.EXTRA_VOLTAGE, 0),
            "technology" to (intent.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY) ?: ""),
            "health" to health,
            "charging" to charging,
            "cycles" to (if (cycles > 0) cycles else null),
            // Şu anki yük ve yüzdeden tahmini tam şarj kapasitesi (mAh); telefon bildirmiyorsa null.
            "estimatedFull" to (if (counter > 0 && pct in 20..100) counter.toLong() * 100 / pct / 1000 else null),
        )
    }

    private fun readKhz(path: String): Long = try {
        File(path).readText().trim().toLong()
    } catch (e: Exception) {
        0L
    }

    private fun cpuFreqMhz(file: String, max: Boolean): Long {
        val n = Runtime.getRuntime().availableProcessors()
        val values = (0 until n).map { readKhz("/sys/devices/system/cpu/cpu$it/cpufreq/$file") }.filter { it > 0 }
        if (values.isEmpty()) return 0
        return (if (max) values.max() else values.sum() / values.size) / 1000
    }

    private fun system(): Map<String, Any?> {
        val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        val mem = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val soc = if (Build.VERSION.SDK_INT >= 31) listOf(Build.SOC_MANUFACTURER, Build.SOC_MODEL)
            .filter { it.isNotBlank() && it != Build.UNKNOWN }.joinToString(" ") else ""
        return mapOf(
            "cpu" to soc.ifBlank { Build.HARDWARE },
            "cores" to Runtime.getRuntime().availableProcessors(),
            "maxMhz" to cpuFreqMhz("cpuinfo_max_freq", true),
            "ram" to mem.totalMem,
            "os" to "Android ${Build.VERSION.RELEASE}",
            "sdk" to Build.VERSION.SDK_INT,
            "boot" to (System.currentTimeMillis() - SystemClock.elapsedRealtime()),
            "maker" to Build.MANUFACTURER.replaceFirstChar { it.uppercase() },
            "model" to Build.MODEL,
        )
    }

    private fun live(): Map<String, Any?> {
        val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        val mem = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val t = battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE) ?: Int.MIN_VALUE
        return mapOf(
            "avail" to mem.availMem,
            "mhz" to cpuFreqMhz("scaling_cur_freq", false),
            "rx" to TrafficStats.getTotalRxBytes(),
            "tx" to TrafficStats.getTotalTxBytes(),
            "temp" to (if (t == Int.MIN_VALUE) null else t / 10.0),
        )
    }

    // ---------------------------------------------------------------------------------------
    // Uygulamalar ve izinler
    // ---------------------------------------------------------------------------------------

    private fun launchablePackages(): List<String> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        return packageManager.queryIntentActivities(intent, 0).map { it.activityInfo.packageName }.distinct().filter { it != packageName }
    }

    private fun isInstalled(pkg: String): Boolean = try {
        @Suppress("DEPRECATION")
        packageManager.getPackageInfo(pkg, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun apps(): List<Map<String, Any?>> {
        val pm = packageManager
        val out = ArrayList<Map<String, Any?>>()
        for (pkg in launchablePackages()) {
            try {
                @Suppress("DEPRECATION")
                val info = pm.getPackageInfo(pkg, 0)
                val ai = info.applicationInfo ?: continue
                if (ai.flags and ApplicationInfo.FLAG_SYSTEM != 0) continue // kaldırılamaz
                var size = File(ai.sourceDir).length()
                ai.splitSourceDirs?.forEach { size += File(it).length() }
                out.add(
                    mapOf(
                        "pkg" to pkg,
                        "name" to ai.loadLabel(pm).toString(),
                        "version" to (info.versionName ?: ""),
                        "installed" to info.firstInstallTime,
                        "size" to size,
                    ),
                )
            } catch (e: Exception) {
            }
        }
        return out
    }

    private fun uninstall(pkg: String, result: MethodChannel.Result) {
        if (pendingUninstall != null) {
            result.error("busy", "Kaldırma penceresi zaten açık", null)
            return
        }
        @Suppress("DEPRECATION")
        startActivityForResult(Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg")), REQ_UNINSTALL)
        pendingUninstall = Pair(result, pkg)
    }

    private fun permissions(): Map<String, Any?> {
        val pm = packageManager
        val uses = ArrayList<Map<String, Any?>>()
        val checks = listOf(
            "camera" to listOf(Manifest.permission.CAMERA),
            "microphone" to listOf(Manifest.permission.RECORD_AUDIO),
            "location" to listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
        )
        for (pkg in launchablePackages()) {
            val label = try {
                @Suppress("DEPRECATION")
                pm.getApplicationInfo(pkg, 0).loadLabel(pm).toString()
            } catch (e: Exception) {
                continue
            }
            for ((kind, perms) in checks) {
                if (perms.none { pm.checkPermission(it, pkg) == PackageManager.PERMISSION_GRANTED }) continue
                val background = kind == "location" &&
                    pm.checkPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION, pkg) == PackageManager.PERMISSION_GRANTED
                uses.add(mapOf("kind" to kind, "app" to label, "pkg" to pkg, "background" to background))
            }
        }
        val lm = getSystemService(LOCATION_SERVICE) as LocationManager
        return mapOf("location" to lm.isLocationEnabled, "uses" to uses)
    }

    /** https / mailto bağlantıları, "package:<ad>" (uygulama ayarları) ve "settings:privacy". */
    private fun open(url: String): Boolean = try {
        val intent = when {
            url.startsWith("package:") -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse(url))
            url == "settings:privacy" -> Intent(Settings.ACTION_PRIVACY_SETTINGS)
            url.startsWith("mailto:") -> Intent(Intent.ACTION_SENDTO, Uri.parse(url))
            else -> Intent(Intent.ACTION_VIEW, Uri.parse(url))
        }
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }
}
