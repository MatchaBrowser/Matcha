import Foundation

/// SSH keys for the import tests: made by `ssh-keygen` (OpenSSH 10), their PKCS#8 by Python `cryptography`; the RSA
/// key is the one of the CXF example (Appendix A, errata 2026-03-09), its public key and fingerprint computed by Python.
enum VaultImportFixtures {
    static let ed25519OpenSSH = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACCXKZCo55PejSY/FnzC1B3HYN+5ZtCiz9MxgNdj8RoAsAAAAJAok3xQKJN8
    UAAAAAtzc2gtZWQyNTUxOQAAACCXKZCo55PejSY/FnzC1B3HYN+5ZtCiz9MxgNdj8RoAsA
    AAAEB3SoxHEnkSmhxrlARlGsONfuRoAp5/AYImtd+noZkXF5cpkKjnk96NJj8WfMLUHcdg
    37lm0KLP0zGA12PxGgCwAAAADHRlc3RAZWQyNTUxOQE=
    -----END OPENSSH PRIVATE KEY-----

    """
    static let ed25519Public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJcpkKjnk96NJj8WfMLUHcdg37lm0KLP0zGA12PxGgCw test@ed25519"
    static let ed25519Fingerprint = "SHA256:sfzLWxVtWOo88cP8tGyLGygC+BvS55tO0v6D/gVZ1lo"
    static let ed25519PKCS8 = "MC4CAQAwBQYDK2VwBCIEIHdKjEcSeRKaHGuUBGUaw41+5GgCnn8Bgia136ehmRcX"

    static let p256OpenSSH = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAaAAAABNlY2RzYS
    1zaGEyLW5pc3RwMjU2AAAACG5pc3RwMjU2AAAAQQRjvtotEuRfU5DKxz0mXlSs7nhQtAMv
    OKAEYR2vW27TTXQEpFM36v9NIVzinSagDltLw+CCmCvxGP69wNqFQ21tAAAAqEaUokFGlK
    JBAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBGO+2i0S5F9TkMrH
    PSZeVKzueFC0Ay84oARhHa9bbtNNdASkUzfq/00hXOKdJqAOW0vD4IKYK/EY/r3A2oVDbW
    0AAAAgWV3u/MXpmV9kZgWQR4A6j8Qs8LCXBiD9QzzbLnUPzAEAAAAJdGVzdEBwMjU2AQID
    BAUGBw==
    -----END OPENSSH PRIVATE KEY-----

    """
    static let p256Public = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBGO+2i0S5F9TkMrHPSZeVKzueFC0Ay84"
        + "oARhHa9bbtNNdASkUzfq/00hXOKdJqAOW0vD4IKYK/EY/r3A2oVDbW0= test@p256"
    static let p256Fingerprint = "SHA256:R4VA+VQ7TszoMNLt8x15orp1jD9WoC7kiEn+sUjDaCE"
    static let p256PKCS8 = "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgWV3u/MXpmV9kZgWQR4A6j8Qs8LCXBiD9QzzbLnUPzAGhRANCAARjvtot"
        + "EuRfU5DKxz0mXlSs7nhQtAMvOKAEYR2vW27TTXQEpFM36v9NIVzinSagDltLw+CCmCvxGP69wNqFQ21t"

