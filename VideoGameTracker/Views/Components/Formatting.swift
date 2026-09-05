import Foundation

enum Money {
    /// `$1,234` — whole-dollar currency, which is precise enough for a hobby tracker.
    static func string(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// `+$120` / `−$30` for deltas.
    static func signedString(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        let sign = value < 0 ? "−" : "+"
        let magnitude = abs(value)
        return sign + magnitude.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}

extension Date {
    var yearString: String { formatted(.dateTime.year()) }
    var mediumDateString: String { formatted(.dateTime.month(.abbreviated).day().year()) }
}
