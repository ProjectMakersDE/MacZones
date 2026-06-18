import Cocoa
import ApplicationServices

/// Thin Accessibility wrapper for finding and moving windows of other apps.
/// All rects here are in Quartz / AX global coordinates: top-left origin, y↓.
enum AX {
    static let systemWide = AXUIElementCreateSystemWide()

    static func element(at point: CGPoint) -> AXUIElement? {
        var el: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &el)
        return err == .success ? el : nil
    }

    /// Walk up from an arbitrary UI element to the enclosing window element.
    static func window(for element: AXUIElement) -> AXUIElement? {
        if role(of: element) == (kAXWindowRole as String) { return element }
        if let w = copyElement(element, kAXWindowAttribute) { return w }

        var current: AXUIElement? = element
        var depth = 0
        while let c = current, depth < 16 {
            if role(of: c) == (kAXWindowRole as String) { return c }
            current = copyElement(c, kAXParentAttribute)
            depth += 1
        }
        return nil
    }

    static func windowUnderCursor(at point: CGPoint) -> AXUIElement? {
        guard let el = element(at: point) else { return nil }
        return window(for: el)
    }

    static func role(of el: AXUIElement) -> String? {
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &v) == .success {
            return v as? String
        }
        return nil
    }

    private static func copyElement(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let value = v else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let pv = posValue, let sv = sizeValue,
              CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID()
        else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sv as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    static func setPosition(_ p: CGPoint, for window: AXUIElement) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
        }
    }

    static func setSize(_ s: CGSize, for window: AXUIElement) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v)
        }
    }

    /// Set position + size. Position is applied twice because some apps clamp
    /// the position while resizing from a small size.
    static func setFrame(_ rect: CGRect, for window: AXUIElement) {
        setPosition(rect.origin, for: window)
        setSize(rect.size, for: window)
        setPosition(rect.origin, for: window)
    }
}
