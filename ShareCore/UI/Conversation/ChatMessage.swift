import Foundation

public struct ChatMessage: Identifiable {
    public let id: UUID
    public let role: String // "system", "user", "assistant"
    public var content: String
    public var images: [ImageAttachment]
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: String,
        content: String,
        images: [ImageAttachment] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.images = images
        self.timestamp = timestamp
    }
}
