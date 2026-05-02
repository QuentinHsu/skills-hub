import Foundation

extension Date {
    var appTimestampString: String {
        Self.appTimestampFormatter.string(from: self)
    }

    private static let appTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
