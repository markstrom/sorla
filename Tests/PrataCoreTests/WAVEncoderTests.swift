import XCTest
@testable import PrataCore

final class WAVEncoderTests: XCTestCase {
    private func uint32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<offset + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) }
    }

    private func uint16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func int16(_ data: Data, at offset: Int) -> Int16 {
        Int16(bitPattern: uint16(data, at: offset))
    }

    private func ascii(_ data: Data, at offset: Int) -> String {
        String(decoding: data[offset..<offset + 4], as: UTF8.self)
    }

    func testHeaderDescribesMono16BitPCM() {
        let data = WAVEncoder.encode([0, 0.5, -0.5], sampleRate: 48_000)

        XCTAssertEqual(ascii(data, at: 0), "RIFF")
        XCTAssertEqual(uint32(data, at: 4), UInt32(data.count - 8))
        XCTAssertEqual(ascii(data, at: 8), "WAVE")
        XCTAssertEqual(ascii(data, at: 12), "fmt ")
        XCTAssertEqual(uint32(data, at: 16), 16)
        XCTAssertEqual(uint16(data, at: 20), 1)
        XCTAssertEqual(uint16(data, at: 22), 1)
        XCTAssertEqual(uint32(data, at: 24), 48_000)
        XCTAssertEqual(uint32(data, at: 28), 96_000)
        XCTAssertEqual(uint16(data, at: 32), 2)
        XCTAssertEqual(uint16(data, at: 34), 16)
        XCTAssertEqual(ascii(data, at: 36), "data")
        XCTAssertEqual(uint32(data, at: 40), 6)
        XCTAssertEqual(data.count, 44 + 6)
    }

    func testSamplesAreScaledAndClampedToInt16() {
        let data = WAVEncoder.encode([0, 0.5, -1, 2, -2], sampleRate: 48_000)

        XCTAssertEqual(int16(data, at: 44), 0)
        XCTAssertEqual(int16(data, at: 46), 16_384)
        XCTAssertEqual(int16(data, at: 48), -32_767)
        XCTAssertEqual(int16(data, at: 50), 32_767)
        XCTAssertEqual(int16(data, at: 52), -32_767)
    }
}
