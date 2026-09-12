import Foundation
import CoreGraphics

/// Mirrors mpv-android's `PropertyChange` enum (TouchGestures.kt). Each case
/// is a distinct kind of gesture-driven change the observer should apply;
/// `diff` carries the same meaning as mpv-android's `Float` parameter for
/// each case (see MPVGestureObserver's doc comments below for exact units).
public enum MPVPropertyChange {
    case gestureInit
    case seek
    case volume
    case bright
    case finalize

    /* Tap gestures */
    case seekFixed
    case playPause
    case custom
}

/// Equivalent to mpv-android's `TouchGesturesObserver` interface. A consumer
/// (typically the player view/view model) implements this to react to
/// gesture-driven property changes; `TouchGestures` itself holds no
/// knowledge of mpv, AVFoundation, or UIKit — same separation of concerns
/// as the Kotlin original, where TouchGestures.kt only computes deltas and
/// MPVActivity.kt's `onPropertyChange` does the actual seeking/volume/
/// brightness work.
public protocol MPVGestureObserver: AnyObject {
    /// - Parameters:
    ///   - property: which kind of change occurred.
    ///   - diff: meaning depends on `property`:
    ///     - `.gestureInit`, `.finalize`: unused, always 0.
    ///     - `.seek`: seek offset in seconds from the position at gesture
    ///       start (matches mpv-android's `CONTROL_SEEK_MAX * dr`, a full
    ///       screen-width swipe covers 150 seconds).
    ///     - `.volume`: offset in the 0...1.5 range from the volume level
    ///       at gesture start (matches `CONTROL_VOLUME_MAX`).
    ///     - `.bright`: offset in the 0...1.5 range from the brightness
    ///       level at gesture start (matches `CONTROL_BRIGHT_MAX`).
    ///     - `.seekFixed`: -1 (tap left) or +1 (tap right); the observer is
    ///       expected to multiply by its own fixed seek amount, matching
    ///       mpv-android's `diff * 10f` (10 second fixed seeks).
    ///     - `.playPause`, `.custom`: unused / reserved, always 0.
    func onGesturePropertyChange(_ property: MPVPropertyChange, diff: Float)
}

/// Which gesture behavior a screen region is mapped to. Equivalent to
/// mpv-android's private `State` enum re-used for both a live state machine
/// state AND a per-region gesture-mapping value (TouchGestures.kt keeps
/// both meanings in the same `State` enum; kept separate here as
/// `GestureState` for clarity, but the two purposes still overlap the same
/// way the Kotlin source does — `gestureHoriz`/`gestureVertLeft`/
/// `gestureVertRight` are `GestureState` values used as targets for the
/// live `state` machine to transition into).
public enum MPVGestureState {
    case up
    case down
    case controlSeek
    case controlVolume
    case controlBright
}

/// Headless touch-gesture recognizer for a video player surface — no
/// UIKit/SwiftUI dependency, so any consumer (SwiftUI `DragGesture`,
/// UIKit `UIPanGestureRecognizer`, etc.) can drive it by feeding raw
/// touch points. Faithful port of mpv-android's `TouchGestures.kt`: same
/// state machine, same thresholds, same tap-gesture region split (left
/// 28% / center / right 28%), same throttling and deadzone logic.
public final class MPVTouchGestures {
    private weak var observer: MPVGestureObserver?

    public init(observer: MPVGestureObserver) {
        self.observer = observer
    }

    private var state: MPVGestureState = .up
    // relevant movement direction for the current state (0 = horizontal, 1 = vertical)
    private var stateDirection = 0

    // timestamp of the last tap (touch-up), in seconds since an arbitrary epoch
    private var lastTapTime: TimeInterval = 0
    // when the current gesture began
    private var lastDownTime: TimeInterval = 0

    // where the user initially placed their finger (touch-down)
    private var initialPos: CGPoint = .zero
    // last non-throttled processed position
    private var lastPos: CGPoint = .zero

    private var width: CGFloat = 0
    private var height: CGFloat = 0
    // minimum movement which triggers a Control state
    private var trigger: CGFloat = 0

