// Ed25519 keys and signatures for Sparkle updates, using CryptoKit.
//
//   swift scripts/sparkle-keys.swift generate <dir>        writes <dir>/sparkle_ed25519.key, prints SUPublicEDKey
//   swift scripts/sparkle-keys.swift public <keyfile>      prints SUPublicEDKey for an existing key
//   swift scripts/sparkle-keys.swift sign <file> <keyfile> prints the base64 sparkle:edSignature
//   swift scripts/sparkle-keys.swift verify <file> <signature> <publicKey>
//
// The key file holds the base64-encoded 32-byte Ed25519 seed, the same format
// Sparkle's own tools (`generate_keys -x`, `sign_update --ed-key-file`) use.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadKey(_ path: String) -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8),
          let seed = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed.prefix(32)) else {
        fail("Cannot read an Ed25519 key from \(path)")
    }
    return key
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "generate" where args.count == 3:
    let url = URL(fileURLWithPath: args[2]).appendingPathComponent("sparkle_ed25519.key")
    if FileManager.default.fileExists(atPath: url.path) { fail("\(url.path) already exists; refusing to overwrite.") }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: Data(key.rawRepresentation.base64EncodedString().utf8),
                                   attributes: [.posixPermissions: 0o600])
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public" where args.count == 3:
    print(loadKey(args[2]).publicKey.rawRepresentation.base64EncodedString())
case "sign" where args.count == 4:
    guard let data = FileManager.default.contents(atPath: args[2]) else { fail("Cannot read \(args[2])") }
    print(try loadKey(args[3]).signature(for: data).base64EncodedString())
case "verify" where args.count == 5:
    guard let data = FileManager.default.contents(atPath: args[2]),
          let signature = Data(base64Encoded: args[3]),
          let publicData = Data(base64Encoded: args[4]),
          let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicData) else { fail("Bad input") }
    if publicKey.isValidSignature(signature, for: data) { print("valid") } else { fail("INVALID") }
default:
    fail("usage: sparkle-keys.swift generate <dir> | public <keyfile> | sign <file> <keyfile> | verify <file> <sig> <pubkey>")
}
