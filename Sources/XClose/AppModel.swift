import AppKit
import Combine
import XCloseCore

/// Owns the components and reconciles them into one explicit operational state.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: OperationalState = .starting
    @Published private(set) var tapStatus: TapStatus = .stopped

    let policyStore: ApplicationPolicyStore
    let permissions: PermissionManager
    let lifecycle: ApplicationLifecycleMonitor
    let diagnostics: DiagnosticsStore
    let launchAtLogin: LaunchAtLoginManager
    let inspector: ClickInspector

    private let interceptor: MouseEventInterceptor
    private let quitCoordinator: QuitCoordinator
    private var tapHealth = TapHealthMonitor()
    private var cancellables: Set<AnyCancellable> = []
    private var policy: ApplicationPolicy
    private var startRetryScheduled = false

    init() {
        policyStore = ApplicationPolicyStore()
        permissions = PermissionManager()
        lifecycle = ApplicationLifecycleMonitor()
        diagnostics = DiagnosticsStore()
        launchAtLogin = LaunchAtLoginManager()
        inspector = ClickInspector()
        interceptor = MouseEventInterceptor(inspector: inspector)
        quitCoordinator = QuitCoordinator(diagnostics: diagnostics)
        policy = policyStore.policy()
    }

    func start() {
        quitCoordinator.currentEligibility = { [weak self] app in
            self?.policy.eligibility(of: app) ?? .ineligible(.selfApp)
        }
        quitCoordinator.hidesWhileQuitting = { [weak self] in self?.policyStore.hidesWhileQuitting ?? false }
        interceptor.onNotice = { [weak self] notice in
            MainActor.assumeIsolated { self?.handle(notice) }
        }
        lifecycle.onTerminate = { [weak self] pid in self?.quitCoordinator.applicationTerminated(pid: pid) }
        lifecycle.onSystemResume = { [weak self] in self?.systemResumed() }

        lifecycle.start()
        permissions.startMonitoring()

        policyStore.$isEnabled.dropFirst().removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.reconcile() } }
            .store(in: &cancellables)
        policyStore.$exclusions.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.policyChanged() } }
            .store(in: &cancellables)
        permissions.$isAccessibilityTrusted.dropFirst().removeDuplicates()
            .sink { [weak self] trusted in DispatchQueue.main.async { self?.permissionChanged(trusted: trusted) } }
            .store(in: &cancellables)
        lifecycle.$apps.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.pushConfiguration() } }
            .store(in: &cancellables)

        reconcile()
    }

    func shutdown() {
        interceptor.updateConfiguration { $0.isActive = false }
        interceptor.stop()
    }

    // MARK: - User actions

    var isEnabled: Bool {
        get { policyStore.isEnabled }
        set { policyStore.isEnabled = newValue }
    }

    func toggleEnabled() {
        policyStore.isEnabled.toggle()
    }

    /// Clears a degraded state and tries the event tap again.
    func retryInterception() {
        tapHealth.reset()
        startRetryScheduled = false
        interceptor.stop()
        tapStatus = .stopped
        permissions.refresh()
        reconcile()
    }

    /// Runs the detection pipeline at the current pointer location without acting
    /// on the result. Used by Diagnostics to check compatibility with an app.
    func testPointerTarget(completion: @escaping (ClickEvaluation) -> Void) {
        let point = CGEvent(source: nil)?.location ?? .zero
        let policy = self.policy
        var configuration = InterceptorConfiguration()
        configuration.isActive = true
        configuration.apps = lifecycle.apps.mapValues { AppEntry(descriptor: $0, eligibility: policy.eligibility(of: $0)) }
        let inspector = self.inspector
        DispatchQueue.global(qos: .userInitiated).async {
            let result = inspector.evaluate(point: point, modifiers: [], isSynthetic: false,
                                            configuration: configuration, isPenalized: { _ in false })
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Reconciliation

    private func reconcile() {
        let enabled = policyStore.isEnabled
        let trusted = permissions.isAccessibilityTrusted
        switch TapPlanner.action(isEnabled: enabled, hasAccessibility: trusted, tap: tapStatus) {
        case .start:
            tapStatus = .starting
            updateState()
            if interceptor.start() {
                tapStatus = .running
                diagnostics.record(.tap, "Event tap started")
            } else {
                tapStatus = .failedToStart
                diagnostics.record(.tap, "Event tap could not be created")
                scheduleStartRetry()
            }
        case .stop:
            interceptor.updateConfiguration { $0.isActive = false }
            interceptor.stop()
            tapStatus = .stopped
            quitCoordinator.reset()
            diagnostics.record(.tap, "Event tap stopped")
        case .none:
            break
        }
        updateState()
    }

    /// Tap creation can fail briefly while a fresh Accessibility grant propagates.
    /// One delayed retry; after that the degraded state waits for the user.
    private func scheduleStartRetry() {
        guard !startRetryScheduled else { return }
        startRetryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.tapStatus == .failedToStart else { return }
                self.tapStatus = .stopped
                self.reconcile()
            }
        }
    }

    private func updateState() {
        let newState = OperationalState.derive(isEnabled: policyStore.isEnabled,
                                               hasAccessibility: permissions.isAccessibilityTrusted,
                                               tap: tapStatus)
        if newState != state {
            state = newState
            diagnostics.record(.state, newState.title)
        }
        pushConfiguration()
    }

    private func policyChanged() {
        policy = policyStore.policy()
        pushConfiguration()
    }

    private func pushConfiguration() {
        let active = state.interceptsClicks
        let policy = self.policy
        let entries = lifecycle.apps.mapValues { AppEntry(descriptor: $0, eligibility: policy.eligibility(of: $0)) }
        interceptor.updateConfiguration {
            $0.isActive = active
            $0.apps = entries
        }
    }

    private func permissionChanged(trusted: Bool) {
        diagnostics.record(.permission, trusted ? "Accessibility granted" : "Accessibility revoked")
        // A tap that failed before trust propagated deserves another attempt.
        if trusted, tapStatus == .failedToStart {
            tapStatus = .stopped
            startRetryScheduled = false
        }
        reconcile()
    }

    private func systemResumed() {
        permissions.refresh()
        if tapStatus == .running {
            interceptor.reenableIfNeeded()
        } else if tapStatus == .failedToStart || tapStatus == .unstable {
            tapHealth.reset()
            tapStatus = .stopped
        }
        reconcile()
    }

    private func handle(_ notice: MouseEventInterceptor.Notice) {
        switch notice {
        case .evaluated(let evaluation):
            diagnostics.record(evaluation)
        case .quitRequested(let click):
            guard state.interceptsClicks else { return }
            quitCoordinator.requestQuit(for: click)
        case .releasedOutside(let click):
            diagnostics.record(.releasedOutside, "\(click.appName): released away from red ×, nothing done")
        case .tapDisabled(let byTimeout):
            diagnostics.recordTapDisabled(byTimeout: byTimeout)
            if byTimeout, tapHealth.recordTimeout(now: ProcessInfo.processInfo.systemUptime) {
                // Pause safely rather than flap: normal input is restored at once.
                interceptor.updateConfiguration { $0.isActive = false }
                interceptor.stop()
                tapStatus = .unstable
                updateState()
            }
        case .unknownApplication(let pid):
            lifecycle.refresh(pid: pid)
        case .accessibilityUnavailable:
            permissions.refresh()
        }
    }
}
