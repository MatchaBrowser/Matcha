import Foundation

/// The SSH key types of the vault (`VAULT.md` § 9.4), by their OpenSSH name, which is what an item's `keyType` holds.
/// Ed25519 is the default. Pure type.
nonisolated enum SSHKeyType: String, CaseIterable, Sendable {
    case ed25519 = "ssh-ed25519"
    case ecdsaP256 = "ecdsa-sha2-nistp256"
    case ecdsaP384 = "ecdsa-sha2-nistp384"
    case rsa = "ssh-rsa"

    /// The curve's name inside ECDSA keys (`nistp256`); nil for the other types.
    var curveName: String? {
        switch self {
        case .ecdsaP256: "nistp256"
        case .ecdsaP384: "nistp384"
        case .ed25519, .rsa: nil
        }
    }

    /// Size in bytes of an ECDSA private scalar; nil for the other types.
    var scalarSize: Int? {
        switch self {
        case .ecdsaP256: 32
        case .ecdsaP384: 48
        case .ed25519, .rsa: nil
        }
    }
}
