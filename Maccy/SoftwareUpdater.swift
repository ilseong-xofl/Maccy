import Sparkle

@Observable
class SoftwareUpdater {
  // Development forks must never install an official Maccy release over themselves.
  let isAvailable = Bundle.main.bundleIdentifier == "org.p0deje.Maccy"

  var automaticallyChecksForUpdates = false {
    didSet {
      updater?.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }
  }

  private var updater: SPUUpdater?
  private var automaticallyChecksForUpdatesObservation: NSKeyValueObservation?
  private var updaterController: SPUStandardUpdaterController?

  init() {
    guard isAvailable else { return }

    let updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
    self.updaterController = updaterController
    updater = updaterController.updater
    automaticallyChecksForUpdatesObservation = updater?.observe(
      \.automaticallyChecksForUpdates,
      options: [.initial, .new, .old]
    ) { [unowned self] updater, change in
      guard change.newValue != change.oldValue else {
        return
      }

      self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    }
  }

  func checkForUpdates() {
    updater?.checkForUpdates()
  }
}
