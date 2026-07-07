import CloudKit
import Foundation

/// Classifies CloudKit errors into a few human-meaningful buckets so the
/// UI can pick the right explainer sheet.
///
/// Why this is non-trivial: CloudKit surfaces the same underlying
/// condition in three different shapes — sometimes as a top-level
/// `CKError`, sometimes wrapped in a `.partialFailure` whose real reason
/// lives in `partialErrorsByItemID`, and sometimes as a generic `NSError`
/// with a `CKError` (or another `NSError`) tucked under
/// `NSUnderlyingErrorKey`. On top of that, certain bridges deliver the
/// error without a matching `CKError.Code` at all — the only signal is
/// the word "quota" / "authenticated" / "network" in the localized
/// description. The walker below flattens all of that so callers get a
/// single boolean per concern.
enum ICloudErrorDetection {
    static func isQuotaExceeded(_ error: Error) -> Bool {
        let codes = effectiveCKErrorCodes(from: error)
        if codes.contains(.quotaExceeded) { return true }
        return collectedText(from: error).contains("quota")
    }

    static func isAuthError(_ error: Error) -> Bool {
        let codes = effectiveCKErrorCodes(from: error)
        if codes.contains(.notAuthenticated) { return true }
        return collectedText(from: error).contains("not authenticated")
    }

    static func isNetworkError(_ error: Error) -> Bool {
        let codes = effectiveCKErrorCodes(from: error)
        if codes.contains(.networkUnavailable) || codes.contains(.networkFailure) {
            return true
        }
        let text = collectedText(from: error)
        // Match "network" but avoid a false positive on the literal word in
        // unrelated messages — these are the phrasings CloudKit / URLSession
        // actually produce.
        return text.contains("network connection")
            || text.contains("internet connection")
            || text.contains("network is unavailable")
            || text.contains("network failure")
    }

    /// Returns every `CKError.Code` reachable from `error` — at the top
    /// level, inside a `.partialFailure`'s `partialErrorsByItemID`, or
    /// down the `NSUnderlyingErrorKey` chain. Lets callers match on the
    /// real condition no matter which layer CloudKit surfaced it at.
    private static func effectiveCKErrorCodes(from error: Error) -> Set<CKError.Code> {
        var out: Set<CKError.Code> = []
        walk(error) { err in
            if let ck = err as? CKError { out.insert(ck.code) }
        }
        return out
    }

    /// Concatenates the lowercased localized descriptions of every error
    /// in the tree, for substring-fallback matching when no `CKError.Code`
    /// is present.
    private static func collectedText(from error: Error) -> String {
        var parts: [String] = []
        walk(error) { err in
            parts.append(err.localizedDescription.lowercased())
        }
        return parts.joined(separator: " ")
    }

    /// Depth-first walk over `error`, its `partialErrorsByItemID` (if a
    /// `CKError.partialFailure`), and its `NSUnderlyingErrorKey` chain.
    /// The visit closure receives each node exactly once.
    private static func walk(_ error: Error, visit: (Error) -> Void) {
        visit(error)
        if let ck = error as? CKError, let partial = ck.partialErrorsByItemID {
            for sub in partial.values {
                walk(sub as Error, visit: visit)
            }
        }
        let ns = error as NSError
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            // Skip when the underlying error is a CKError with the same
            // code — Apple has historically nested a CKError under itself
            // in some builds, and recursing would loop.
            let parentCKCode = (error as? CKError)?.code
            let underlyingCKCode = (underlying as? CKError)?.code
            if parentCKCode == nil || parentCKCode != underlyingCKCode {
                walk(underlying, visit: visit)
            }
        }
    }
}
