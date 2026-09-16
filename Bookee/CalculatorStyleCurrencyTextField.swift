//
//  CalculatorStyleCurrencyTextField.swift
//  Bookee
//
//  Created by Kara Eveland on 3/4/26.
//

import SwiftUI

// MARK: - Keyboard Accessory View

/// A custom keyboard accessory view that displays a toolbar with a "Done" button above the keyboard.
fileprivate class KeyboardAccessoryView: UIView {
    /// Action to execute when the Done button should trigger a commit (e.g., saving changes)
    var doneButtonAction: (() -> Void)?
    /// Action to execute when the Done button should only dismiss the keyboard without committing
    var dismissOnlyAction: (() -> Void)?
    /// Controls whether the Done button triggers the commit action (true) or just dismisses the keyboard (false)
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
        let doneButton = UIBarButtonItem(
            title: "Done",
            style: .plain,
            target: self,
            action: #selector(doneButtonTapped)
        )

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17, weight: .medium)
        ]
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
        return CGSize(width: UIView.noIntrinsicMetric, height: 52)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        toolbar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 44)
    }
}

// MARK: - Cursor-at-End Text Field (SwiftUI Wrapper)

/// A SwiftUI wrapper for a UITextField that automatically positions the cursor at the end when the field gains focus.
/// After the initial focus, users can manually reposition the cursor normally. Supports customization via modifiers.
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

        if let returnKeyType = returnKeyType {
            textField.returnKeyType = returnKeyType
        } else {
            textField.returnKeyType = .default
        }

        if showKeyboardToolbar {
            let accessoryView = KeyboardAccessoryView()
            accessoryView.toolbarDoneTriggersCommit = toolbarDoneTriggersCommit

            accessoryView.doneButtonAction = { [weak textField] in
                _ = textField?.resignFirstResponder()
                DispatchQueue.main.async {
                    context.coordinator.onCommit()
                }
            }

            accessoryView.dismissOnlyAction = { [weak textField] in
                _ = textField?.resignFirstResponder()
            }

            textField.inputAccessoryView = accessoryView
        }

        textField.addTarget(context.coordinator, action: #selector(Coordinator.textFieldDidChange(_:)), for: .editingChanged)

        textField.font = UIFont.preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
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
        if uiView.text != text {
            uiView.text = text
        }

        uiView.placeholder = placeholder
        uiView.textAlignment = textAlignment
        uiView.keyboardType = keyboardType
        uiView.autocapitalizationType = autocapitalizationType

        if let returnKeyType = returnKeyType {
            uiView.returnKeyType = returnKeyType
        } else {
            uiView.returnKeyType = .default
        }

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

        @objc func dismissKeyboard() {
            _ = textField?.resignFirstResponder()
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            return true
        }

        @objc func textFieldDidChange(_ textField: UITextField) {
            if let text = textField.text {
                self.text = text
            }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {}

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            _ = textField.resignFirstResponder()
            DispatchQueue.main.async { [weak self] in
                self?.onCommit()
            }
            return true
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        if let frameWidth = frameWidth {
            return CGSize(width: frameWidth, height: uiView.intrinsicContentSize.height)
        }
        return nil
    }
}

// MARK: - View Modifiers for CursorAtEndTextField_SwiftUI

extension CursorAtEndTextField_SwiftUI {
    /// Maps SwiftUI's TextAlignment enum to UIKit's NSTextAlignment
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
        var view = self
        view.keyboardType = type
        return view
    }

    /// Configures the automatic capitalization behavior for text input. Defaults to .words if nil.
    func textInputAutocapitalization(_ type: TextInputAutocapitalization?) -> Self {
        var view = self
        guard let type = type else {
            view.autocapitalizationType = .words
            return view
        }
        // Uses string description comparison since TextInputAutocapitalization doesn't conform to Equatable
        let description = String(describing: type)
        if description.contains("never")      { view.autocapitalizationType = .none }
        else if description.contains("words") { view.autocapitalizationType = .words }
        else if description.contains("sentences") { view.autocapitalizationType = .sentences }
        else if description.contains("characters") { view.autocapitalizationType = .allCharacters }
        return view
    }

    /// Sets an explicit width for the text field, overriding its intrinsic content size.
    func frame(width: CGFloat) -> Self {
        var view = self
        view.frameWidth = width
        return view
    }

    func dismissKeyboardOnReturn(_ shouldDismiss: Bool) -> Self {
        var view = self
        view.shouldDismissKeyboard = shouldDismiss
        return view
    }

    func returnKey(_ type: UIReturnKeyType) -> Self {
        var view = self
        view.returnKeyType = type
        return view
    }

    /// Controls whether the toolbar's Done button triggers the onCommit action or just dismisses the keyboard.
    func toolbarDoneButton(triggersCommit shouldTrigger: Bool) -> Self {
        var view = self
        view.toolbarDoneTriggersCommit = shouldTrigger
        return view
    }
}

