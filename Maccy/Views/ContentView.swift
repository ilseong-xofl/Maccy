import SwiftData
import SwiftUI

enum ClipboardKeyboardFocus: Hashable {
  case list
  case search
}

struct ContentView: View {
  @State private var appState = AppState.shared
  @State private var modifierFlags = ModifierFlags()
  @State private var scenePhase: ScenePhase = .background

  @FocusState private var keyboardFocus: ClipboardKeyboardFocus?

  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView()
      }

      KeyHandlingView(searchQuery: $appState.history.searchQuery, keyboardFocus: $keyboardFocus) {
        VStack(spacing: 0) {
          VStack(spacing: 0) {
            HeaderView(keyboardFocus: $keyboardFocus)

            VStack(alignment: .leading, spacing: 0) {
              HistoryListView(
                searchQuery: $appState.history.searchQuery,
                keyboardFocus: $keyboardFocus
              )

              FooterView(footer: appState.footer)
            }
            // Switch filters immediately, without animating all rows and the footer together.
            .animation(nil, value: appState.history.filter)
            .animation(.default.speed(3), value: appState.history.items)
            .animation(
              .default.speed(3),
              value: appState.history.pasteStack?.id
            )
            .padding(.horizontal, Popup.horizontalPadding)
            .focusable()
            .focusEffectDisabled()
            .focused($keyboardFocus, equals: .list)
          }
          .frame(minHeight: 0)
          .layoutPriority(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .task {
        try? await appState.history.load()
        keyboardFocus = .list
      }
    }
    .overlay(alignment: .bottomTrailing) {
      WindowResizeIndicator()
        .padding(3)
    }
    .overlay {
      if appState.isConfirmingQuit {
        Color.black.opacity(0.18)
          .ignoresSafeArea()
          .accessibilityHidden(true)
      }
    }
    .animation(.easeInOut(duration: 0.2), value: appState.searchVisible)
    .environment(appState)
    .environment(modifierFlags)
    .environment(\.scenePhase, scenePhase)
    .onChange(of: appState.isEditingItem) { _, isEditingItem in
      if !isEditingItem {
        keyboardFocus = .list
      }
    }
    .onChange(of: keyboardFocus) { _, focus in
      appState.isSearchFocused = focus == .search
    }
    .onChange(of: appState.keyboardFocusRequestID) { _, _ in
      if !appState.isEditingItem {
        keyboardFocus = appState.requestedKeyboardFocus
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        keyboardFocus = .list
      }
    }
    // FloatingPanel is not a scene, so let's implement custom scenePhase..
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
      guard !appState.isEditingItem else { return }

      if let window = $0.object as? NSWindow,
         window === appState.appDelegate?.panel || appState.preview.owns(window) {
        scenePhase = .active
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
      guard !appState.isEditingItem, !appState.isConfirmingQuit else { return }

      // AppKit reports resignation before the next key window is established.
      // Treat list + preview as one interaction so preview clicks don't clear search.
      DispatchQueue.main.async {
        guard !appState.isConfirmingQuit else { return }
        if appState.appDelegate?.panel.isKeyWindow != true && appState.preview.window?.isKeyWindow != true {
          scenePhase = .background
        }
      }
    }
  }
}

#Preview {
  ContentView()
    .environment(\.locale, .init(identifier: "en"))
    .modelContainer(Storage.shared.container)
}
