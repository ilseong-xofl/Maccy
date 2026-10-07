import AppKit
import Defaults
import Observation
import SwiftUI

@Observable
final class DetachedPreviewController: NSObject, NSWindowDelegate {
  nonisolated static let defaultSize = NSSize(width: 520, height: 600)
  nonisolated static let minimumSize = NSSize(width: 280, height: 240)
  nonisolated static let windowGap: CGFloat = 8

  struct ContentMetrics: Equatable {
    let itemID: UUID
    let imageSize: NSSize?
    let imageWidth: CGFloat
    let nonImageHeight: CGFloat
    var imageIndex: Int = 0
    var presentationID: UUID?
  }

  private(set) var isVisible = false
  private(set) var selectedImageIndex = 0
  private(set) var presentationID = UUID()
  @ObservationIgnored private var previewedItemID: UUID?
  @ObservationIgnored private(set) var window: NSPanel?
  @ObservationIgnored private(set) var sessionSize = DetachedPreviewController.defaultSize
  @ObservationIgnored private var automaticallyFitsImage = true
  @ObservationIgnored private var contentMetrics: ContentMetrics?
  @ObservationIgnored private var directionObservation: Task<Void, Never>?
  @ObservationIgnored private var eventMonitor: Any?

  override init() {
    super.init()
    directionObservation = Task { [weak self] in
      for await _ in Defaults.updates(.previewDirection, initial: false) {
        guard let self else { return }
        reposition()
      }
    }
  }

  isolated deinit {
    directionObservation?.cancel()
    if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    window?.delegate = nil
    window?.orderOut(nil)
  }

  func togglePreview() {
    guard !AppState.shared.isEditingItem else { return }
    if isVisible {
      close(restoreListFocus: true)
      return
    }
    guard canPreviewSelection, let anchor = listWindow, anchor.isVisible else { return }
    if window == nil { makeWindow() }
    sessionSize = Self.defaultSize
    automaticallyFitsImage = true
    resetImageSelection()
    presentationID = UUID()
    isVisible = true
    reposition()
    window?.makeKeyAndOrderFront(nil)
  }

  func close(restoreListFocus: Bool = false) {
    guard isVisible else { return }
    isVisible = false
    window?.orderOut(nil)
    if restoreListFocus, let anchor = listWindow, anchor.isVisible {
      AppState.shared.requestKeyboardFocus(.list)
      anchor.makeKeyAndOrderFront(nil)
    }
  }

  func selectionDidChange() {
    guard isVisible else { return }
    if !canPreviewSelection {
      close(restoreListFocus: window?.isKeyWindow == true)
      return
    }
    if previewedItemID != AppState.shared.navigator.leadHistoryItem?.id { resetImageSelection() }
    reposition()
  }

  @discardableResult
  func navigateImages(by offset: Int) -> Bool {
    guard isVisible, !AppState.shared.isEditingItem,
          let item = AppState.shared.navigator.leadHistoryItem, item.previewImageCount > 1 else { return false }
    if previewedItemID != item.id { resetImageSelection() }
    let nextIndex = min(max(selectedImageIndex + offset, 0), item.previewImageCount - 1)
    if nextIndex != selectedImageIndex {
      contentMetrics = nil
      selectedImageIndex = nextIndex
    }
    return true
  }

  private func resetImageSelection() {
    previewedItemID = AppState.shared.navigator.leadHistoryItem?.id
    selectedImageIndex = 0
    contentMetrics = nil
  }

  func contentLayoutDidChange(_ metrics: ContentMetrics) {
    guard metrics.itemID == AppState.shared.navigator.leadHistoryItem?.id,
          metrics.imageIndex == selectedImageIndex,
          metrics.presentationID == nil || metrics.presentationID == presentationID else { return }
    contentMetrics = metrics
    reposition()
  }

