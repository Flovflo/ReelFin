import NativeMediaCore
import XCTest

final class StreamingRangeWriterTests: XCTestCase {
    /// Regression for the on-device crash "Task created in a session that has been invalidated":
    /// when the cache loader is torn down (recovery) while the parallel fill is launching a window,
    /// `stream()` must NOT create a URLSession task on the invalidated session. It must finish the
    /// stream with an error instead — never crash.
    func testStreamAfterInvalidateFinishesWithoutCrashing() async {
        let writer = StreamingRangeWriter(configuration: .ephemeral)
        writer.invalidate()

        var request = URLRequest(url: URL(string: "https://example.com/clip")!)
        request.setValue("bytes=0-1048575", forHTTPHeaderField: "Range")
        let stream = writer.stream(request: request, startOffset: 0)

        var threw = false
        do {
            for try await _ in stream {}
        } catch {
            threw = true
        }
        XCTAssertTrue(threw, "stream() after invalidate must finish with an error (no task on the dead session), not crash or hang.")
    }

    /// Concurrent invalidate() + stream() must also be crash-safe (the real device race).
    func testConcurrentInvalidateAndStreamIsCrashSafe() async {
        let writer = StreamingRangeWriter(configuration: .ephemeral)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { writer.invalidate() }
            for _ in 0..<8 {
                group.addTask {
                    var request = URLRequest(url: URL(string: "https://example.com/clip")!)
                    request.setValue("bytes=0-1048575", forHTTPHeaderField: "Range")
                    let stream = writer.stream(request: request, startOffset: 0)
                    do { for try await _ in stream {} } catch {}
                }
            }
        }
        // Reaching here without a crash is the assertion.
        XCTAssertTrue(true)
    }
}
