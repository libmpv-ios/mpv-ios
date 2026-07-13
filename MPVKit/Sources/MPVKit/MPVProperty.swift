import Foundation
import CMPV

/// Typed property access on MPVCore, equivalent to mpv-android's
/// property.cpp (getPropertyInt/Double/Boolean/String, setProperty*,
/// observeProperty). Swift's overloading + Optional return types replace
/// the Java boxed-type (Integer/Double/Boolean) nullable-return pattern
/// property.cpp uses to signal "property unavailable."
public extension MPVCore {

    // MARK: - Getters

    /// Equivalent to MPVLib.getPropertyInt(String): Integer?
    func getPropertyInt(_ property: String) -> Int64? {
        guard let h = handle else { return nil }
        var value: Int64 = 0
        let result = mpv_get_property(h, property, MPV_FORMAT_INT64, &value)
        guard result >= 0 else { return nil }
        return value
    }

    /// Equivalent to MPVLib.getPropertyDouble(String): Double?
    func getPropertyDouble(_ property: String) -> Double? {
        guard let h = handle else { return nil }
        var value: Double = 0
        let result = mpv_get_property(h, property, MPV_FORMAT_DOUBLE, &value)
        guard result >= 0 else { return nil }
        return value
    }

    /// Equivalent to MPVLib.getPropertyBoolean(String): Boolean?
    func getPropertyBool(_ property: String) -> Bool? {
        guard let h = handle else { return nil }
        var value: Int32 = 0
        let result = mpv_get_property(h, property, MPV_FORMAT_FLAG, &value)
        guard result >= 0 else { return nil }
        return value != 0
    }

    /// Equivalent to MPVLib.getPropertyString(String): String?
    /// Frees the mpv-allocated string via mpv_free, same as property.cpp.
    func getPropertyString(_ property: String) -> String? {
        guard let h = handle else { return nil }
        var cValue: UnsafeMutablePointer<CChar>?
        let result = withUnsafeMutablePointer(to: &cValue) { ptr -> Int32 in
            ptr.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1) { rawPtr in
                mpv_get_property(h, property, MPV_FORMAT_STRING, rawPtr)
            }
        }
        guard result >= 0, let cValue else { return nil }
        defer { mpv_free(cValue) }
        return String(cString: cValue)
    }

    // MARK: - Setters

    /// Equivalent to MPVLib.setPropertyInt(String, Int).
    @discardableResult
    func setPropertyInt(_ property: String, _ value: Int64) -> Int32 {
        guard let h = handle else { return MPV_ERROR_UNINITIALIZED.rawValue }
        var v = value
        return mpv_set_property(h, property, MPV_FORMAT_INT64, &v)
    }

    /// Equivalent to MPVLib.setPropertyDouble(String, Double).
    @discardableResult
    func setPropertyDouble(_ property: String, _ value: Double) -> Int32 {
        guard let h = handle else { return MPV_ERROR_UNINITIALIZED.rawValue }
        var v = value
        return mpv_set_property(h, property, MPV_FORMAT_DOUBLE, &v)
    }

    /// Equivalent to MPVLib.setPropertyBoolean(String, Boolean).
    @discardableResult
    func setPropertyBool(_ property: String, _ value: Bool) -> Int32 {
        guard let h = handle else { return MPV_ERROR_UNINITIALIZED.rawValue }
        var v: Int32 = value ? 1 : 0
        return mpv_set_property(h, property, MPV_FORMAT_FLAG, &v)
    }

    /// Equivalent to MPVLib.setPropertyString(String, String).
    @discardableResult
    func setPropertyString(_ property: String, _ value: String) -> Int32 {
        guard let h = handle else { return MPV_ERROR_UNINITIALIZED.rawValue }
        return value.withCString { cValue -> Int32 in
            var mutableCopy: UnsafePointer<CChar>? = cValue
            return withUnsafeMutablePointer(to: &mutableCopy) { ptr -> Int32 in
                ptr.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1) { rawPtr in
                    mpv_set_property(h, property, MPV_FORMAT_STRING, rawPtr)
                }
            }
        }
    }

    // MARK: - Observation (property.cpp: observeProperty)

    /// Equivalent to MPVLib.observeProperty(String, int format).
    /// After calling this, changes to `property` arrive as
    /// `.propertyChanged` events via MPVCoreDelegate, matching how
    /// mpv-android routes observed property changes through
    /// eventProperty(...) callbacks on MPVLib.
    @discardableResult
    func observeProperty(_ property: String, format: MPVFormat) -> Int32 {
        guard let h = handle else { return MPV_ERROR_UNINITIALIZED.rawValue }
        return mpv_observe_property(h, 0, property, format.mpvFormat)
    }

    /// Equivalent to MPVLib.unobserveProperty — stops delivering change
    /// events for properties matching the given reply userdata (0, matching
    /// observeProperty's default above).
    @discardableResult
    func unobserveProperty() -> Int32 {
        guard let h = handle else { return MPV_ERROR_UNINITIALIZED.rawValue }
        return mpv_unobserve_property(h, 0)
    }
}
