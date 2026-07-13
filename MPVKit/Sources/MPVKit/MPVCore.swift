import Foundation
import CMPV

/// Errors surfaced from libmpv calls, wrapping mpv's own error codes.
public struct MPVError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String

    init(_ code: Int32) {
        self.code = code
        self.message = String(cString: mpv_error_string(code))
    }

    public var description: String { "MPVError(\(code)): \(message)" }
}

/// Formats mpv properties can be read/written as. Mirrors mpv-android's
/// MPVLib.mpvFormat constants (used there as raw ints; here as a proper enum).
public enum MPVFormat: Int32 {
    case none   = 0 // MPV_FORMAT_NONE
    case string = 1 // MPV_FORMAT_STRING
    case flag   = 3 // MPV_FORMAT_FLAG
    case int64  = 4 // MPV_FORMAT_INT64
    case double = 5 // MPV_FORMAT_DOUBLE

    /// Maps to the real libmpv `mpv_format` C enum, for passing to raw
    /// C API calls (e.g. mpv_observe_property). Explicit case-by-case
    /// mapping rather than `mpv_format(rawValue: UInt32(self.rawValue))`
    /// so this is guaranteed non-optional at compile time — the C enum's
    /// generated Swift initializer is failable (it can't know every raw
    /// value maps to a defined case), which would otherwise force an
    /// unsafe unwrap or an unreachable-but-still-required fallback here.
    var mpvFormat: mpv_format {
        switch self {
        case .none:   return MPV_FORMAT_NONE
        case .string: return MPV_FORMAT_STRING
        case .flag:   return MPV_FORMAT_FLAG
        case .int64:  return MPV_FORMAT_INT64
        case .double: return MPV_FORMAT_DOUBLE
        }
    }
}

/// Events dispatched by MPVCore, mirroring the `event(int)` and
/// `eventProperty(...)` static callbacks mpv-android's event.cpp invokes on
/// MPVLib via JNI. Here they're delivered through MPVCoreDelegate instead.
public enum MPVEvent {
    case propertyChanged(name: String, format: MPVFormat, data: MPVPropertyData)
    case fileLoaded
    case seek
    case playbackRestart
    case shutdown
    case endFile(reason: Int32)
    case idle
    case logMessage(prefix: String, level: Int32, text: String)
    case other(eventId: Int32)
}

public enum MPVPropertyData {
    case none
    case flag(Bool)
    case int64(Int64)
    case double(Double)
    case string(String)
}

/// Receives events from MPVCore's background event-polling loop.
/// Delivered on the main thread, mirroring how mpv-android marshals events
/// back onto MPVLib's registered EventObserver instances (which Android app
/// code then typically hops to the main thread from, e.g. via runOnUiThread —
/// MPVCore does that hop for you here instead).
public protocol MPVCoreDelegate: AnyObject {
    func mpv(_ core: MPVCore, event: MPVEvent)
}

/// The central libmpv context wrapper. Equivalent responsibilities to
/// mpv-android's `MPVLib.java` (JNI declarations) + `main.cpp` (create/init/
/// destroy/command) + `event.cpp` (the polling thread) combined into one
/// Swift type, since Swift doesn't need the JNI split between "declared
/// interface" and "native implementation."
///
/// Usage mirrors mpv-android's MPVLib lifecycle:
///   let core = MPVCore()
///   core.create()
///   core.setOptionString("some-option", "value")
///   core.initialize()
///   core.command(["loadfile", url])
///   ...
///   core.destroy()
public final class MPVCore {
    /// The underlying mpv_handle. `internal` (not private) because
    /// MPVRenderContext needs it to create the render context.
    internal private(set) var handle: OpaquePointer?

    public weak var delegate: MPVCoreDelegate?

    private var eventTask: Task<Void, Never>?
    private let eventContinuationBox = WakeupBox()

    public init() {}

    deinit {
        if handle != nil {
            destroy()
        }
    }

    // MARK: - Lifecycle (main.cpp: create / init / destroy)

