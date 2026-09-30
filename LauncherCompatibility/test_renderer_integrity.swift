import Foundation
import CryptoKit

@main struct RendererIntegrityTest {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 4 else { fatalError("Usage: test source-dylib signed-dylib manifest") }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("mnm-renderer-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[3]))) as! [String: Any]
        let expected = (manifest["files"] as! [String: String])["MnMLauncherRetina.dylib"]!
        func digest(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        for index in 1...2 {
            let copy = temporary.appendingPathComponent("renderer-\(index).dylib")
            try FileManager.default.copyItem(at: URL(fileURLWithPath: args[index]), to: copy)
            // Check canonical hashing here; production separately verifies trust.
            // The tool sandbox cannot resolve Developer ID certificate trust.
            for command in [["--remove-signature", copy.path]] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                process.arguments = command
                try process.run(); process.waitUntilExit()
                precondition(process.terminationStatus == 0)
            }
            let raw = try Data(contentsOf: copy)
            let canonical = try LauncherRendererIntegrity.canonical(raw)
            precondition(digest(canonical) == expected, "Signed/unsigned canonical checksum mismatch")
            var expanded = raw
            func word(_ offset: Int, big: Bool = false) -> Int {
                let bytes = Array(raw[offset..<offset + 4])
                return (big ? bytes : Array(bytes.reversed())).reduce(0) { ($0 << 8) | Int($1) }
            }
            for slice in 0..<2 {
                let start = word(8 + slice * 20 + 8, big: true)
                var cursor = start + 32
                for _ in 0..<word(start + 16) {
                    if word(cursor) == 0x19,
                       Array(raw[cursor + 8..<cursor + 24]) == Array("__LINKEDIT".utf8) + Array(repeating: 0, count: 6) {
                        expanded[cursor + 33] ^= 0xc0 // Simulate signature-induced virtual-size expansion.
                    }
                    cursor += word(cursor + 4)
                }
            }
            let expandedCanonical = try LauncherRendererIntegrity.canonical(expanded)
            precondition(expandedCanonical == canonical, "Release signing metadata must not break verification")
            var altered = raw
            altered[0x4500] ^= 1
            let alteredCanonical = try LauncherRendererIntegrity.canonical(altered)
            precondition(digest(alteredCanonical) != expected,
                         "Executable tampering must still fail integrity checks")
        }
        do {
            _ = try LauncherRendererIntegrity.canonical(Data(repeating: 0, count: 8))
            fatalError("Malformed renderer accepted")
        } catch {}
        print("Renderer integrity passed: packaged/source assets, release-signing size expansion, code tampering, malformed input.")
    }
}
