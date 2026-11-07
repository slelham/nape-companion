// Copyright (c) 2026 slelham
// SPDX-License-Identifier: MIT

import AppKit

/// Local display names. Saving writes UserDefaults and nothing on the trackball.
final class RenamePanel: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private static var retained: RenamePanel?
    private let onSave: ([String]) -> Void
    private var fields: [NSTextField] = []

    static func show(names: [String], onSave: @escaping ([String]) -> Void) {
        retained?.close()
        let panel = RenamePanel(names: LayerNames.normalize(names), onSave: onSave)
        retained = panel
        panel.showWindow(nil)
        panel.window?.makeKeyAndOrderFront(nil)
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    init(names: [String], onSave: @escaping ([String]) -> Void) {
        self.onSave = onSave
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Layer names"
        super.init(window: window)
        window.delegate = self
        window.contentView = content(names: names)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func windowWillClose(_ notification: Notification) {
        if RenamePanel.retained === self {
            RenamePanel.retained = nil
        }
    }

    @objc private func save(_ sender: Any?) {
        let values = fields.map(\.stringValue)
        onSave(LayerNames.normalize(values))
        close()
    }

    @objc private func cancel(_ sender: Any?) {
        close()
    }

    @objc private func reset(_ sender: Any?) {
        let defaults = LayerNames.defaults()
        for (index, field) in fields.enumerated() where defaults.indices.contains(index) {
            field.stringValue = defaults[index]
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field.stringValue.count > LayerNames.maxLength {
            field.stringValue = String(field.stringValue.prefix(LayerNames.maxLength))
        }
    }

    private func content(names: [String]) -> NSView {
        let content = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let help = NSTextField(
            wrappingLabelWithString: "These names stay on this Mac. Nothing is written to the trackball."
        )
        help.preferredMaxLayoutWidth = 400
        stack.addArrangedSubview(help)

        fields = (0 ..< LayerNames.count).map { index in
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 8
            let label = NSTextField(labelWithString: "Layer \(index)")
            label.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            label.setAccessibilityLabel("Display name for layer \(index)")
            label.widthAnchor.constraint(equalToConstant: 72).isActive = true
            let field = NSTextField(string: names.indices.contains(index) ? names[index] : "")
            field.delegate = self
            field.tag = index
            field.setAccessibilityLabel("Display name for layer \(index)")
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
            row.addArrangedSubview(label)
            row.addArrangedSubview(field)
            stack.addArrangedSubview(row)
            return field
        }

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let resetButton = NSButton(title: "Reset", target: self, action: #selector(reset(_:)))
        resetButton.setAccessibilityLabel("Reset layer names to Layer 0 through Layer 7")
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save(_:)))
        saveButton.keyEquivalent = "\r"
        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(resetButton)
        buttons.addArrangedSubview(cancelButton)
        buttons.addArrangedSubview(saveButton)
        stack.addArrangedSubview(buttons)
        window?.defaultButtonCell = saveButton.cell as? NSButtonCell

        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
        ])
        return content
    }
}