    /// Equivalent to MPVLib.create() -> jni main.cpp `create()`.
    /// Creates the mpv_handle and applies the same baseline logging setup
    /// mpv-android uses ("terminal-default" log messages, msg-level=all=v),
    /// so `logMessage` events are populated for debugging exactly like on
    /// Android.
    public func create() throws {
        setlocale(LC_NUMERIC, "C") // required by mpv, same as main.cpp prepare_environment()

        guard handle == nil else {
            throw MPVError.alreadyInitialized
        }

        guard let h = mpv_create() else {
            throw MPVError.contextCreateFailed
        }
        handle = h

        mpv_request_log_messages(h, "terminal-default")
        mpv_set_option_string(h, "msg-level", "all=v")
    }

    /// Equivalent to MPVLib.init() -> jni main.cpp `init()`.
    /// Calls mpv_initialize, then starts the Swift-side event loop (replacing
    /// mpv-android's pthread event_thread).
    public func initialize() throws {
        guard let h = handle else { throw MPVError.notCreated }

        let result = mpv_initialize(h)
        guard result >= 0 else { throw MPVError(result) }

        startEventLoop()
    }

    /// Equivalent to MPVLib.destroy() -> jni main.cpp `destroy()`.
    /// Stops the event loop, then terminates and frees the mpv_handle.
    public func destroy() {
        guard let h = handle else { return }

        stopEventLoop()
        mpv_terminate_destroy(h)
        handle = nil
    }

    // MARK: - Commands (main.cpp: command())

