import SwiftUI
import UIKit

struct WaveScrollChromePolicy {
    private(set) var hidden = false
    private var accumulated: CGFloat = 0
    mutating func reset() { hidden = false; accumulated = 0 }
    mutating func update(delta: CGFloat, offset: CGFloat) -> Bool {
        let old = hidden
        guard delta.isFinite, offset.isFinite else { return false }
        if offset <= 8 && (!hidden || delta <= 0) { reset(); return hidden != old }
        if (delta > 0 && accumulated < 0) || (delta < 0 && accumulated > 0) { accumulated = 0 }
        accumulated += delta
        if accumulated >= 28 { hidden = true; accumulated = 0 }
        if accumulated <= -12 { hidden = false; accumulated = 0 }
        return hidden != old
    }
}

struct WaveScrollChromeObserver: UIViewRepresentable {
    let onChange: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }
    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.attach = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }; coordinator?.attach(from: view)
        }
        return view
    }
    func updateUIView(_ view: ProbeView, context: Context) {
        context.coordinator.onChange = onChange
        DispatchQueue.main.async { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }; coordinator?.attach(from: view)
        }
    }
    static func dismantleUIView(_ view: ProbeView, coordinator: Coordinator) { coordinator.detach() }
    final class ProbeView: UIView {
        var attach: (() -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { attach?() } }
        override func layoutSubviews() { super.layoutSubviews(); attach?() }
    }
    @MainActor
    final class Coordinator: NSObject {
        var onChange: (Bool) -> Void
        private weak var scroll: UIScrollView?
        private var policy = WaveScrollChromePolicy()
        private var lastTranslation: CGFloat = 0
        private var offsetObservation: NSKeyValueObservation?
        init(onChange: @escaping (Bool) -> Void) { self.onChange = onChange }
        func attach(from probe: UIView) {
            guard probe.window != nil else { return }
            var parent = probe.superview
            while let container = parent {
                if let candidate = findScroll(in: container), candidate.bounds.width > 0 {
                    guard scroll !== candidate else { return }
                    detach(); scroll = candidate
                    candidate.panGestureRecognizer.addTarget(self, action: #selector(panned(_:)))
                    offsetObservation = candidate.observe(\.contentOffset, options: [.new]) { [weak self] view, _ in
                        guard !view.isDragging, !view.isDecelerating, view.contentOffset.y + view.adjustedContentInset.top <= 8 else { return }
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.policy.hidden, let current = self.scroll, !current.isDragging, !current.isDecelerating, current.contentOffset.y + current.adjustedContentInset.top <= 8 else { return }
                            self.policy.reset(); self.onChange(false)
                        }
                    }
                    return
                }
                parent = container.superview
            }
        }
        private func findScroll(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UICollectionView { return scroll }
            if let scroll = view as? UITableView { return scroll }
            for child in view.subviews { if let found = findScroll(in: child) { return found } }
            return nil
        }
        @objc private func panned(_ gesture: UIPanGestureRecognizer) {
            guard let scroll, !UIAccessibility.isVoiceOverRunning else { return }
            let translation = gesture.translation(in: scroll).y
            switch gesture.state {
            case .began: lastTranslation = translation
            case .changed:
                let delta = lastTranslation - translation
                lastTranslation = translation
                if policy.update(delta: delta, offset: scroll.contentOffset.y + scroll.adjustedContentInset.top) { onChange(policy.hidden) }
            default: break
            }
        }
        func detach() {
            scroll?.panGestureRecognizer.removeTarget(self, action: #selector(panned(_:)))
            offsetObservation?.invalidate(); offsetObservation = nil; scroll = nil
            policy.reset()
        }
    }
}