  func reposition() {
    guard isVisible, let window, !window.inLiveResize, let anchor = listWindow,
          let screen = anchor.screen ?? NSScreen.main else { return }
    let visibleFrame = screen.visibleFrame
    window.minSize = NSSize(width: min(Self.minimumSize.width, visibleFrame.width),
                            height: min(Self.minimumSize.height, visibleFrame.height))
    window.maxSize = visibleFrame.size
    let maximumFrame = Self.placement(anchorFrame: anchor.frame, visibleFrame: visibleFrame,
                                     requestedSize: sessionSize, direction: Defaults[.previewDirection])
    var requestedSize = maximumFrame.size
    let nativeChromeHeight = maximumFrame.height - window.contentRect(forFrameRect: maximumFrame).height
    if automaticallyFitsImage, let metrics = contentMetrics,
       metrics.itemID == AppState.shared.navigator.leadHistoryItem?.id,
       metrics.imageIndex == selectedImageIndex,
       abs(metrics.imageWidth - (maximumFrame.width - SlideoutContentView.horizontalPadding * 2)) < 1 {
      requestedSize = Self.automaticSize(imageSize: metrics.imageSize, maximumSize: maximumFrame.size,
                                         imageWidth: metrics.imageWidth,
                                         nonImageHeight: metrics.nonImageHeight + nativeChromeHeight)
    }
    let frame = Self.placement(anchorFrame: anchor.frame, visibleFrame: visibleFrame,
                               requestedSize: requestedSize, direction: Defaults[.previewDirection])
    // Auto-fit and screen constraints never change the current session's baseline size.
    if window.frame != frame { window.setFrame(frame, display: true) }
  }

  func owns(_ candidate: NSWindow?) -> Bool {
    guard let candidate, let window else { return false }
    if candidate === window { return true }
    var parent = candidate.sheetParent
    while let current = parent {
      if current === window { return true }
      parent = current.sheetParent
    }
    return false
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard !AppState.shared.isEditingItem, sender.attachedSheet == nil else { return false }
    close(restoreListFocus: true)
    return false
  }

  func windowWillStartLiveResize(_ notification: Notification) {
    guard let resizedWindow = notification.object as? NSWindow, resizedWindow === window else { return }
    automaticallyFitsImage = false
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    guard let resizedWindow = notification.object as? NSWindow, resizedWindow === window else { return }
    sessionSize = resizedWindow.frame.size
    reposition()
  }

