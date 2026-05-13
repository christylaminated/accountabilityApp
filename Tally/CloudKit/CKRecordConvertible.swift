import CloudKit
import Foundation

/// Conformance lets a Swift model materialize from / serialize to a `CKRecord`.
/// Repositories use this on every read and write — fetched records are decoded
/// via `init?(record:)`, and outgoing writes are built via `toRecord(recordID:parent:)`.
///
/// Convention:
///   • `recordType` matches the record type declared in CloudKit Dashboard.
///   • `init(record:)` is failable — returns `nil` when required fields are missing
///     (e.g., a partially-synced record from an older app version).
///   • `populate(_:)` writes the model's fields onto an *existing* record,
///     preserving system fields. Used when updating an already-fetched record.
protocol CKRecordConvertible {
    static var recordType: String { get }

    init?(record: CKRecord)
    func populate(_ record: CKRecord)
}

extension CKRecordConvertible {
    /// Build a fresh `CKRecord` for this model with the given recordID. Optionally
    /// attach a `parent` reference so the new record rides along with its parent's
    /// `CKShare` (required for any record meant to be visible to Circle participants).
    func toRecord(
        recordID: CKRecord.ID,
        parent: CKRecord.Reference? = nil
    ) -> CKRecord {
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        if let parent {
            record.parent = parent
        }
        populate(record)
        return record
    }
}
