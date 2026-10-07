import SwiftUI

extension View {
  /// Marks this view as a button that responds to both a mouse tap and VoiceOver activation
  /// (VO-Space) with the same action, so the two input methods never diverge from each other.
  func buttonAction(_ action: @escaping () -> Void) -> some View {
    self
      .accessibilityAddTraits(.isButton)
      .accessibilityAction(.default, action)
      .onTapGesture(perform: action)
  }

  /// Clipboard rows select on press, activate on double click, and drag the window.
  func clipboardItemInteraction(
    onSelect: @escaping (NSEvent.ModifierFlags) -> Void,
    onActivate: @escaping (NSEvent.ModifierFlags) -> Void,
    onToggleFavorite: (() -> Void)? = nil,
    favoriteHitSize: CGSize = CGSize(width: 27, height: 27)
  ) -> some View {
    self
      .overlay {
        ClipboardItemMouseCapture(onSelect: onSelect, onActivate: onActivate,
                                  onToggleFavorite: onToggleFavorite, favoriteHitSize: favoriteHitSize)
          .accessibilityHidden(true)
      }
      .accessibilityAddTraits(.isButton)
      .accessibilityAction(.default) { onActivate(.currentModifierFlags) }
  }
}

private struct ClipboardItemMouseCapture: NSViewRepresentable {
  var onSelect: (NSEvent.ModifierFlags) -> Void
  var onActivate: (NSEvent.ModifierFlags) -> Void
  var onToggleFavorite: (() -> Void)?
  var favoriteHitSize: CGSize

  func makeNSView(context: Context) -> ClipboardItemMouseView {
    let view = ClipboardItemMouseView()
    view.setAccessibilityElement(false)
    updateNSView(view, context: context)
    return view
  }

  func updateNSView(_ view: ClipboardItemMouseView, context: Context) {
    view.onSelect = onSelect
    view.onActivate = onActivate
    view.onToggleFavorite = onToggleFavorite
    view.favoriteHitSize = favoriteHitSize
  }
}

class ClipboardItemMouseView: NSView {
  var onSelect: (NSEvent.ModifierFlags) -> Void = { _ in }
  var onActivate: (NSEvent.ModifierFlags) -> Void = { _ in }
  var onToggleFavorite: (() -> Void)?
  var favoriteHitSize = CGSize(width: 27, height: 27)
  private var mouseDownEvent: NSEvent?
  private var pressedFavorite = false

  private var favoriteHitRect: CGRect? {
    guard onToggleFavorite != nil else { return nil }
    let width = min(max(favoriteHitSize.width, 0), bounds.width)
    let height = min(max(favoriteHitSize.height, 0), bounds.height)
    guard width > 0, height > 0 else { return nil }
    return CGRect(x: bounds.minX, y: bounds.midY - height / 2, width: width, height: height)
      .intersection(visibleRect)
  }

  override var mouseDownCanMoveWindow: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    mouseDownEvent = event
    let point = convert(event.locationInWindow, from: nil)
    pressedFavorite = favoriteHitRect?.contains(point) == true
    window?.makeKey()
    if !pressedFavorite { onSelect(normalizedFlags(event)) }
  }

  override func mouseDragged(with event: NSEvent) {
    guard let original = mouseDownEvent else { return }
    let distance = hypot(event.locationInWindow.x - original.locationInWindow.x,
                         event.locationInWindow.y - original.locationInWindow.y)
    guard distance >= 4 else { return }
    // AppKit can consume the final mouse-up when taking over a native window drag.
    mouseDownEvent = nil
    let wasFavorite = pressedFavorite
    pressedFavorite = false
    // A drag beginning on the star cancels that button press instead of moving the window.
    if !wasFavorite { beginWindowDrag(with: original) }
  }

  func beginWindowDrag(with event: NSEvent) {
    window?.performDrag(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    guard let original = mouseDownEvent else { return }
    mouseDownEvent = nil
    let wasFavorite = pressedFavorite
    pressedFavorite = false
    let point = convert(event.locationInWindow, from: nil)
    let overFavorite = favoriteHitRect?.contains(point) == true
    if wasFavorite {
      if overFavorite { onToggleFavorite?() }
      return
    }
    guard original.clickCount == 2, event.clickCount == 2, visibleRect.contains(point),
          !overFavorite else { return }
    onActivate(normalizedFlags(event))
  }

  override func scrollWheel(with event: NSEvent) {
    nextResponder?.scrollWheel(with: event)
  }

  private func normalizedFlags(_ event: NSEvent) -> NSEvent.ModifierFlags {
    event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])
  }
}
