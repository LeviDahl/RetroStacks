import SwiftUI

extension Binding where Value == Decimal? {
    /// Bridges an optional `Decimal` to a non-optional field, treating 0 as "unset".
    var orZero: Binding<Decimal> {
        Binding<Decimal>(
            get: { wrappedValue ?? 0 },
            set: { wrappedValue = $0 == 0 ? nil : $0 }
        )
    }
}

extension Binding where Value == String? {
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

extension Binding where Value == Date? {
    /// Presents an optional date as (Bool, Date) so a `Toggle` + `DatePicker` pair works.
    var presence: Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { wrappedValue = $0 ? (wrappedValue ?? .now) : nil }
        )
    }
    var orNow: Binding<Date> {
        Binding<Date>(
            get: { wrappedValue ?? .now },
            set: { wrappedValue = $0 }
        )
    }
}
