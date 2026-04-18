import SwiftUI

// MARK: — Typed Action Handlers for Menu Commands

struct ArbiterActions {
    var execute:  () -> Void = {}
    var validate: () -> Void = {}
    var abort:    () -> Void = {}
}

// MARK: — FocusedValue Key

struct ArbiterActionsKey: FocusedValueKey {
    typealias Value = ArbiterActions
}

extension FocusedValues {
    var arbiterActions: ArbiterActions? {
        get { self[ArbiterActionsKey.self] }
        set { self[ArbiterActionsKey.self] = newValue }
    }
}
