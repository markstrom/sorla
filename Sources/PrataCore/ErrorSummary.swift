import Foundation

// Error descriptions can carry file paths with the user's name; logs get only the domain and code.
public enum ErrorSummary {
    public static func of(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }
}
