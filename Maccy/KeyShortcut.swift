import AppKit.NSEvent
import Defaults
import Sauce

struct KeyShortcut: Identifiable {
  static func create(character: String) -> [KeyShortcut] {
    let key = Key(character: character, virtualKeyCode: nil)
    // Keep existing f pins usable without advertising the now-reserved ⌘F search shortcut.
    if character.lowercased() == "f" {
      return [KeyShortcut(key: key, modifierFlags: [.option])]
    }
    let modified = [
      KeyShortcut(key: key),
      KeyShortcut(key: key, modifierFlags: [.option]),
      KeyShortcut(key: key, modifierFlags: [Defaults[.pasteByDefault] ? .command : .option, .shift])
    ]
    if isCopyDigit(character) {
      return [KeyShortcut(key: key, modifierFlags: [])] + modified
    }
    return modified
  }

  static func isCopyDigit(_ character: String) -> Bool {
    character.count == 1 && "123456789".contains(character)
  }

  static func normalizedModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
    flags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
  }

  let id = UUID()

  var key: Key?
  var modifierFlags: NSEvent.ModifierFlags = [.command]

  var description: String {
    guard let key, let character = Sauce.shared.currentASCIICapableCharacter(
      for: Int(Sauce.shared.keyCode(for: key)),
      modifiers: .cocoa([])
    ) else {
      return ""
    }

    return "\(modifierFlags.description)\(character.capitalized)"
  }

  func isVisible(_ all: [KeyShortcut], _ pressedModifierFlags: NSEvent.ModifierFlags) -> Bool {
    let flags = Self.normalizedModifiers(pressedModifierFlags)
    let visible = all.first { $0.modifierFlags == flags }
      ?? all.first { $0.modifierFlags.isEmpty }
      ?? all.first { $0.modifierFlags == [.command] }
      ?? all.first
    return visible?.id == id
  }
}