// MARK: - Cursor-at-End UITextField Subclass

/// Custom UITextField subclass that automatically positions the cursor at the end when gaining focus.
/// After the initial focus, allows normal cursor repositioning through taps and gestures.
fileprivate class CursorAtEndUITextField: UITextField {

    private var hasPositionedCursorOnFocus = false

    override func closestPosition(to point: CGPoint) -> UITextPosition? {
        if !isFirstResponder || !hasPositionedCursorOnFocus {
            return endOfDocument
        }
        return super.closestPosition(to: point)
    }

    override func becomeFirstResponder() -> Bool {
        hasPositionedCursorOnFocus = false
        let result = super.becomeFirstResponder()
        if result {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let endPosition = self.endOfDocument
                self.selectedTextRange = self.textRange(from: endPosition, to: endPosition)
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
        get { return super.selectedTextRange }
        set {
            if isFirstResponder {
                super.selectedTextRange = newValue
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        return super.intrinsicContentSize
    }
}

// MARK: - Calculator-Style Currency Text Field

/// A currency text field that formats input like a calculator.
///
/// Numbers are added from right to left, starting at cents. Each digit typed shifts previous digits left.
/// - Typing "1" shows "$0.01"
/// - Typing "2" next shows "$0.12"
/// - Typing "3" next shows "$1.23"
///
/// The field uses a number pad keyboard and limits input to 10 digits (max $99,999,999.99).
/// Currency is formatted with comma separators and always displays two decimal places.
struct CalculatorStyleCurrencyTextField: View {
    /// The currency amount in dollars (e.g., 1.23 for $1.23)
    @Binding var amount: Decimal

    /// Binding to control the focused state of the text field
    var isFocused: FocusState<Bool>.Binding

    /// Placeholder text shown when the field is empty (default: "$0.00")
    let placeholder: String

    /// Closure called when editing completes (keyboard dismissed or focus lost)
    let onCommit: () -> Void

    @State private var textValue: String = ""

    init(amount: Binding<Decimal>, isFocused: FocusState<Bool>.Binding, placeholder: String = "$0.00", onCommit: @escaping () -> Void = {}) {
        self._amount = amount
        self.isFocused = isFocused
        self.placeholder = placeholder
        self.onCommit = onCommit
    }

    var body: some View {
        CursorAtEndTextField_SwiftUI(text: $textValue, placeholder: placeholder) {
            onCommit()
        }
        .multilineTextAlignment(.trailing)
        .keyboardType(.numberPad)
        .dismissKeyboardOnReturn(true)
        .focused(isFocused)
        .onChange(of: textValue) { oldValue, newValue in
            handleTextChange(oldValue: oldValue, newValue: newValue)
        }
        .onAppear {
            updateTextFromAmount()
        }
        .onChange(of: amount) { _, _ in
            if !isFocused.wrappedValue {
                updateTextFromAmount()
            }
        }
        .onChange(of: isFocused.wrappedValue) { _, focused in
            if !focused {
                onCommit()
            }
        }
    }

    private func handleTextChange(oldValue: String, newValue: String) {
        let digits = newValue.filter { $0.isNumber }
        let limitedDigits = String(digits.prefix(10))

        guard !limitedDigits.isEmpty else {
            textValue = formatCurrency(cents: 0)
            amount = 0
            return
        }

        guard let cents = Int(limitedDigits) else {
            textValue = oldValue
            return
        }

        amount = Decimal(cents) / 100
        textValue = formatCurrency(cents: cents)
    }

    private func formatCurrency(cents: Int) -> String {
        let dollars = cents / 100
        let remainingCents = cents % 100

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","

        let dollarsString = formatter.string(from: NSNumber(value: dollars)) ?? "0"
        let centsString = String(format: "%02d", remainingCents)

        return "$\(dollarsString).\(centsString)"
    }

    private func updateTextFromAmount() {
        let cents = NSDecimalNumber(decimal: amount.roundedMoney() * 100).int64Value
        textValue = formatCurrency(cents: Int(cents))
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var amount: Decimal = 0
        @FocusState private var isFocused: Bool

        var body: some View {
            Form {
                Section {
                    HStack {
                        Text("Amount")
                            .contentShape(Rectangle())
                            .onTapGesture { isFocused = true }
                        Spacer()
                            .contentShape(Rectangle())
                            .onTapGesture { isFocused = true }
                        CalculatorStyleCurrencyTextField(amount: $amount, isFocused: $isFocused) {
                            print("Committed with amount: $\(amount)")
                        }
                    }

                    Text("Current value: $\(amount, format: .number.precision(.fractionLength(2)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    return PreviewWrapper()
}
