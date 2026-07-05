package com.deivid22srk.pocketbase

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Ponte Flutter ↔ Android nativo.
 *
 * Expõe apenas dois métodos:
 *  - getNativeLibraryDir → caminho onde os lib*.so são extraídos do APK
 *    (aqui vive libpocketbase.so, o binário oficial pré-compilado)
 *  - getDataDir          → diretório gravável dentro do sandbox do app
 *    (onde o PocketBase guarda o SQLite)
 *
 * O start/stop do servidor é feito diretamente em Dart via dart:io Process,
 * sem precisar de MethodChannel.
 */
object PocketBasePlugin {

    private const val CHANNEL = "app.pocketbase/native"

    fun register(flutterEngine: FlutterEngine, context: Context) {
        val dataDir = context.getDir("pocketbase", Context.MODE_PRIVATE).absolutePath

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNativeLibraryDir" ->
                        result.success(context.applicationInfo.nativeLibraryDir)
                    "getDataDir" ->
                        result.success(dataDir)
                    else -> result.notImplemented()
                }
            }
    }
}
