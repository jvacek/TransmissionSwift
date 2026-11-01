import Foundation

/// A decoded bencode value ([BEP 3](https://www.bittorrent.org/beps/bep_0003.html)).
///
/// Deliberately internal: the package's surface is `TorrentMetainfo`, and
/// bencode is just how a `.torrent` file is stored on disk.
enum Bencode: Equatable, Sendable {
    case integer(Int)
    case bytes([UInt8])
    case list([Bencode])
    case dictionary([String: Bencode])
}

extension Bencode {
    var integer: Int? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    var bytes: [UInt8]? {
        guard case .bytes(let value) = self else { return nil }
        return value
    }

    var list: [Bencode]? {
        guard case .list(let value) = self else { return nil }
        return value
    }

    var dictionary: [String: Bencode]? {
        guard case .dictionary(let value) = self else { return nil }
        return value
    }

    /// Dictionary lookup. Only ever called on the top level and on `info`,
    /// which the spec guarantees are dictionaries.
    subscript(key: String) -> Bencode? {
        dictionary?[key]
    }
}

/// Why a byte sequence isn't valid bencode. Internal — mapped to
/// `TorrentMetainfoError.malformedBencode` at the package boundary.
enum BencodeDecodingError: Error, Equatable, Sendable {
    case unexpectedEnd(offset: Int)
    case invalidToken(offset: Int)
    case invalidInteger(offset: Int)
    case invalidStringLength(offset: Int)
    case invalidDictionaryKey(offset: Int)
    case trailingBytes(count: Int)
}

/// Recursive-descent bencode decoder. Every read is bounds-checked, so
/// untrusted input — a user-picked `.torrent` — throws rather than trapping.
enum BencodeDecoder {
    static func decode(_ data: Data) throws -> Bencode {
        var parser = Parser(bytes: [UInt8](data))
        let value = try parser.parseValue()
        try parser.finish()
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func parseValue() throws -> Bencode {
            guard index < bytes.count else {
                throw BencodeDecodingError.unexpectedEnd(offset: index)
            }
            switch bytes[index] {
            case Self.i: return try parseInteger()
            case Self.l: return try parseList()
            case Self.d: return try parseDictionary()
            case Self.zero...Self.nine: return try parseBytes()
            default: throw BencodeDecodingError.invalidToken(offset: index)
            }
        }

        mutating func finish() throws {
            guard index == bytes.count else {
                throw BencodeDecodingError.trailingBytes(count: bytes.count - index)
            }
        }

        // MARK: - Values

        private mutating func parseInteger() throws -> Bencode {
            let start = index
            index += 1  // 'i'
            let valueStart = index
            if index < bytes.count, bytes[index] == Self.minus {
                index += 1
            }
            let digitsStart = index
            while index < bytes.count, Self.isDigit(bytes[index]) {
                index += 1
            }
            guard index > digitsStart, index < bytes.count, bytes[index] == Self.e else {
                throw BencodeDecodingError.invalidInteger(offset: start)
            }
            let text = String(decoding: bytes[valueStart..<index], as: UTF8.self)
            index += 1  // 'e'
            guard let value = Int(text) else {
                throw BencodeDecodingError.invalidInteger(offset: start)
            }
            return .integer(value)
        }

        private mutating func parseBytes() throws -> Bencode {
            let start = index
            var length = 0
            while index < bytes.count, Self.isDigit(bytes[index]) {
                length = length * 10 + Int(bytes[index] - Self.zero)
                guard length <= bytes.count else {
                    throw BencodeDecodingError.invalidStringLength(offset: start)
                }
                index += 1
            }
            guard index > start, index < bytes.count, bytes[index] == Self.colon else {
                throw BencodeDecodingError.invalidStringLength(offset: start)
            }
            index += 1  // ':'
            guard index + length <= bytes.count else {
                throw BencodeDecodingError.unexpectedEnd(offset: index)
            }
            let value = Array(bytes[index..<(index + length)])
            index += length
            return .bytes(value)
        }

        private mutating func parseList() throws -> Bencode {
            index += 1  // 'l'
            var items: [Bencode] = []
            while true {
                guard index < bytes.count else {
                    throw BencodeDecodingError.unexpectedEnd(offset: index)
                }
                if bytes[index] == Self.e {
                    index += 1
                    return .list(items)
                }
                items.append(try parseValue())
            }
        }

        private mutating func parseDictionary() throws -> Bencode {
            index += 1  // 'd'
            var entries: [String: Bencode] = [:]
            while true {
                guard index < bytes.count else {
                    throw BencodeDecodingError.unexpectedEnd(offset: index)
                }
                if bytes[index] == Self.e {
                    index += 1
                    return .dictionary(entries)
                }
                let keyStart = index
                guard case .bytes(let keyBytes) = try parseValue(),
                    let key = String(bytes: keyBytes, encoding: .utf8)
                else {
                    throw BencodeDecodingError.invalidDictionaryKey(offset: keyStart)
                }
                entries[key] = try parseValue()
            }
        }

        // MARK: - Tokens

        private static let i = UInt8(ascii: "i")
        private static let l = UInt8(ascii: "l")
        private static let d = UInt8(ascii: "d")
        private static let e = UInt8(ascii: "e")
        private static let zero = UInt8(ascii: "0")
        private static let nine = UInt8(ascii: "9")
        private static let minus = UInt8(ascii: "-")
        private static let colon = UInt8(ascii: ":")

        private static func isDigit(_ byte: UInt8) -> Bool {
            byte >= zero && byte <= nine
        }
    }
}
