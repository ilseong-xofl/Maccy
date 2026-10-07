import Defaults
import SwiftUI

// An NSPanel subclass that implements floating panel traits.
// https://stackoverflow.com/questions/46023769/how-to-show-a-window-without-stealing-focus-on-macos
class FloatingPanel<Content: View>: NSPanel, NSWindowDelegate {
  static var minimumListWidth: CGFloat { 200 }
  var isPresented: Bool = false
  var statusBarButton: NSStatusBarButton?
  let onClose: () -> Void

  override var isMovable: Bool {
    get { Defaults[.popupPosition] != .statusItem }
    set {}
  }

  init(
    contentRect: NSRect,
    identifier: String = "",
    statusBarButton: NSStatusBarButton? = nil,
    onClose: @escaping () -> Void,
    view: () -> Content
  ) {
    self.onClose = onClose

    super.init(
        contentRect: contentRect,
        styleMask: [.nonactivatingPanel, .resizable, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )

    self.statusBarButton = statusBarButton
    self.identifier = NSUserInterfaceItemIdentifier(identifier)

    delegate = self

    animationBehavior = .none
    isFloatingPanel = true
    // TODO: Automatically detect Chrome autofill that uses window layer 999 and set to screenSaver (1000). See #1403.
    level = .statusBar
    collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = true
    hidesOnDeactivate = false
    backgroundColor = .clear
    titlebarSeparatorStyle = .none

    // Hide all traffic light buttons
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true

    let hostingView = NSHostingView(
      rootView: FloatingPanelRootView(
        content: view(),
        onWindowDragEnded: { [weak self] in
          self?.saveWindowPosition()
        }
      )
    )
    // Keep native resizing independent of SwiftUI's current layout size.
    hostingView.sizingOptions = []
    contentView = hostingView
    contentMinSize = NSSize(
      width: Self.minimumListWidth,
      height: AppState.shared.popup.minimumHeight
    )
    applyRoundedCorners()
  }

  private func applyRoundedCorners() {
    let radius = Popup.cornerRadius + Popup.horizontalPadding

    for view in [contentView, contentView?.superview].compactMap({ $0 }) {
      view.wantsLayer = true
      view.layer?.cornerRadius = radius
      view.layer?.cornerCurve = .continuous
      view.layer?.masksToBounds = true
    }
  }

  func toggle(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    if isPresented {
      close()
    } else {
      open(height: height, at: popupPosition)
    }
  }

  func open(height _: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    let appState = AppState.shared
    let requestedSize = Defaults[.windowSize]
    let visibleFrame = targetScreen(at: popupPosition)?.visibleFrame
    let finalSize = NSSize(
      width: min(max(requestedSize.width, Self.minimumListWidth), visibleFrame?.width ?? .infinity),
      height: min(max(requestedSize.height, appState.popup.minimumHeight), visibleFrame?.height ?? .infinity)
    )
    appState.isSearchFocused = false
    setContentSize(finalSize)
    var origin = popupPosition.origin(size: frame.size, statusBarButton: statusBarButton)
    if let visibleFrame {
      origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
      origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)
    }
    setFrameOrigin(origin)
    orderFrontRegardless()
    makeKey()
    isPresented = true
    DispatchQueue.main.async { [weak self] in
      guard let self, self.isPresented, self.isKeyWindow else { return }
      AppState.shared.requestKeyboardFocus(.list)
    }

    if popupPosition == .statusItem {
      DispatchQueue.main.async {
        self.statusBarButton?.isHighlighted = true
      }
    }
  }

  private func targetScreen(at popupPosition: PopupPosition) -> NSScreen? {
    switch popupPosition {
    case .center, .lastPosition:
      return NSScreen.forPopup
    case .statusItem:
      return statusBarButton?.window?.screen ?? NSScreen.main
    case .window:
      if let windowFrame = NSWorkspace.shared.frontmostApplication?.windowFrame {
        let center = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
        return NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) } ?? NSScreen.main
      }
    case .cursor:
      break
    }

    let mouseLocation = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
  }

  func verticallyResize(to newHeight: CGFloat) {
    var newSize = frame.size
    newSize.height = newHeight
    var newOrigin = frame.origin
    newOrigin.y += (frame.height - newSize.height)

    NSAnimationContext.runAnimationGroup { (context) in
      context.duration = 0.2
      animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
    }
  }

  func saveWindowPosition() {
    if let screenFrame = screen?.visibleFrame {
      let anchorX = frame.midX - screenFrame.minX
      let anchorY = frame.maxY - screenFrame.minY
      Defaults[.windowPosition] = NSPoint(x: anchorX / screenFrame.width, y: anchorY / screenFrame.height)
    }
  }

  func saveWindowFrame(frame: NSRect) {
    Defaults[.windowSize] = frame.size
    saveWindowPosition()
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    var finalFrameSize = frameSize
    finalFrameSize.width = max(finalFrameSize.width, Self.minimumListWidth)

    let minimumHeight = AppState.shared.popup.minimumHeight
    finalFrameSize.height = max(finalFrameSize.height, minimumHeight)

    if let visibleFrame = screen?.visibleFrame {
      finalFrameSize.width = min(finalFrameSize.width, visibleFrame.width)
      finalFrameSize.height = min(finalFrameSize.height, visibleFrame.height)
    }

    return finalFrameSize
  }

  func windowDidMove(_ notification: Notification) {
    AppState.shared.preview.reposition()
  }

  func windowWillStartLiveResize(_ notification: Notification) {
    contentView?.layoutSubtreeIfNeeded()
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    saveWindowFrame(frame: frame)
    AppState.shared.preview.reposition()
  }

  func windowDidResize(_ notification: Notification) {
    AppState.shared.preview.reposition()
  }

  // Close automatically when out of focus, e.g. outside click.
  override func resignKey() {
    super.resignKey()
    // Wait until AppKit has installed the next key window. Clicking or resizing
    // the detached preview must not dismiss either window.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.isPresented, !self.isKeyWindow else { return }
      let state = AppState.shared
      if NSApp.alertWindow == nil && !state.suppressPopupAutoClose && !state.preview.owns(NSApp.keyWindow) {
        self.close()
      }
    }
  }

  override func close() {
    super.close()
    let appState = AppState.shared
    appState.preview.close()
    appState.isSearchFocused = false
    appState.isEditingItem = false
    appState.navigator.isDragAndDropInProgress = false
    appState.navigator.isManualMultiSelect = false
    isPresented = false
    statusBarButton?.isHighlighted = false
    onClose()
  }

  // Allow text inputs inside the panel can receive focus
  override var canBecomeKey: Bool {
    return true
  }
}

private struct FloatingPanelRootView<Content: View>: View {
  @State private var appState = AppState.shared

  let content: Content
  let onWindowDragEnded: () -> Void

  var body: some View {
    content
      // The safe area is ignored because the title bar still interferes with the geometry
      .ignoresSafeArea()
      .gesture(
        DragGesture()
          .onEnded { _ in
            onWindowDragEnded()
          }
      )
  }
}
