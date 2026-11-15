/// Uniform draws for the vault's generators (`VAULT.md` § 9.7): an index below a bound by rejection, never by a bare
/// modulo, which would favor the first values whenever the bound doesn't divide 2⁶⁴.
nonisolated extension RandomNumberGenerator {
    /// An index in `0 ..< count`, every value equally likely: a 64-bit draw is masked down to the smallest power of two
    /// that holds `count`, and drawn again while it lands at or above `count` (fewer than two draws on average). The
    /// generator must be a real random source: one stuck above `count` would never return.
    mutating func uniformIndex(below count: Int) -> Int {
        precondition(count > 0, "Uniform index below a bound that isn't positive")
        let bound = UInt64(count)
        let mask = UInt64.max >> (bound - 1).leadingZeroBitCount
        while true {
            let value = next() & mask
            if value < bound {
                return Int(value)
            }
        }
    }
}
