import SwiftUI
import UIKit

// SwiftUI selection does not always change when the active tab is tapped again.
// Observe native selections while forwarding the existing SwiftUI delegate.
struct WaveTabReselectionObserver: UIViewControllerRepresentable {
    var onSelect: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }
    func makeUIViewController(context: Context) -> Probe {
        let probe = Probe()
        probe.onAttach = { [weak coordinator = context.coordinator] controller in
            coordinator?.attach(to: controller)
        }
        return probe
    }
    func updateUIViewController(_ controller: Probe, context: Context) {
        context.coordinator.onSelect = onSelect
        controller.attach()
    }
    static func dismantleUIViewController(_ controller: Probe, coordinator: Coordinator) {
        coordinator.detach()
        controller.onAttach = nil
    }

    final class Probe: UIViewController {
        var onAttach: ((UITabBarController) -> Void)?
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            attach()
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attach()
        }
        func attach() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let tabs = self.tabBarController else { return }
                self.onAttach?(tabs)
            }
        }
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var onSelect: () -> Void
        private weak var tabs: UITabBarController?
        private weak var original: UITabBarControllerDelegate?
        init(onSelect: @escaping () -> Void) { self.onSelect = onSelect }
        func attach(to controller: UITabBarController) {
            guard controller.delegate !== self else { return }
            detach()
            tabs = controller
            original = controller.delegate
            controller.delegate = self
        }
        func detach() {
            if tabs?.delegate === self { tabs?.delegate = original }
            tabs = nil
            original = nil
        }
        func tabBarController(_ tabBarController: UITabBarController,
                              shouldSelect viewController: UIViewController) -> Bool {
            let allowed = original?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
            if allowed { onSelect() }
            return allowed
        }
        func tabBarController(_ tabBarController: UITabBarController,
                              didSelect viewController: UIViewController) {
            original?.tabBarController?(tabBarController, didSelect: viewController)
        }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            if original?.responds(to: selector) == true { return original }
            return super.forwardingTarget(for: selector)
        }
    }
}
