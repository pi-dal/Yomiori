import Foundation
import Testing
@testable import Kotoba

struct AudioCacheTests {
    @Test func importedRecordingURLsDoNotAlias() throws {
        let addresses = ["https://a.example/audio/one.mp3", "https://b.example/audio/one.mp3", "https://a.example/audio/one.mp3?v=1", "https://a.example/audio/one.mp3?v=2", "https://a.example/audio_one.mp3", "https://a.example/audio?id=one", "https://a.example/audio?id=two"]
        let keys = try addresses.map { AtlasPronunciationPlayer.cacheFilename(for: try #require(URL(string: $0))) }
        #expect(Set(keys).count == addresses.count)
        #expect(keys[0] == AtlasPronunciationPlayer.cacheFilename(for: try #require(URL(string: addresses[0]))))
        #expect(keys.allSatisfy { !$0.contains("/") && !$0.contains("?") })
    }
}
