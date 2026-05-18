package com.enginebeck.colatranslate

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
	private val channelName = "cola.translate/engine"
	private val modelPrefix = "Hy-MT1.5-1.8B-1.25bit"
	private var loadedModelFile: File? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"initEngine" -> result.success(initEngine())
					"getBundledModelPath" -> result.success(extractBundledModel())
					"listModels" -> result.success(listModels())
					"downloadModel" -> {
						val modelName = call.argument<String>("modelName") ?: "$modelPrefix.onnx"
						result.success(downloadModel(modelName))
					}
					"deleteModel" -> {
						val modelName = call.argument<String>("modelName") ?: "$modelPrefix.onnx"
						result.success(deleteModel(modelName))
					}
					"translate" -> {
						if (!initEngine()) {
							result.error(
								"engine_not_ready",
								"Offline model is not loaded. Please download model first.",
								null
							)
							return@setMethodCallHandler
						}
						val text = call.argument<String>("text") ?: ""
						val targetLang = call.argument<String>("targetLang") ?: "en"
						result.success(mockTranslate(text, targetLang))
					}
					else -> result.notImplemented()
				}
			}
	}

	private fun initEngine(): Boolean {
		loadedModelFile = findModelFile()
		return loadedModelFile != null
	}

	private fun modelsDir(): File {
		return File(filesDir, "models").apply {
			if (!exists()) {
				mkdirs()
			}
		}
	}

	private fun listModels(): List<String> {
		val files = modelsDir()
			.listFiles()
			?.filter { it.isFile && (it.extension == "onnx" || it.extension == "tflite") }
			?.sortedBy { it.name.lowercase() }
			?: emptyList()
		return files.map { it.name }
	}

	private fun findModelFile(): File? {
		return modelsDir()
			.listFiles()
			?.filter { it.isFile && it.name.contains(modelPrefix, ignoreCase = true) }
			?.sortedByDescending { it.length() }
			?.firstOrNull()
	}

	/// Copies the GGUF model from APK assets to internal storage on first
	/// launch (idempotent) and returns its absolute path. The native engine
	/// requires a real filesystem path because it mmap()s the model.
	private fun extractBundledModel(): String? {
		val fname = "$modelPrefix.gguf"
		val target = File(modelsDir(), fname)
		if (target.exists() && target.length() > 0) {
			return target.absolutePath
		}
		val assetPath = "flutter_assets/assets/models/$fname"
		return try {
			assets.open(assetPath).use { input ->
				target.outputStream().use { output ->
					input.copyTo(output, bufferSize = 1 shl 20)
				}
			}
			target.absolutePath
		} catch (_: Exception) {
			null
		}
	}

	private fun downloadModel(modelName: String): Boolean {
		return try {
			val target = File(modelsDir(), modelName)
			val assetPath = "flutter_assets/assets/models/$modelName"
			if (!target.exists()) {
				try {
					assets.open(assetPath).use { input ->
						target.outputStream().use { output ->
							input.copyTo(output)
						}
					}
				} catch (_: Exception) {
					// When no embedded asset exists, create a tiny placeholder to keep the flow testable.
					target.writeText("placeholder model file: $modelName")
				}
			}
			initEngine()
		} catch (_: Exception) {
			false
		}
	}

	private fun deleteModel(modelName: String): Boolean {
		val target = File(modelsDir(), modelName)
		if (!target.exists()) {
			return false
		}
		val deleted = target.delete()
		if (deleted && loadedModelFile?.absolutePath == target.absolutePath) {
			loadedModelFile = null
		}
		return deleted
	}

	private fun mockTranslate(text: String, targetLang: String): String {
		if (text.isBlank()) {
			return ""
		}
		val dictionary = mapOf(
			"你好" to "Hello",
			"谢谢" to "Thank you",
			"再见" to "Goodbye",
			"apple" to "苹果"
		)
		val direct = dictionary[text.trim()]
		return direct ?: "[$targetLang/离线] $text"
	}
}