    /// Equivalent to MPVLib.command(String[]) -> jni main.cpp `command()`.
    /// Runs an mpv command synchronously, e.g. core.command(["loadfile", url]).
    @discardableResult
    public func command(_ args: [String]) -> Int32 {
        guard let h = handle else { return MPV_ERROR_UNINITIALIZED.rawValue }

        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cArgs.append(nil)
        defer { cArgs.forEach { if let p = $0 { free(p) } } }

        return cArgs.withUnsafeMutableBufferPointer { buf -> Int32 in
            buf.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buf.count) { rebound in
                mpv_command(h, rebound)
            }
        }
    }

    /// Async command variant using mpv_command_async, useful for commands
    /// that shouldn't block the calling thread (mpv-android's synchronous
    /// jni command() call is fine there since it's invoked off the JNI/UI
    /// thread already in practice; here we expose both for flexibility).
    public func commandAsync(_ args: [String], replyUserdata: UInt64 = 0) -> Int32 {
        guard let h = handle else { return MPV_ERROR_UNINITIALIZED.rawValue }

        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cArgs.append(nil)
        defer { cArgs.forEach { if let p = $0 { free(p) } } }

        return cArgs.withUnsafeMutableBufferPointer { buf -> Int32 in
            buf.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buf.count) { rebound in
                mpv_command_async(h, replyUserdata, rebound)
            }
        }
    }

    // MARK: - Options (property.cpp: setOptionString)

    /// Equivalent to MPVLib.setOptionString(String, String).
    @discardableResult
    public func setOptionString(_ option: String, _ value: String) -> Int32 {
        guard let h = handle else { return MPV_ERROR_UNINITIALIZED.rawValue }
        return mpv_set_option_string(h, option, value)
    }

    // MARK: - Event loop (event.cpp)

    /// Replaces mpv-android's pthread-based event_thread(). Swift concurrency
    /// gives us a cleaner mechanism: an unstructured Task looping on
    /// mpv_wait_event, hopping results to the main actor before calling the
    /// delegate — matching the "always deliver on a safe thread" guarantee
    /// mpv-android effectively provides via its own dispatch path.
    private func startEventLoop() {
        eventTask = Task.detached { [weak self] in
            guard let self else { return }
            await self.runEventLoop()
        }
    }

    private func stopEventLoop() {
        eventTask?.cancel()
        // Wake up mpv_wait_event(-1) so the loop notices cancellation
        // promptly instead of waiting for the next real event, mirroring
        // main.cpp destroy()'s mpv_wakeup(g_mpv) call.
        if let h = handle {
            mpv_wakeup(h)
        }
        eventTask = nil
    }

    private func runEventLoop() async {
        guard let h = handle else { return }

        while !Task.isCancelled {
            guard let event = mpv_wait_event(h, -1.0)?.pointee else { continue }

            if Task.isCancelled { break }
            if event.event_id == MPV_EVENT_NONE { continue }

            let mapped = Self.mapEvent(event)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.delegate?.mpv(self, event: mapped)
            }

            if event.event_id == MPV_EVENT_SHUTDOWN {
                break
            }
        }
    }

    /// Translates a raw mpv_event into the Swift-friendly MPVEvent enum.
    /// Equivalent to event.cpp's sendEventToJava / sendPropertyUpdateToJava /
    /// sendLogMessageToJava dispatch logic, minus the JNI plumbing.
    private static func mapEvent(_ event: mpv_event) -> MPVEvent {
        switch event.event_id {
        case MPV_EVENT_PROPERTY_CHANGE, MPV_EVENT_GET_PROPERTY_REPLY:
            guard let dataPtr = event.data else {
                return .other(eventId: Int32(event.event_id.rawValue))
            }
            let prop = dataPtr.assumingMemoryBound(to: mpv_event_property.self).pointee
            let name = String(cString: prop.name)
            let format = MPVFormat(rawValue: Int32(prop.format.rawValue)) ?? .none

            let data: MPVPropertyData
            switch prop.format {
            case MPV_FORMAT_FLAG:
                let v = prop.data.assumingMemoryBound(to: Int32.self).pointee
                data = .flag(v != 0)
            case MPV_FORMAT_INT64:
                let v = prop.data.assumingMemoryBound(to: Int64.self).pointee
                data = .int64(v)
            case MPV_FORMAT_DOUBLE:
                let v = prop.data.assumingMemoryBound(to: Double.self).pointee
                data = .double(v)
            case MPV_FORMAT_STRING:
                let cstrPtr = prop.data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee
                data = cstrPtr.map { .string(String(cString: $0)) } ?? .none
            default:
                data = .none
            }
            return .propertyChanged(name: name, format: format, data: data)

        case MPV_EVENT_LOG_MESSAGE:
            guard let dataPtr = event.data else {
                return .other(eventId: Int32(event.event_id.rawValue))
            }
            let msg = dataPtr.assumingMemoryBound(to: mpv_event_log_message.self).pointee
            // Same invalid-UTF-8 defensive filtering as event.cpp's
            // sendLogMessageToJava, since malformed byte sequences from
            // muxer/codec logs can otherwise crash String(cString:).
            let text = String(cString: msg.text)
            let prefix = String(cString: msg.prefix)
            return .logMessage(prefix: prefix, level: Int32(msg.log_level.rawValue), text: text)

        case MPV_EVENT_FILE_LOADED:
            return .fileLoaded
        case MPV_EVENT_SEEK:
            return .seek
        case MPV_EVENT_PLAYBACK_RESTART:
            return .playbackRestart
        case MPV_EVENT_SHUTDOWN:
            return .shutdown
        case MPV_EVENT_IDLE:
            return .idle
        case MPV_EVENT_END_FILE:
            guard let dataPtr = event.data else {
                return .endFile(reason: -1)
            }
            let endFile = dataPtr.assumingMemoryBound(to: mpv_event_end_file.self).pointee
            return .endFile(reason: Int32(endFile.reason.rawValue))
        default:
            return .other(eventId: Int32(event.event_id.rawValue))
        }
    }
}

/// Small reference box so the C wakeup trampoline (which needs a stable
/// `void*` to pass through mpv_set_wakeup_callback) has something to target
/// without capturing `self` in a way ARC/C interop would mishandle.
private final class WakeupBox {}

extension MPVError {
    static let alreadyInitialized = MPVError(rawCode: -900, message: "mpv is already initialized")
    static let contextCreateFailed = MPVError(rawCode: -901, message: "mpv_create() failed")
    static let notCreated = MPVError(rawCode: -902, message: "mpv is not created; call create() first")

    fileprivate init(rawCode: Int32, message: String) {
        self.code = rawCode
        self.message = message
    }
}
