import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let backgroundSyncIdentifier =
    "com.clementg.rccompanion.background.sync"
  private let backgroundRecoveryIdentifier =
    "com.clementg.rccompanion.background.recovery"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Les handlers BGTaskScheduler doivent exister avant la fin du lancement.
    // Pré-enregistrement explicite des deux identifiants utilisés par Dart.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: backgroundSyncIdentifier,
      frequency: NSNumber(value: 15 * 60)
    )

    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: backgroundRecoveryIdentifier
    )

    // Réenregistre également les identifiants persistés par Workmanager
    // lors des lancements précédents (nécessaire avec UIScene / iOS 26).
    WorkmanagerPlugin.registerLaunchHandlers()

    // Rend les autres plugins Flutter accessibles à l'isolate de fond.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  func didInitializeImplicitFlutterEngine(
    _ engineBridge: FlutterImplicitEngineBridge
  ) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
