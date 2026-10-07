import Defaults
import SwiftUI

// An NSPanel subclass that implements floating panel traits.
// https://stackoverflow.com/questions/46023769/how-to-show-a-window-without-stealing-focus-on-macos
class FloatingPanel<Content: View>: NSPanel, NSWindowDelegate {
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
    // SlideoutView fixes the list width between resize gestures. Do not let
    // NSHostingView turn that current width into the window's minimum size,
    // which would prevent the next gesture from making the window narrower.
    hostingView.sizingOptions = []
    contentView = hostingView
    contentMinSize = NSSize(
      width: AppState.shared.preview.minimumContentWidth,
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
      width: min(max(requestedSize.width, appState.preview.minimumContentWidth), visibleFrame?.width ?? .infinity),
      height: min(max(requestedSize.height, appState.popup.minimumHeight), visibleFrame?.height ?? .infinity)
    )
    appState.preview.contentWidth = finalSize.width
    // The slideout's width callback saves changes. A screen constraint is temporary,
    // so retain the user's requested size until they resize the window themselves.
    Defaults[.windowSize] = requestedSize
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

  func determinePreviewPlacement() {
    let preview = AppState.shared.preview
    guard !preview.state.isOpen else { return }
    let newSize = preview.computeSizeWithPreview(frame.size, state: .open)
    preview.placement = preview.computePlacement(window: self, for: newSize)
  }

  func saveWindowPosition() {
    if let screenFrame = screen?.visibleFrame {
      // Only store the size of the window without the preview
      let width = AppState.shared.preview.contentWidth

      let anchorX = frame.minX + width / 2 - screenFrame.minX
      let anchorY = frame.maxY - screenFrame.minY
      Defaults[.windowPosition] = NSPoint(x: anchorX / screenFrame.width, y: anchorY / screenFrame.height)
    }
  }

  func saveWindowFrame(frame: NSRect) {
    Defaults[.windowSize] = frame.size
    saveWindowPosition()
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    let preview = AppState.shared.preview

    if inLiveResize {
      startResizeIfNeeded()
    }

    var finalFrameSize = frameSize
    var minContent = preview.minimumContentWidth
    var minPreview = 0.0

    if inLiveResize && preview.resizingMode != .none {
      if preview.resizingMode == .content && preview.state == .open {
        minPreview = preview.slideoutWidth
      }
      if preview.resizingMode == .slideout {
        minPreview = preview.minimumSlideoutWidth
        minContent = preview.contentWidth
      }
    }
    finalFrameSize.width = max(finalFrameSize.width, minContent + minPreview)

    let minimumHeight = AppState.shared.popup.minimumHeight
    finalFrameSize.height = max(finalFrameSize.height, minimumHeight)

    if let visibleFrame = screen?.visibleFrame {
      finalFrameSize.width = min(finalFrameSize.width, visibleFrame.width)
      finalFrameSize.height = min(finalFrameSize.height, visibleFrame.height)
    }

    return finalFrameSize
  }

  private func startResizeIfNeeded() {
    let preview = AppState.shared.preview
    guard preview.resizingMode == .none else { return }

    let windowPoint = convertPoint(fromScreen: NSEvent.mouseLocation)
    let location: SlideoutPlacement = windowPoint.x <= frame.width / 2 ? .left : .right
    if location == preview.placement && preview.state == .open {
      preview.startResize(mode: .slideout)
    } else {
      preview.startResize(mode: .content)
    }
  }

  func windowWillMove(_ notification: Notification) {
    determinePreviewPlacement()
  }

  func windowDidMove(_ notification: Notification) {
    determinePreviewPlacement()
  }

  func windowWillStartLiveResize(_ notification: Notification) {
    AppState.shared.preview.cancelAutoOpen()
    // Release the fixed list/preview width before AppKit proposes a smaller
    // window size, instead of waiting for the first windowWillResize callback.
    startResizeIfNeeded()
    contentView?.layoutSubtreeIfNeeded()
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    let preview = AppState.shared.preview
    preview.endResize()
    var size = frame.size
    // Save the final list width, excluding the independently sized preview.
    size.width = preview.contentWidth
    saveWindowFrame(frame: NSRect(origin: frame.origin, size: size))
    preview.startAutoOpen()
  }

  func windowDidBecomeKey(_ notification: Notification) {
    AppState.shared.preview.enableAutoOpen()

    if AppState.shared.navigator.leadHistoryItem != nil {
      AppState.shared.preview.startAutoOpen()
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    AppState.shared.preview.disableAutoOpen()
  }

  // Close automatically when out of focus, e.g. outside click.
  override func resignKey() {
    super.resignKey()
    // Don't hide while a modal interaction from this panel is active.
    if NSApp.alertWindow == nil && !AppState.shared.suppressPopupAutoClose {
      close()
    }
  }

  override func close() {
    super.close()
    let appState = AppState.shared
    appState.preview.state = .closed
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
