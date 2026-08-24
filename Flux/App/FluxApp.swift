import SwiftUI
import FirebaseCore

@main
struct FluxApp: App {
    @StateObject private var env = AppEnvironment.create()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env.backend)
                .environmentObject(env.lock)
                .environmentObject(env.accountManager)
                .environmentObject(env.l10n)
                .environmentObject(env.theme)
                .environmentObject(env)
                .preferredColorScheme(env.theme.mode.colorScheme)
                .tint(FluxColors.blue)
                .task {
                    await env.start()
                }
        }
    }
}

/// Dependency container — builds the backend (Firestore when a real
/// Firebase config is present, local-first otherwise) and the supporting
/// controllers. The iOS counterpart of `main.dart`'s bootstrap.
@MainActor
final class AppEnvironment: ObservableObject {
    let backend: LocalBackend
    let lock: LockController
    let accountManager: AccountManager
    let l10n: FluxL10n
    let theme: ThemeController

    /// True once the persisted state has been restored.
    @Published private(set) var isReady = false

    private var started = false

    private init(backend: LocalBackend, lock: LockController, accountManager: AccountManager, l10n: FluxL10n, theme: ThemeController) {
        self.backend = backend
        self.lock = lock
        self.accountManager = accountManager
        self.l10n = l10n
        self.theme = theme
    }

    /// Creates the container. Firebase is configured synchronously (a
    /// missing GoogleService-Info.plist falls back to the offline local
    /// mode); the heavier state restore happens in [start].
    static func create() -> AppEnvironment {
        var projectId: String?
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            if FirebaseApp.app() == nil {
                FirebaseApp.configure()
            }
            projectId = FirebaseApp.app()?.options.projectID
        }

        let useRemote: Bool
        if let projectId, !projectId.isEmpty, projectId != LocalBackend.placeholderProject {
            useRemote = true
        } else {
            useRemote = false
        }

        let backend: LocalBackend = useRemote ? FirestoreBackend() : LocalBackend()
        let lock = LockController()
        let accountManager = AccountManager()
        accountManager.initManager()
        let l10n = FluxL10n(backend.prefs.language)
        let theme = ThemeController(backend.prefs.themeMode)
        return AppEnvironment(
            backend: backend,
            lock: lock,
            accountManager: accountManager,
            l10n: l10n,
            theme: theme
        )
    }

    /// Restores persisted state, then applies the lock screen when
    /// app-lock is enabled.
    func start() async {
        guard !started else { return }
        started = true

        await backend.initBackend()

        accountManager.initManager()
        l10n.setLanguage(backend.prefs.language)
        theme.setMode(ThemeController.Mode(rawValue: backend.prefs.themeMode) ?? .light)

        if backend.privacy.appLockEnabled {
            lock.lock()
        }

        isReady = true
    }
}

/// Routes the user through the setup flow:
/// onboarding → smart auth → (lock) → messenger. Fully declarative — each
/// step mutates backend state and the root cross-fades to the next screen.
struct RootView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var lock: LockController
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var theme: ThemeController
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            FluxColors.background.ignoresSafeArea()
            if !env.isReady {
                splash
            } else {
                switch stage {
                case .onboarding:
                    OnboardingView()
                        .transition(stageTransition)
                case .auth:
                    SmartAuthView()
                        .transition(stageTransition)
                case .lock:
                    LockScreenView()
                        .transition(stageTransition)
                case .home:
                    HomeShellView()
                        .transition(stageTransition)
                }
            }
        }
        // The theme controller is observed here directly, so switching
        // light/dark/system re-renders the root and applies immediately.
        .preferredColorScheme(theme.mode.colorScheme)
        .animation(FluxMotion.slowDecelAnimation, value: stage)
        .onChange(of: scenePhase) { phase in
            // Re-lock when the app leaves the foreground.
            if phase == .inactive || phase == .background {
                if backend.privacy.appLockEnabled {
                    lock.lock()
                }
            }
        }
    }

    private var splash: some View {
        VStack(spacing: 18) {
            FluxLogoMark(size: 72, animate: true)
            Text("Flux")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(FluxColors.textPrimary)
        }
    }

    private enum Stage: Equatable {
        case onboarding, auth, lock, home
    }

    private var stage: Stage {
        if !backend.onboarded { return .onboarding }
        guard backend.me != nil else { return .auth }
        if backend.privacy.appLockEnabled && lock.locked { return .lock }
        return .home
    }

    private var stageTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 1.03))
    }
}