    // which gesture behavior each screen region/direction is mapped to
    private var gestureHoriz: MPVGestureState = .down
    private var gestureVertLeft: MPVGestureState = .down
    private var gestureVertRight: MPVGestureState = .down
    private var tapGestureLeft: MPVPropertyChange?
    private var tapGestureCenter: MPVPropertyChange?
    private var tapGestureRight: MPVPropertyChange?

    // MARK: - Tunables (mirrors TouchGestures.kt's companion object constants)

    /// Ratio for trigger: 1/Xth of the minimum surface dimension. For tap
    /// gestures this is also the distance that must *not* be moved for a
    /// touch sequence to still count as a tap.
    private static let triggerRate: CGFloat = 30

    /// Maximum duration between taps (seconds) for a double tap to count.
    private static let tapDuration: TimeInterval = 0.3

    /// A full sweep from the left edge to the right edge seeks 150 seconds.
    private static let controlSeekMax: Float = 150

    /// Rescaled by the observer into whatever volume range it uses (0...1.5
    /// so a full swipe doesn't require starting exactly at zero volume).
    private static let controlVolumeMax: Float = 1.5

    /// Same reasoning as volume: user doesn't have to start from the very
    /// bottom of brightness to reach full brightness in one swipe.
    private static let controlBrightMax: Float = 1.5

    /// Percent of screen height, top and bottom, where touch-down is
    /// ignored entirely — leaves room for iOS's own edge gestures (Control
    /// Center, notification shade equivalent, home indicator) the same way
    /// mpv-android reserves this for Android's status bar swipe-down.
    private static let deadzonePercent: CGFloat = 5

    // MARK: - Configuration

    /// Must be called whenever the gesture surface's size changes (e.g. in
    /// a SwiftUI `GeometryReader`'s `onChange(of: geometry.size)`, or
    /// `viewDidLayoutSubviews` in UIKit). Equivalent to `setMetrics`.
    public func setMetrics(width: CGFloat, height: CGFloat) {
        guard width.isFinite, height.isFinite else { return }
        self.width = width
        self.height = height
        trigger = min(width, height) / Self.triggerRate
    }

    /// Configures which gesture maps to which region/direction. Equivalent
    /// to `syncSettings(prefs:resources:)`, but taking plain Swift values
    /// instead of reading Android SharedPreferences — the caller (e.g. a
    /// settings-backed view model) is responsible for translating its own
    /// persisted preferences into these parameters, matching how
    /// PlayerViewModel/MPVPlayerView owns settings on the iOS side rather
    /// than TouchGestures.kt reading prefs directly.
    public func configure(
        gestureHoriz: MPVGestureState = .down,
        gestureVertLeft: MPVGestureState = .down,
        gestureVertRight: MPVGestureState = .down,
        tapGestureLeft: MPVPropertyChange? = .seekFixed,
        tapGestureCenter: MPVPropertyChange? = .playPause,
        tapGestureRight: MPVPropertyChange? = .seekFixed
    ) {
        self.gestureHoriz = gestureHoriz
        self.gestureVertLeft = gestureVertLeft
        self.gestureVertRight = gestureVertRight
        self.tapGestureLeft = tapGestureLeft
        self.tapGestureCenter = tapGestureCenter
        self.tapGestureRight = tapGestureRight
    }

    // MARK: - Touch event entry points

    /// Feed a touch-down (finger just placed) event. Returns true if the
    /// event was consumed by the gesture recognizer (mirrors
    /// `onTouchEvent`'s ACTION_DOWN branch): callers that also want normal
    /// tap-through behavior (e.g. toggling controls visibility) should
    /// still handle that themselves — this recognizer only decides whether
    /// *it* wants to claim the gesture, the same division of responsibility
    /// as mpv-android's `dispatchTouchEvent` calling both `touchGestures`
    /// and the fallback single-tap-to-toggle-controls handler.
    @discardableResult
    public func touchDown(at point: CGPoint) -> Bool {
        guard width >= 1, height >= 1 else { return false }
        guard point.x.isFinite, point.y.isFinite else { return false }

        // deadzone on top/bottom, same reasoning as Android's status bar swipe
        if point.y < height * Self.deadzonePercent / 100
            || point.y > height * (100 - Self.deadzonePercent) / 100 {
            return false
        }

        initialPos = point
        _ = processTap(point)
        lastPos = point
        state = .down
        // mpv-android always returns true on ACTION_DOWN to keep receiving events;
        // callers here should keep forwarding subsequent touchMoved/touchUp calls
        // regardless of this return value for the same reason.
        return true
    }

