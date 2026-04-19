import CryptoKit
import Foundation

public protocol FileFingerprinting: Sendable {
    func fingerprint(file_url: URL, metadata: StableFileMetadata) async throws -> FileFingerprint
}

public struct SHA256FileFingerprintService: FileFingerprinting {
    public init() {}

    public func fingerprint(file_url: URL, metadata: StableFileMetadata) async throws -> FileFingerprint {
        let hash = try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: file_url, options: [.mappedIfSafe])
            return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        }.value

        return FileFingerprint(file_hash: hash, file_size: metadata.file_size, modified_at_fs: metadata.modified_at_fs)
    }
}
