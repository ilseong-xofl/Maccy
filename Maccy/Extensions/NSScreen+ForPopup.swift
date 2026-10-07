import AppKit
import Defaults

extension NSScreen {
  static var forPopup: NSScreen? {
    let screens = NSScreen.screens
    guard let index = popupScreenIndex(
      desiredScreen: Defaults[.popupScreen],
      screenFrames: screens.map(\.frame),
      mouseLocation: NSEvent.mouseLocation
    ) else { return NSScreen.main ?? screens.first }
    return screens[index]
  }

  static func popupScreenIndex(
    desiredScreen: Int,
    screenFrames: [NSRect],
    mouseLocation: NSPoint
  ) -> Int? {
    if desiredScreen > 0, desiredScreen <= screenFrames.count {
      return desiredScreen - 1
    }
    // Use the full screen frame so the menu bar and Dock also belong to their display.
    return screenFrames.firstIndex { NSMouseInRect(mouseLocation, $0, false) }
  }
}
