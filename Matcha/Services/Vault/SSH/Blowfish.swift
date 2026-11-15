import Foundation

/// Blowfish (Schneier, 1993) as OpenBSD's `blf.c` has it for `bcrypt_pbkdf` (`BcryptPBKDF`): the standard key schedule
/// (`Blowfish_expand0state`), EksBlowfish's salted one (`Blowfish_expandstate`), and the encryption of 64-bit blocks.
/// The 18 subkeys and the 4 S-boxes live in one buffer of 1 042 words, subkeys first, so that both schedules rewrite it
/// in a single pass. Written to stay fast without optimization (debug builds, tests): a raw buffer and concrete integer
/// operations only. Not thread-safe: one instance per derivation. Pure type.
final nonisolated class Blowfish {
    /// 18 subkeys (the P-array), then 4 S-boxes of 256 words.
    static let wordCount = 18 + 4 * 256
    private static let subkeyCount = 18

    private let state: UnsafeMutablePointer<UInt32>

    /// The initial state: pi's digits (`Blowfish_initstate`).
    init() {
        state = .allocate(capacity: Self.wordCount)
        reset()
    }

    /// Standard Blowfish keyed with `key` (1 to 72 bytes), for the published test vectors.
    convenience init(key: [UInt8]) {
        self.init()
        expand(key: key)
    }

    deinit {
        state.update(repeating: 0, count: Self.wordCount)
        state.deallocate()
    }

    /// Back to the initial state, pi's digits.
    func reset() {
        Self.initialState.withUnsafeBufferPointer { initial in
            if let base = initial.baseAddress {
                state.update(from: base, count: Self.wordCount)
            }
        }
    }

    /// `Blowfish_expand0state`: `key` XORed into the subkeys, then the whole state replaced, two words at a time, by the
    /// successive encryptions of a zero block.
    func expand(key: [UInt8]) {
        xorSubkeys(with: key)
        var left: UInt32 = 0
        var right: UInt32 = 0
        var index = 0
        while index < Self.wordCount {
            encipher(&left, &right)
            state[index] = left
            state[index + 1] = right
            index += 2
        }
    }

    /// `Blowfish_expandstate`: like `expand(key:)`, but the next 8 bytes of `data` (the salt, read cyclically) are
    /// XORed into the block before each encryption.
    func expand(key: [UInt8], data: [UInt8]) {
        xorSubkeys(with: key)
        var left: UInt32 = 0
        var right: UInt32 = 0
        var position = 0
        var index = 0
        while index < Self.wordCount {
            left ^= Self.word(of: data, at: &position)
            right ^= Self.word(of: data, at: &position)
            encipher(&left, &right)
            state[index] = left
            state[index + 1] = right
            index += 2
        }
    }

    /// The subkeys XORed with `key`, read cyclically.
    private func xorSubkeys(with key: [UInt8]) {
        var position = 0
        for index in 0 ..< Self.subkeyCount {
            state[index] ^= Self.word(of: key, at: &position)
        }
    }

    /// `Blowfish_stream2word`: the next 4 bytes of `bytes`, big-endian, starting over at the end; 0 if `bytes` is empty.
    static func word(of bytes: [UInt8], at position: inout Int) -> UInt32 {
        guard !bytes.isEmpty else {
            return 0
        }
        var word: UInt32 = 0
        for _ in 0 ..< 4 {
            if position >= bytes.count {
                position = 0
            }
            word = (word &<< 8) | UInt32(bytes[position])
            position += 1
        }
        return word
    }

    /// Encrypts one block, given as its two big-endian halves (`Blowfish_encipher`): 16 Feistel rounds.
    func encipher(_ left: inout UInt32, _ right: inout UInt32) {
        let boxes = state + Self.subkeyCount
        var leftHalf = left ^ state[0]
        var rightHalf = right
        var round = 1
        while round < 17 {
            rightHalf ^= Self.feistel(boxes, leftHalf) ^ state[round]
            leftHalf ^= Self.feistel(boxes, rightHalf) ^ state[round + 1]
            round += 2
        }
        left = rightHalf ^ state[17]
        right = leftHalf
    }

    /// The round function: `((S0[a] + S1[b]) ^ S2[c]) + S3[d]` for the four bytes `a b c d` of `half`.
    @inline(__always)
    private static func feistel(_ boxes: UnsafeMutablePointer<UInt32>, _ half: UInt32) -> UInt32 {
        let first = boxes[Int(half &>> 24)]
        let second = boxes[256 + Int((half &>> 16) & 0xFF)]
        let third = boxes[512 + Int((half &>> 8) & 0xFF)]
        let fourth = boxes[768 + Int(half & 0xFF)]
        return ((first &+ second) ^ third) &+ fourth
    }
}
