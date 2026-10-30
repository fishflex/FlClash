package com.follow.clash

import android.content.Context
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var isExiting = false

    private var keepsProcessForRun = false

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        MainFlutterEngine.obtain(context, flutterShellArgs.toArray())

    // Dart has closed the Core by now, so the next launch needs a new engine.
    override fun popSystemNavigator(): Boolean {
        isExiting = true
        keepsProcessForRun = ServiceState.isRunRequested || ServiceController.runtime != null
        return false
    }

    override fun shouldDestroyEngineWithHost(): Boolean = isExiting && keepsProcessForRun

    override fun detachFromFlutterEngine() {
        super.detachFromFlutterEngine()
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isExiting && !keepsProcessForRun) {
            Process.killProcess(Process.myPid())
        }
    }
}
