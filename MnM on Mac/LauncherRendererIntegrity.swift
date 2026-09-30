import Foundation

/// Developer ID signatures can enlarge __LINKEDIT.vmsize. Removing the
/// signature leaves that size behind; canonicalize only this signing metadata.
enum LauncherRendererIntegrity {
    static func canonical(_ raw: Data) throws -> Data {
        var bytes = [UInt8](raw)
        func fail() -> NSError {
            NSError(domain: "MnMLauncherRenderer", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The launcher renderer package is invalid."])
        }
        func word(_ offset: Int, bigEndian: Bool = false) throws -> Int {
            guard offset >= 0, offset <= bytes.count - 4 else { throw fail() }
            let parts = Array(bytes[offset..<offset + 4])
            return (bigEndian ? parts : Array(parts.reversed())).reduce(0) { ($0 << 8) | Int($1) }
        }
        guard try word(0, bigEndian: true) == 0xcafebabe,
              try word(4, bigEndian: true) == 2 else { throw fail() }
        for index in 0..<2 {
            let start = try word(8 + index * 20 + 8, bigEndian: true)
            let size = try word(8 + index * 20 + 12, bigEndian: true)
            guard size >= 32, start <= bytes.count, size <= bytes.count - start,
                  try word(start) == 0xfeedfacf else { throw fail() }
            let commands = try word(start + 16)
            let commandBytes = try word(start + 20)
            guard commandBytes <= size - 32 else { throw fail() }
            var cursor = start + 32
            let end = cursor + commandBytes
            var found = false
            for _ in 0..<commands {
                guard cursor <= end - 8 else { throw fail() }
                let command = try word(cursor)
                let length = try word(cursor + 4)
                guard length >= 8, length <= end - cursor else { throw fail() }
                if command == 0x19, length >= 72,
                   Array(bytes[cursor + 8..<cursor + 24]) == Array("__LINKEDIT".utf8) + Array(repeating: 0, count: 6) {
                    bytes.replaceSubrange(cursor + 32..<cursor + 40, with: repeatElement(UInt8(0), count: 8))
                    found = true
                }
                cursor += length
            }
            guard found else { throw fail() }
        }
        return Data(bytes)
    }
}
