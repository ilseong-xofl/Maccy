import Observation

@Observable
class SoftwareUpdater {
  // This independent development build has no automatic update service.
  let isAvailable = false
  var automaticallyChecksForUpdates = false

  func checkForUpdates() {}
}