    /// RSA 3072, PKCS#8 in `b64url`.
    static let rsaPKCS8 = [
        "MIIG_QIBADANBgkqhkiG9w0BAQEFAASCBucwggbjAgEAAoIBgQCn4-QiJojZ9mgc9KYJIvDWGaz4qFhf0CButg6L8zEoHKwuiN-mqcEciCCOa9BNiJm",
        "m8NTTehZvrrglGG59zIbqYtDAHjVn-vtb49xPzIv-M651Yqj08lIbR9tEIHKCq7aH8GlDm8NgG9EzJGjlL7okQym4TH1MHl-s4mUyr_qb2unlZBDixA",
        "QsphU8iCLftukWCIkmQg4CSj1Gh3WbBlZ-EX5eW0EXuAw4XsSbBTWV9CHRowVIpYqPvEYSpHsoCjEcd988p19hpiGknA0J4z7JfUlNgyT_1chb8GCTD",
        "T-2DCBRApbsIg6TOBVS-PR6emAQ3eZzUW0-3_oRM4ip0ujltQy8uU6gvYIAqx5wXGMThVpZcUgahKiSsVo_s4b84iMe4DG3W8jz4qi6yyNv0VedEzPU",
        "Z1lXd1GJFoy9uKNuSTe-1ksicAcluZN6LuNsPHcPxFCzOcmoNnVXEKAXInt-ys__5CDVasroZSAHZnDjUD4oNsLI3VIOnGxgXrkwSH0CAwEAAQKCAYA",
        "A2SDMf7OBHw1OGM9OQa1ZS4u-ktfQHhn31-FxbrhWGp-lDt8gYABVf6Y4dKN6rMtn7D9gVSAlZCAn3Hx8aWAvcXHaspxe9YXiZDTh-Kd8EIXxBQn-Ti",
        "DA5LH0dryABqmMp20vYKtR7OS3lIIXfFBSrBMwdunKzLwmKwZLWq0SWf6vVbwpxRyR9CyByodF6DjmZK3QB2qQ3jqlL1HWXL0VnyArY7HLvUvfLLK4v",
        "MPqnsSH-FdHvhcEhwqMlWT44g-fhqWtCJNnjDgLK3FPbI8Pz9TF8dWJvOmp5Q6iSBua1e9x2LizVuNSqiFc7ZTLeoG4nDj7T2BtqB0E1rNUDEN1aBo-",
        "UZmHJK7LrzfW_B-ssi2WwIpfxYa1lO6HFod5_YQiXV1GunyH1chCsbvOFtXvAHASO4HTKlJNbWhRF1GXqnKpAaHDPCVuwp3eq6Yf0oLbXrL3KFZ3jwW",
        "iWbpQXRVvpqzaJwZn3CN1yQgYS9j17a9wrPky-BoJxXjZ_oImWLECgcEA0lkLwiHvmTYFTCC7PN938Agk9_NQs5PQ18MRn9OJmyfSpYqf_gNp-Md7xU",
        "gtF_MTif7uelp2J7DYf6fj9EYf9g4EuW-SQgFP4pfiJn1-zGFeTQq1ISvwjsA4E8ZSt-GIumjZTg6YiL1_A79u4wm24swt7iqnVViOPtPGOM34S1tAa",
        "mjZzq2eZDmAF6pAfmuTMdinCMR1E1kNJYbxeqLiqQCXuwBBnHOOOJofN3AkvzjRUBB9udvniqYxH3PQcxPxAoHBAMxT5KwBhZhnJedYN87Kkcpl7xdM",
        "kpU8b-aXeZoNykCeoC-wgIQexnSWmFk4HPkCNxvCWlbkOT1MHrTAKFnaOww23Ob-Vi6A9n0rozo9vtoJig114GB0gUqEmtfLhO1P5AE8yzogE-ILHyp",
        "0BqXt8vGIfzpDnCkN-GKl8gOOMPrR4NAcLO-Rshc5nLs7BGB4SEi126Y6mSfp85m0--1QhWMz9HzqJEHCWKVcZYdCdEONP9js04EUnK33KtlJIWzZTQ",
        "KBwAT0pBpGwmZRp35Lpx2gBitZhcVxrg0NBnaO2fNyAGPvZD8SLQLHAdAiov_a23Uc_PDbWLL5Pp9gwzj-s5glrssVOXdE8aUscr1b5rARdNNL1_Tos",
        "6u8ZUZ3sNqGaZx7a8U4gyYboexWyo9EC1C-AdkGBm7-AkM4euFwC9N6xsa_t5zKK5d676hc0m-8SxivYCBkgkrqlfeGuZCQxU-mVsC0it6U-va8ojUj",
        "LGkZ80OuCwBf4xZl3-acU7vx9o8_gQKBwB7BrhU6MWrsc-cr_1KQaXum9mNyckomi82RFYvb8Yrilcg38FBy9XqNRKeBa9MLw1HZYpHbzsXsVF7u4eQ",
        "MloDTLVNUC5L6dKAI1owoyTa24uH90WWTg_a8mTZMe1jhgrew-AJq27NV6z4PswR9GenDmyshDDudz7rBsflZCQRoXUfWRelV7BHU6UPBsXn4ASF4xn",
        "RyM6WvcKy9coKZcUqqgm3fLM_9OizCCMJgfXHBrE-x7nBqst746qlEedSRrQKBwQCVYwwKCHNlZxl0_NMkDJ-hp7_InHF6mz_3VO58iCb19TLDVUC2d",
        "DGPXNYwWTT9PclefwV5HNBHcAfTzgB4dpQyNiDyV914HL7DFEGduoPnwBYjeFre54v0YjjnskjJO7myircdbdX__i-7LMUw5aZZXCC8a5BD_rdV6IKJ",
        "WJG5QBXbe5fVf1XwOjBTzlhIPIqhNFfSu-mFikp5BRwHGBqsKMju6inYmW6YADeY_SvOQjDEB37RqGZxqyIx8V2ZYwU",
    ].joined()
    static let rsaFingerprint = "SHA256:vWqZh87vgxDk0eDx0VqWR001mXyFGTdRF4Q2JVW/Q9w"
    static let rsaPublicPrefix = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCn4+QiJojZ9mgc9KYJIvDWGaz4qFhf0CButg6L8zEoHKwuiN+mqcEciCCOa9BNiJm"

    static func base64(_ text: String) -> Data {
        Data(base64Encoded: text) ?? Data()
    }
}
