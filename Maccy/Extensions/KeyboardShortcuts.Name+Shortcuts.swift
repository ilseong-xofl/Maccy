import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let popup = Self("popup", initial: Shortcut(.c, modifiers: [.command, .shift]))
  static let pin = Self("pin", initial: Shortcut(.p, modifiers: [.option]))
  static let delete = Self("delete", initial: Shortcut(.delete, modifiers: []))
  static let togglePreview = Self("togglePreview", initial: Shortcut(.space, modifiers: [.control]))

  static func migrateDeleteShortcutToBackspace() {
    guard delete.shortcut == Shortcut(.delete, modifiers: [.option]) else { return }
    delete.shortcut = delete.initialShortcut
  }
}
