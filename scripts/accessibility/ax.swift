#!/usr/bin/env swift
// Drives and audits the running Palmier Pro through the macOS Accessibility API.
//
//   scripts/accessibility/ax.swift dump [--all]        tree of identified (or all) elements
//   scripts/accessibility/ax.swift audit               interactive elements missing a valid identifier or a label
//   scripts/accessibility/ax.swift press <identifier>  AXPress the element with that identifier
//   scripts/accessibility/ax.swift find <identifier>   print the element's role, label, value, and frame
//   scripts/accessibility/ax.swift set <identifier> <value>       set AXValue (e.g. a timecode for timeline.playhead)
//   scripts/accessibility/ax.swift increment|decrement <identifier>
//
// The calling terminal needs Accessibility permission (System Settings → Privacy & Security).
import AppKit
import ApplicationServices

let interactiveRoles: Set<String> = [
    "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXSlider",
    "AXTextField", "AXTextArea", "AXComboBox", "AXIncrementor", "AXLink", "AXDisclosureTriangle",
    "AXSegmentedControl", "AXColorWell",
]

/// First segment of every app identifier; SwiftUI's automatic SF Symbol identifiers never match.
let identifierAreas: Set<String> = [
    "panel", "window", "toolbar", "media", "preview", "inspector", "timeline", "agent", "export",
    "settings", "home", "generation", "project", "account", "help", "search", "tour", "editor",
]

func isValidIdentifier(_ id: String) -> Bool {
    let segments = id.split(separator: ".", omittingEmptySubsequences: false)
    return segments.count >= 2
        && identifierAreas.contains(String(segments[0]))
        && segments.allSatisfy { !$0.isEmpty && !$0.contains(" ") }
}

func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? T
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) ?? []
}

/// System-owned chrome the app cannot label: window buttons, the title-bar proxy menu, scroll arrows.
let systemSubroles: Set<String> = [
    "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton", "AXToolbarButton",
    "AXIncrementArrow", "AXDecrementArrow", "AXIncrementPage", "AXDecrementPage",
]
let systemParentRoles: Set<String> = ["AXScrollBar", "AXWindow"]

struct Node {
    let element: AXUIElement
    let depth: Int
    var parentRole: String? = nil
    var role: String { attribute(element, kAXRoleAttribute) ?? "?" }
    var subrole: String? { attribute(element, kAXSubroleAttribute) }
    var isSystemChrome: Bool {
        systemSubroles.contains(subrole ?? "") || systemParentRoles.contains(parentRole ?? "")
    }
    var identifier: String? { nonEmpty(attribute(element, kAXIdentifierAttribute)) }
    var label: String? {
        nonEmpty(attribute(element, kAXDescriptionAttribute))
            ?? nonEmpty(attribute(element, kAXTitleAttribute))
    }
    var value: String? {
        guard let raw: CFTypeRef = attribute(element, kAXValueAttribute) else { return nil }
        return nonEmpty("\(raw)")
    }
    var frame: CGRect? {
        guard let pos: AXValue = attribute(element, kAXPositionAttribute),
              let size: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(pos, .cgPoint, &point)
        AXValueGetValue(size, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }
}

func nonEmpty(_ s: String?) -> String? {
    guard let s, !s.isEmpty else { return nil }
    return s
}

func walk(_ element: AXUIElement, depth: Int = 0, parentRole: String? = nil, visit: (Node) -> Void) {
    guard depth < 80 else { return }
    let node = Node(element: element, depth: depth, parentRole: parentRole)
    visit(node)
    let role = node.role
    for child in children(element) { walk(child, depth: depth + 1, parentRole: role, visit: visit) }
}

func appElement() -> AXUIElement {
    guard AXIsProcessTrusted() else {
        fail("Accessibility permission is missing for this terminal.")
    }
    let running = NSWorkspace.shared.runningApplications.first {
        $0.bundleIdentifier == "io.palmier.pro" || $0.localizedName == "PalmierPro" || $0.localizedName == "Palmier Pro"
    }
    guard let pid = running?.processIdentifier else { fail("Palmier Pro is not running.") }
    return AXUIElementCreateApplication(pid)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func describe(_ node: Node) -> String {
    var parts = [node.role]
    if let id = node.identifier { parts.append("#\(id)") }
    if let label = node.label { parts.append("\"\(label)\"") }
    if let value = node.value, value.count <= 60 { parts.append("= \(value)") }
    return parts.joined(separator: " ")
}

func find(_ identifier: String) -> Node? {
    var match: Node?
    walk(appElement()) { node in
        if match == nil, node.identifier == identifier { match = node }
    }
    return match
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "dump":
    let all = args.contains("--all")
    walk(appElement()) { node in
        guard all || node.identifier != nil else { return }
        print(String(repeating: "  ", count: all ? node.depth : 0) + describe(node))
    }
case "audit":
    var total = 0, missingID: [Node] = [], missingLabel: [Node] = [], seen: [String: Int] = [:]
    walk(appElement()) { node in
        if let id = node.identifier, isValidIdentifier(id) { seen[id, default: 0] += 1 }
        guard interactiveRoles.contains(node.role), !node.isSystemChrome else { return }
        total += 1
        if !(node.identifier.map(isValidIdentifier) ?? false) { missingID.append(node) }
        if node.label == nil { missingLabel.append(node) }
    }
    let duplicates = seen.filter { $0.value > 1 }.keys.sorted()
    print("interactive elements: \(total)")
    print("missing or invalid identifier: \(missingID.count)")
    for node in missingID { print("  " + describe(node)) }
    print("missing label: \(missingLabel.count)")
    for node in missingLabel { print("  " + describe(node)) }
    print("duplicate identifiers: \(duplicates.count)")
    for id in duplicates { print("  \(id) ×\(seen[id]!)") }
    exit(missingID.isEmpty && missingLabel.isEmpty && duplicates.isEmpty ? 0 : 2)
case "press":
    guard args.count == 2 else { fail("usage: press <identifier>") }
    guard let node = find(args[1]) else { fail("No element with identifier \(args[1]).") }
    let result = AXUIElementPerformAction(node.element, kAXPressAction as CFString)
    guard result == .success else { fail("AXPress failed on \(args[1]): \(result.rawValue)") }
    print("pressed \(describe(node))")
case "set":
    guard args.count == 3 else { fail("usage: set <identifier> <value>") }
    guard let node = find(args[1]) else { fail("No element with identifier \(args[1]).") }
    let result = AXUIElementSetAttributeValue(node.element, kAXValueAttribute as CFString, args[2] as CFString)
    guard result == .success else { fail("Setting value failed on \(args[1]): \(result.rawValue)") }
    print(describe(find(args[1]) ?? node))
case "increment", "decrement":
    guard args.count == 2 else { fail("usage: \(args[0]) <identifier>") }
    guard let node = find(args[1]) else { fail("No element with identifier \(args[1]).") }
    let action = args[0] == "increment" ? kAXIncrementAction : kAXDecrementAction
    let result = AXUIElementPerformAction(node.element, action as CFString)
    guard result == .success else { fail("\(args[0]) failed on \(args[1]): \(result.rawValue)") }
    print(describe(find(args[1]) ?? node))
case "find":
    guard args.count == 2 else { fail("usage: find <identifier>") }
    guard let node = find(args[1]) else { fail("No element with identifier \(args[1]).") }
    print(describe(node))
    if let frame = node.frame { print("frame \(frame)") }
default:
    fail("usage: ax.swift dump [--all] | audit | press|find|increment|decrement <identifier> | set <identifier> <value>")
}