    /// Feed a touch-move (finger dragging) event.
    @discardableResult
    public func touchMoved(to point: CGPoint) -> Bool {
        guard width >= 1, height >= 1 else { return false }
        guard point.x.isFinite, point.y.isFinite else { return false }
        return processMovement(point)
    }

    /// Feed a touch-up (finger lifted) event.
    @discardableResult
    public func touchUp(at point: CGPoint) -> Bool {
        guard width >= 1, height >= 1 else { return false }
        guard point.x.isFinite, point.y.isFinite else { return false }

        let movementHandled = processMovement(point)
        let tapHandled = processTap(point)
        let handled = movementHandled || tapHandled
        if state != .down {
            sendPropertyChange(.finalize, diff: 0)
        }
        state = .up
        return handled
    }

    // MARK: - Internal state machine (direct port of TouchGestures.kt)

    private func processTap(_ p: CGPoint) -> Bool {
        if state == .up {
            lastDownTime = now()
            // 3x trigger is an arbitrary-but-inherited threshold from upstream
            let dx = lastPos.x - p.x
            let dy = lastPos.y - p.y
            if (dx * dx + dy * dy).squareRoot() > trigger * 3 {
                lastTapTime = 0 // last tap was too far away, invalidate
            }
            return true
        }
        // discard if any movement gesture already took place
        if state != .down {
            return false
        }

        let currentTime = now()
        if currentTime - lastDownTime >= Self.tapDuration {
            lastTapTime = 0 // finger was held too long, reset
            return false
        }
        if currentTime - lastTapTime < Self.tapDuration {
            // [ Left 28% ] [    Center    ] [ Right 28% ]
            if p.x <= width * 0.28 {
                if let g = tapGestureLeft {
                    sendPropertyChange(g, diff: -1)
                    return true
                }
            } else if p.x >= width * 0.72 {
                if let g = tapGestureRight {
                    sendPropertyChange(g, diff: 1)
                    return true
                }
            } else {
                if let g = tapGestureCenter {
                    sendPropertyChange(g, diff: 0)
                    return true
                }
            }
            lastTapTime = 0
        } else {
            lastTapTime = currentTime
        }
        return false
    }

    private func processMovement(_ p: CGPoint) -> Bool {
        // throttle: only send updates when there's some movement since the last update
        let ldx = lastPos.x - p.x
        let ldy = lastPos.y - p.y
        if (ldx * ldx + ldy * ldy).squareRoot() < trigger / 3 {
            return false
        }
        lastPos = p

        let dx = p.x - initialPos.x
        let dy = p.y - initialPos.y
        let dr: Float = stateDirection == 0
            ? Float(dx / width)
            : Float(-dy / height)

        switch state {
        case .up:
            break
        case .down:
            // might transition into a Control state if the user moved enough
            if abs(dx) > trigger {
                state = gestureHoriz
                stateDirection = 0
            } else if abs(dy) > trigger {
                state = initialPos.x > width / 2 ? gestureVertRight : gestureVertLeft
                stateDirection = 1
            }
            // send Init so the observer can cache values before we start modifying them
            if state != .down {
                sendPropertyChange(.gestureInit, diff: 0)
            }
        case .controlSeek:
            sendPropertyChange(.seek, diff: Self.controlSeekMax * dr)
        case .controlVolume:
            sendPropertyChange(.volume, diff: Self.controlVolumeMax * dr)
        case .controlBright:
            sendPropertyChange(.bright, diff: Self.controlBrightMax * dr)
        }
        return state != .up && state != .down
    }

    private func sendPropertyChange(_ p: MPVPropertyChange, diff: Float) {
        observer?.onGesturePropertyChange(p, diff: diff)
    }

    private func now() -> TimeInterval {
        // Equivalent role to Android's SystemClock.uptimeMillis(): a
        // monotonic clock unaffected by wall-clock adjustments, which is
        // all this state machine needs (only differences between
        // timestamps are ever compared, never absolute values).
        ProcessInfo.processInfo.systemUptime
    }
}
