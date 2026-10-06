import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct WaveDockIdlePolicy {
    var lastActivity: Date = .now
    let delay: TimeInterval = 20
    mutating func interacted(at date: Date) { lastActivity = date }
    func shouldDim(at date: Date) -> Bool { date.timeIntervalSince(lastActivity) >= delay }
}
struct WaveDockActivityObserver: UIViewRepresentable {
    let onActivity: () -> Void
    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView(); view.isUserInteractionEnabled = false
        view.attach = { [weak coordinator = context.coordinator, weak view] in
            guard let window = view?.window else { return }; coordinator?.attach(to: window)
        }
        return view
    }
    func makeCoordinator() -> Coordinator { Coordinator(onActivity: onActivity) }
    func updateUIView(_ view: ProbeView, context: Context) {
        context.coordinator.onActivity = onActivity
        DispatchQueue.main.async { [weak coordinator = context.coordinator, weak view] in
            guard let window = view?.window else { return }; coordinator?.attach(to: window)
        }
    }
    static func dismantleUIView(_ view: ProbeView, coordinator: Coordinator) { coordinator.detach() }
    final class ProbeView: UIView {
        var attach: (() -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { attach?() } }
    }
    final class ActivityGesture: UIGestureRecognizer {
        var activity: (() -> Void)?
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { activity?(); state = .began }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { activity?(); state = .changed }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { activity?(); state = .ended }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
    }
    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onActivity: () -> Void
        private weak var window: UIWindow?
        private let gesture = ActivityGesture()
        init(onActivity: @escaping () -> Void) {
            self.onActivity = onActivity; super.init()
            gesture.delegate = self; gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false; gesture.delaysTouchesEnded = false
            gesture.activity = { [weak self] in self?.onActivity() }
        }
        func attach(to window: UIWindow) {
            guard self.window !== window else { return }
            detach(); self.window = window; window.addGestureRecognizer(gesture)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        func detach() { window?.removeGestureRecognizer(gesture); window = nil }
    }
}