  func windowDidResignKey(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self, isVisible else { return }
      let appState = AppState.shared
      guard !appState.suppressPopupAutoClose, NSApp.modalWindow == nil,
            window?.attachedSheet == nil, listWindow?.attachedSheet == nil else { return }
      if NSApp.keyWindow === listWindow || owns(NSApp.keyWindow) { return }
      listWindow?.close()
    }
  }

  private var listWindow: NSWindow? { AppState.shared.appDelegate?.panel }

  private var canPreviewSelection: Bool {
    let appState = AppState.shared
    return appState.navigator.leadHistoryItem != nil
      || (appState.navigator.pasteStackSelected && appState.history.pasteStack != nil)
  }

  private func makeWindow() {
    let panel = DetachedPreviewPanel(contentRect: NSRect(origin: .zero, size: Self.defaultSize),
                                     styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
    panel.title = NSLocalizedString("ShowPreview", tableName: "GeneralSettings", comment: "")
      .trimmingCharacters(in: CharacterSet(charactersIn: ":： "))
    panel.identifier = NSUserInterfaceItemIdentifier("MaccyPreview.detached-preview")
    panel.delegate = self
    panel.isReleasedWhenClosed = false
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = false
    panel.level = .statusBar
    panel.collectionBehavior = [.auxiliary, .moveToActiveSpace, .fullScreenAuxiliary]
    panel.animationBehavior = .none
    let hostingView = NSHostingView(rootView: SlideoutContentView()
      .environment(AppState.shared)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, maxHeight: .infinity))
    hostingView.sizingOptions = []
    panel.contentView = hostingView
    window = panel
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, isVisible, owns(event.window), !AppState.shared.isEditingItem,
            window?.attachedSheet == nil, NSApp.modalWindow == nil else { return event }
      if let inputClient = event.window?.firstResponder as? NSTextInputClient, inputClient.hasMarkedText() {
        return event
      }
      switch KeyChord(event) {
      case .focusSearch:
        listWindow?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { AppState.shared.requestKeyboardFocus(.search) }
        return nil
      case .spacePreview, .close, .togglePreview:
        close(restoreListFocus: true)
        return nil
      case .previousPreviewImage, .nextPreviewImage:
        if let editor = event.window?.firstResponder as? NSTextView, editor.isEditable { return event }
        return navigateImages(by: KeyChord(event) == .nextPreviewImage ? 1 : -1) ? nil : event
      case .moveToNext:
        AppState.shared.navigator.highlightNext()
        return nil
      case .moveToPrevious:
        AppState.shared.navigator.highlightPrevious()
        return nil
      case .moveToFirst:
        AppState.shared.navigator.highlightFirst()
        return nil
      case .moveToLast:
        AppState.shared.navigator.highlightLast()
        return nil
      case .pinOrUnpin:
        AppState.shared.togglePin()
        return nil
      case .deleteCurrentItem:
        if AppState.shared.navigator.pasteStackSelected {
          AppState.shared.removePasteStack()
        } else {
          AppState.shared.deleteSelection()
        }
        return nil
      case .selectCurrentItem:
        AppState.shared.select(flags: .currentModifierFlags)
        return nil
      case .openPreferences:
        AppState.shared.openPreferences()
        return nil
      default:
        return event
      }
    }
  }

  /// Width is the baseline width, including when a small image must be enlarged.
  nonisolated static func automaticSize(imageSize: NSSize?, maximumSize: NSSize,
                                        imageWidth: CGFloat, nonImageHeight: CGFloat) -> NSSize {
    guard let imageSize, imageSize.width.isFinite, imageSize.height.isFinite,
          imageSize.width > 0, imageSize.height > 0,
          imageWidth.isFinite, imageWidth > 0,
          nonImageHeight.isFinite, nonImageHeight >= 0 else { return maximumSize }
    let fittedHeight = ceil(imageWidth * (imageSize.height / imageSize.width) + nonImageHeight)
    return NSSize(width: maximumSize.width,
                  height: min(maximumSize.height, max(minimumSize.height, fittedHeight)))
  }

  /// Computes an on-screen frame without changing the requested size or the list window.
  nonisolated static func placement(anchorFrame: NSRect, visibleFrame: NSRect,
                                     requestedSize: NSSize, direction: PreviewDirection) -> NSRect {
    let screen = visibleFrame.standardized
    guard screen.width > 0, screen.height > 0 else { return NSRect(origin: screen.origin, size: .zero) }
    let desiredWidth = requestedSize.width.isFinite ? requestedSize.width : minimumSize.width
    let desiredHeight = requestedSize.height.isFinite ? requestedSize.height : minimumSize.height
    let width = min(max(desiredWidth, minimumSize.width), screen.width)
    let height = min(max(desiredHeight, minimumSize.height), screen.height)
    let leftSpace = max(0, min(anchorFrame.minX - windowGap, screen.maxX) - screen.minX)
    let rightSpace = max(0, screen.maxX - max(anchorFrame.maxX + windowGap, screen.minX))
    let preferredSpace = direction == .right ? rightSpace : leftSpace
    let oppositeSpace = direction == .right ? leftSpace : rightSpace
    let useRight: Bool
    if preferredSpace >= width {
      useRight = direction == .right
    } else if oppositeSpace >= width {
      useRight = direction != .right
    } else if rightSpace == leftSpace {
      useRight = direction == .right
    } else {
      useRight = rightSpace > leftSpace
    }
    // Keep the preview width stable. If neither side fits, overlap the list within the screen.
    let finalWidth = width
    let proposedX = useRight ? anchorFrame.maxX + windowGap : anchorFrame.minX - windowGap - finalWidth
    let x = min(max(proposedX, screen.minX), screen.maxX - finalWidth)
    let y = min(max(anchorFrame.maxY - height, screen.minY), screen.maxY - height)
    return NSRect(x: x, y: y, width: finalWidth, height: height)
  }
}

private final class DetachedPreviewPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
