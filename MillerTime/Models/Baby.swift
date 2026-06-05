import Foundation
import SwiftData

/// The baby being tracked. v1 has exactly one; the model stays relational so a
/// future sibling needs a baby switcher, not a schema migration.
@Model
final class Baby {
    var id: UUID = UUID()
    var name: String = ""
    var dateOfBirth: Date = Date()
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String, dateOfBirth: Date, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.dateOfBirth = dateOfBirth
        self.createdAt = createdAt
    }
}
