#if os(iOS)
import SwiftUI
import UIKit

final class AppearanceObservationView: UIView {
    var onChange: ((ColorScheme) -> Void)?
    private weak var observedScene: UIWindowScene?
    private var registration: (any UITraitChangeRegistration)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAppearance),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func refreshAppearance() {
        if let scene = window?.windowScene { publish(scene) }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        observeScene()
    }

    func observeScene() {
        guard let scene = window?.windowScene, scene !== observedScene else { return }
        if let observedScene, let registration {
            observedScene.unregisterForTraitChanges(registration)
        }
        observedScene = scene
        registration = scene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (scene: UIWindowScene, _: UITraitCollection) in
            self?.publish(scene)
        }
        publish(scene)
    }

    private func publish(_ scene: UIWindowScene) {
        // SwiftUI also overrides scene traits for preferredColorScheme. The screen
        // retains the system appearance, independently of website status-bar contrast.
        let scheme: ColorScheme = scene.screen.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        Task { @MainActor [weak self] in
            self?.onChange?(scheme)
        }
    }
}
#endif
