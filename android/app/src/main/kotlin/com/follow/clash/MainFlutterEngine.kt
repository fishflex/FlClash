package com.follow.clash

import android.content.Context
import com.follow.clash.plugins.AppPlugin
import com.follow.clash.plugins.BatteryPlugin
import com.follow.clash.plugins.ServicePlugin
import com.follow.clash.plugins.TilePlugin
import io.flutter.embedding.engine.FlutterEngine

// Outlives any MainActivity; see "Android engine kept" in .agents/flutter-upgrade.md.
internal object MainFlutterEngine {
    private var engine: FlutterEngine? = null

    fun obtain(context: Context, shellArgs: Array<String>): FlutterEngine =
        engine ?: FlutterEngine(context.applicationContext, shellArgs).also { created ->
            created.plugins.add(AppPlugin())
            created.plugins.add(BatteryPlugin())
            created.plugins.add(ServicePlugin())
            created.plugins.add(TilePlugin())
            ServiceState.attachFlutterEngine(created)
            created.addEngineLifecycleListener(
                object : FlutterEngine.EngineLifecycleListener {
                    override fun onPreEngineRestart() = Unit

                    override fun onEngineWillDestroy() {
                        ServiceState.detachFlutterEngine(created)
                        engine = null
                    }
                },
            )
            engine = created
        }
}
