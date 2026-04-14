//
//  AppleTranslationWindow.swift
//  TLingo
//
//  A hidden NSWindow that hosts the .translationTask() modifier on macOS.
//  Apple's Translation framework requires a proper NSWindowScene (not an NSPopover)
//  to present its UI. This window satisfies that requirement without being visible.
//

#if os(macOS)
    import AppKit
    import Combine
    import ShareCore
    import SwiftUI
    import Translation

    // MARK: - Bridge

    /// Coordinates Apple Translate requests between HomeViewModel and the hidden translation window.
    @MainActor
    final class AppleTranslationBridge: ObservableObject {
        static let shared = AppleTranslationBridge()

        /// Pending translation configuration. The hidden window view observes this.
        @Published var pendingConfig: TranslationSession.Configuration?

        /// Weak reference to the view model that owns the current Apple Translate request.
        weak var activeViewModel: HomeViewModel?

        private init() {}

        /// Called by HomeViewModel (via its appleTranslationRequestHandler closure) to trigger
        /// a translation through the hidden window.
        @available(macOS 14.4, *)
        func requestTranslation(
            source: Locale.Language?,
            target: TargetLanguageOption,
            for viewModel: HomeViewModel
        ) {
            activeViewModel = viewModel
            let targetLocale = target.localeLanguage
            Logger.debug("[AppleTranslationBridge] requestTranslation source=\(source?.languageCode?.identifier ?? "nil (auto)"), target=\(targetLocale.languageCode?.identifier ?? "unknown")")

            if pendingConfig != nil {
                pendingConfig?.invalidate()
                pendingConfig = nil
                Task { @MainActor in
                    self.pendingConfig = .init(source: source, target: targetLocale)
                }
            } else {
                pendingConfig = .init(source: source, target: targetLocale)
            }
        }

        /// Called by the hidden window view when a TranslationSession becomes available.
        @available(macOS 14.4, *)
        func sessionReady(_ session: TranslationSession) {
            Logger.debug("[AppleTranslationBridge] sessionReady, forwarding to activeViewModel=\(activeViewModel != nil)")
            activeViewModel?.executeAppleTranslation(session: session)
        }
    }

    // MARK: - Hidden Window View

    /// A zero-size view that holds the .translationTask() modifier.
    @available(macOS 14.4, *)
    struct AppleTranslationWindowView: View {
        @ObservedObject private var bridge = AppleTranslationBridge.shared

        var body: some View {
            Color.clear
                .frame(width: 1, height: 1)
                .translationTask(bridge.pendingConfig) { session in
                    Logger.debug("[AppleTranslationWindowView] .translationTask fired")
                    AppleTranslationBridge.shared.sessionReady(session)
                }
        }
    }

    // MARK: - Window Manager

    /// Manages the lifecycle of the hidden translation window.
    @MainActor
    final class AppleTranslationWindowManager {
        static let shared = AppleTranslationWindowManager()

        private var window: NSWindow?
        private var viewModelObserver: NSObjectProtocol?
        /// ViewModels that registered before the window was ready.
        private var pendingViewModels: [WeakRef<HomeViewModel>] = []

        private init() {
            // Start listening immediately so viewModels that register before setup() don't get lost.
            viewModelObserver = NotificationCenter.default.addObserver(
                forName: .appleTranslationViewModelRegister,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let viewModel = notification.userInfo?["viewModel"] as? HomeViewModel
                else { return }
                Task { @MainActor in
                    if self.window != nil {
                        if #available(macOS 14.4, *) { self.registerViewModel(viewModel) }
                    } else {
                        self.pendingViewModels.append(WeakRef(viewModel))
                        Logger.debug("[AppleTranslationWindowManager] Queued viewModel (window not ready yet)")
                    }
                }
            }
        }

        func setup() {
            guard window == nil else { return }
            guard #available(macOS 14.4, *) else { return }

            let hostingView = NSHostingView(rootView: AppleTranslationWindowView())
            hostingView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)

            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.contentView = hostingView
            win.isReleasedWhenClosed = false
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            win.level = .floating
            win.isOpaque = false
            win.backgroundColor = .clear
            win.ignoresMouseEvents = true
            win.hasShadow = false
            win.alphaValue = 0
            // Move far off-screen so it's part of a real NSWindowScene but completely invisible.
            // Must be shown (orderFront) for .translationTask to get a valid session.
            win.setFrameOrigin(NSPoint(x: -9999, y: -9999))
            win.orderFront(nil)

            self.window = win
            Logger.debug("[AppleTranslationWindowManager] Hidden translation window created")

            // Register any viewModels that arrived before we were ready.
            for ref in pendingViewModels {
                if let vm = ref.value { registerViewModel(vm) }
            }
            pendingViewModels.removeAll()
        }

        func teardown() {
            if let observer = viewModelObserver {
                NotificationCenter.default.removeObserver(observer)
                viewModelObserver = nil
            }
            window?.close()
            window = nil
            pendingViewModels.removeAll()
        }

        /// Wires the bridge request handler into a HomeViewModel instance.
        @available(macOS 14.4, *)
        private func registerViewModel(_ viewModel: HomeViewModel) {
            viewModel.appleTranslationRequestHandler = { [weak viewModel] source, target in
                guard let viewModel else { return }
                AppleTranslationBridge.shared.requestTranslation(
                    source: source,
                    target: target,
                    for: viewModel
                )
            }
            Logger.debug("[AppleTranslationWindowManager] Registered viewModel \(ObjectIdentifier(viewModel))")
        }
    }

    // MARK: - WeakRef helper

    private final class WeakRef<T: AnyObject> {
        weak var value: T?
        init(_ value: T) { self.value = value }
    }
#endif
