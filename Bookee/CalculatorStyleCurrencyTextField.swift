//
//  CalculatorStyleCurrencyTextField.swift
//  Bookee
//
//  Created by Kara Eveland on 3/4/26.
//

import SwiftUI

// MARK: - Keyboard Accessory View

fileprivate class KeyboardAccessoryView: UIView {
    var doneButtonAction: (() -> Void)?
    var dismissOnlyAction: (() -> Void)?
    var toolbarDoneTriggersCommit: Bool = false
    private let toolbar = UIToolbar()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = .clear
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        toolbar.barStyle = .default
        toolbar.isTranslucent = true
        toolbar.autoresizingMask = [.flexibleWidth]

        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(doneButtonTapped))
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 17, weight: .medium)]
        doneButton.setTitleTextAttributes(attributes, for: .normal)
        doneButton.setTitleTextAttributes(attributes, for: .highlighted)

        toolbar.items = [flexSpace, doneButton]
        toolbar.sizeToFit()
        addSubview(toolbar)
    }

    @objc private func doneButtonTapped() {
        if toolbarDoneTriggersCommit {
            doneButtonAction?()
        } else {
            dismissOnlyAction?()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 52)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        toolbar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 44)
    }
}

// MARK: - Cursor-at-End Text Field (SwiftUI Wrapper)

/// A SwiftUI wrapper for a UITextField that automatically positions the cursor at the end when the field gains focus.
struct CursorAtEndTextField_SwiftUI: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var onCommit: () -> Void = {}
    var shouldDismissKeyboard: Bool = true
    var showKeyboardToolbar: Bool = true
    var toolbarDoneTriggersCommit: Bool = false

    var textAlignment: NSTextAlignment = .natural
    var keyboardType: UIKeyboardType = .default
    var autocapitalizationType: UITextAutocapitalizationType = .words
    var frameWidth: CGFloat? = nil
    var returnKeyType: UIReturnKeyType? = nil

    func makeUIView(context: Context) -> UITextField {
        let textField = CursorAtEndUITextField()
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.borderStyle = .none
        textField.textAlignment = textAlignment
        textField.keyboardType = keyboardType
        textField.autocapitalizationType = autocapitalizationType
        textField.returnKeyType = returnKeyType ?? .default

        if showKeyboardToolbar {
            let accessoryView = KeyboardAccessoryView()
            accessoryView.toolbarDoneTriggersCommit = toolbarDoneTriggersCommit
            accessoryView.doneButtonAction = { [weak textField] in
                _ = textField?.resignFirstResponder()
                DispatchQueue.main.async { context.coordinator.onCommit() }
            }
            accessoryView.dismissOnlyAction = { [weak textField] in
                _ = textField?.resignFirstResponder()
            }
            textField.inputAccessoryView = accessoryView
        }

        textField.addTarget(context.coordinator, action: #selector(Coordinator.textFieldDidChange(_:)), for: .editingChanged)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)

        context.coordinator.textField = textField
        context.coordinator.frameWidth = frameWidth
        context.coordinator.shouldDismissKeyboard = shouldDismissKeyboard
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text { uiView.text = text }
        uiView.placeholder = placeholder
        uiView.textAlignment = textAlignment
        uiView.keyboardType = keyboardType
        uiView.autocapitalizationType = autocapitalizationType
        uiView.returnKeyType = returnKeyType ?? .default
        context.coordinator.frameWidth = frameWidth
        context.coordinator.shouldDismissKeyboard = shouldDismissKeyboard
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var onCommit: () -> Void
        weak var textField: UITextField?
        var frameWidth: CGFloat? = nil
        var shouldDismissKeyboard: Bool = true

        init(text: Binding<String>, onCommit: @escaping () -> Void) {
            _text = text
            self.onCommit = onCommit
        }

        @objc func dismissKeyboard() { _ = textField?.resignFirstResponder() }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool { true }

        @objc func textFieldDidChange(_ textField: UITextField) {
            if let t = textField.text { self.text = t }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {}

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            _ = textField.resignFirstResponder()
            DispatchQueue.main.async { [weak self] in self?.onCommit() }
            return true
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        if let frameWidth { return CGSize(width: frameWidth, height: uiView.intrinsicContentSize.height) }
        return nil
    }
}

// MARK: - View Modifiers for CursorAtEndTextField_SwiftUI

extension CursorAtEndTextField_SwiftUI {
    func multilineTextAlignment(_ alignment: TextAlignment) -> Self {
        var view = self
        switch alignment {
        case .leading:  view.textAlignment = .left
        case .center:   view.textAlignment = .center
        case .trailing: view.textAlignment = .right
        }
        return view
    }

    func keyboardType(_ type: UIKeyboardType) -> Self {
        var view = self; view.keyboardType = type; return view
    }

    func textInputAutocapitalization(_ type: TextInputAutocapitalization?) -> Self {
        var view = self
        guard let type else { view.autocapitalizationType = .words; return view }
        let d = String(describing: type)
        if d.contains("never")           { view.autocapitalizationType = .none }
        else if d.contains("words")      { view.autocapitalizationType = .words }
        else if d.contains("sentences")  { view.autocapitalizationType = .sentences }
        else if d.contains("characters") { view.autocapitalizationType = .allCharacters }
        return view
    }

    func frame(width: CGFloat) -> Self {
        var view = self; view.frameWidth = width; return view
    }

    func dismissKeyboardOnReturn(_ shouldDismiss: Bool) -> Self {
        var view = self; view.shouldDismissKeyboard = shouldDismiss; return view
    }

    func returnKey(_ type: UIReturnKeyType) -> Self {
        var view = self; view.returnKeyType = type; return view
    }

    func toolbarDoneButton(triggersCommit shouldTrigger: Bool) -> Self {
        var view = self; view.toolbarDoneTriggersCommit = shouldTrigger; return view
    }
}

// MARK: - Cursor-at-End UITextField Subclass

fileprivate class CursorAtEndUITextField: UITextField {
    private var hasPositionedCursorOnFocus = false

    override func closestPosition(to point: CGPoint) -> UITextPosition? {
        if !isFirstResponder || !hasPositionedCursorOnFocus { return endOfDocument }
        return super.closestPosition(to: point)
    }

    override func becomeFirstResponder() -> Bool {
        hasPositionedCursorOnFocus = false
        let result = super.becomeFirstResponder()
        if result {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let end = self.endOfDocument
                self.selectedTextRange = self.textRange(from: end, to: end)
                self.hasPositionedCursorOnFocus = true
            }
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        hasPositionedCursorOnFocus = false
        return super.resignFirstResponder()
    }

    override var selectedTextRange: UITextRange? {
        get { super.selectedTextRange }
        set { if isFirstResponder { super.selectedTextRange = newValue } }
    }
}
