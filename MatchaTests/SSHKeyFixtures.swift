import Testing

/// A key file and what `ssh-keygen` says of it: `ssh-keygen -y` (the public line, with the comment for OpenSSH's
/// format) and `ssh-keygen -l -E sha256`.
struct SSHKeyFixture: CustomTestStringConvertible, Sendable {
    let name: String
    let text: String
    /// nil for an unencrypted key.
    let passphrase: String?
    let publicKey: String
    let fingerprint: String
    let bits: Int?

    var testDescription: String {
        name
    }
}

/// Keys written for these tests by `ssh-keygen` (OpenSSH 10.3, macOS) and OpenSSL 4.0, encrypted with the passphrase
/// “correct horse” and `ssh-keygen`'s default cost (16).
enum SSHKeyFixtures {
    static let unencrypted = [ed25519, p256, p384, rsa3072]
    static let encrypted = [
        ed25519Encrypted, p256Encrypted, p384Encrypted, rsa3072Encrypted, ed25519AES256CBC, ed25519AES128CTR, ed25519AES256GCM,
    ]
    static let pem = [p256SEC1, p384PKCS8, p256SEC1Named, p256PKCS8Named, ed25519PKCS8, rsa2048PKCS1, rsa2048PKCS8]
}

/// Ed25519 and ECDSA keys in OpenSSH's format, unencrypted and encrypted with each cipher.
extension SSHKeyFixtures {
    static let ed25519 = SSHKeyFixture(
        name: "Ed25519",
        text: """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
        QyNTUxOQAAACCo+kXZ2dpTs3rplECZwgR9lZr8xXyQ1Ikv3NvPs/fUtAAAAJj92diX/dnY
        lwAAAAtzc2gtZWQyNTUxOQAAACCo+kXZ2dpTs3rplECZwgR9lZr8xXyQ1Ikv3NvPs/fUtA
        AAAEAnFzSyvcZHcMvLFfotwvMA1J3PM3eEVrvNtZw5d6QQ16j6RdnZ2lOzeumUQJnCBH2V
        mvzFfJDUiS/c28+z99S0AAAADmVkMjU1MTlAbWF0Y2hhAQIDBAUGBw==
        -----END OPENSSH PRIVATE KEY-----
        """,
        passphrase: nil,
        publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKj6RdnZ2lOzeumUQJnCBH2VmvzFfJDUiS/c28+z99S0 ed25519@matcha",
        fingerprint: "SHA256:WTkQe9ptM8n607Ird6bLk0X6LysVabYLW1QJdEGmpT0",
        bits: nil,
    )

    static let p256 = SSHKeyFixture(
        name: "ECDSA P-256",
        text: """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAaAAAABNlY2RzYS
        1zaGEyLW5pc3RwMjU2AAAACG5pc3RwMjU2AAAAQQSIvo9mkScvBaRVtBOSyMlrpFdNRV7i
        rb402UsRfAw5crXCqD1aso5cspjGPupBX9IUK4J2Q1QHY32FDN9kSEBJAAAAqBchsB4XIb
        AeAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBIi+j2aRJy8FpFW0
        E5LIyWukV01FXuKtvjTZSxF8DDlytcKoPVqyjlyymMY+6kFf0hQrgnZDVAdjfYUM32RIQE
        kAAAAhALyB/qi7Wv/fGhUnQKGLPn+glRAzjuuGfyIC1pAIH605AAAAC3AyNTZAbWF0Y2hh
        AQIDBA==
        -----END OPENSSH PRIVATE KEY-----
        """,
        passphrase: nil,
        publicKey: """
        ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBIi+j2aRJy8FpFW0E5LIyWukV01F\
        XuKtvjTZSxF8DDlytcKoPVqyjlyymMY+6kFf0hQrgnZDVAdjfYUM32RIQEk= p256@matcha
        """,
        fingerprint: "SHA256:yXR9Gc1jCRlTtOlMjfYrAhS+t5Vbka11VXZ+aoBrxU8",
        bits: nil,
    )

    static let p384 = SSHKeyFixture(
        name: "ECDSA P-384",
        text: """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAiAAAABNlY2RzYS
        1zaGEyLW5pc3RwMzg0AAAACG5pc3RwMzg0AAAAYQTvYi9GWXYkVmNCcigklWx6CFgQl/cc
        z9tdFbZUySi8Dn1eZkIicNxLTK7cdSaY5+KX5NtA0X0ig9POBuMLlaUiY+c+EAuT6NbCRp
        vSOMVAicBjwlcjM9c79J8+nqxA1gYAAADYoRu6WqEbuloAAAATZWNkc2Etc2hhMi1uaXN0
        cDM4NAAAAAhuaXN0cDM4NAAAAGEE72IvRll2JFZjQnIoJJVseghYEJf3HM/bXRW2VMkovA
        59XmZCInDcS0yu3HUmmOfil+TbQNF9IoPTzgbjC5WlImPnPhALk+jWwkab0jjFQInAY8JX
        IzPXO/SfPp6sQNYGAAAAMQCIjBwsBRR8rxmaJXTP7h51F3//bjPpczRJxiZaPc6i0pKKA2
        u4rSTxMnsTNn9Wy+8AAAALcDM4NEBtYXRjaGEBAgME
        -----END OPENSSH PRIVATE KEY-----
        """,
        passphrase: nil,
        publicKey: """
        ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBO9iL0ZZdiRWY0JyKCSVbHoIWBCX\
        9xzP210VtlTJKLwOfV5mQiJw3EtMrtx1Jpjn4pfk20DRfSKD084G4wuVpSJj5z4QC5Po1sJGm9I4xUCJwGPCVyMz1zv0nz6erEDW\
        Bg== p384@matcha
        """,
        fingerprint: "SHA256:CpZlixy4uImPu9PRCJl2GaeqcmFt8G7rgB1eFOwk4Z0",
        bits: nil,
    )

    static let ed25519Encrypted = SSHKeyFixture(
        name: "Ed25519, aes256-ctr",
        text: """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABAKL9zRvO
        fdBZhv9Fs9ddcGAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIAmD+Enja96o78u5
        beLcgk1fIOygo521qmJiZ1fZmKHyAAAAoCNGPxsQ/4PtXt/4U81JlOWKHnjHypzjrGrJ1D
        Nl7Af/07x+5ANSFLKCGehvZ2RfbCKXDzb4ImFd98oTxv28cpQBHTVqk9vmspHHYHtB3+2y
        IIwShKwOPVxf8Ucn9s6X43awud10kqKvrcI0/ELSHJi0mBYJQ61Ng/Z1oA29NMu7R1ZdcK
        qJMlNBlALdJdiWXLJb+ICcJSUxOLLZs/URRvY=
        -----END OPENSSH PRIVATE KEY-----
        """,
        passphrase: "correct horse",
        publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAmD+Enja96o78u5beLcgk1fIOygo521qmJiZ1fZmKHy ed25519-enc@matcha",
        fingerprint: "SHA256:kzDbFsEfFfM21/5bgHX5xZO/5a5xlDHMTHwzKxQw814",
        bits: nil,
    )

    static let p256Encrypted = SSHKeyFixture(
        name: "ECDSA P-256, aes256-ctr",
        text: """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABBEI6By2e
        K55Tvknyk5Hnd+AAAAGAAAAAEAAABoAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlz
        dHAyNTYAAABBBN0BcfB959NwjLxi8q7nz2fgRsGGrMQcyxE0ApGrPbJLLvIzEVQH1OMIow
        Aifx+rwn5C8IdbjqeKXh5qZEDk5CIAAACweSIDjGNraDpETBsBlkB1qTj7dVcbov9PT9EL
        8OjZ4azRZyHDyTd9cdF0NYp6rviPR0WB4zTMajCPZcGDEykmIjpZ2+ukP8e/+b+Xezmcky
        8GG5xwCrjEdIQUq5tG4BXeAtSZoS58PArXB/e3xWxvPV2PCTfEyWA8xBw0RaEAx0QiDhNt
        3v91Z1ha/LycNMNDtYgQ7TJhfYLCzoTGBz2GYvt24ea/xz1BjIXdTBPaliQ=
        -----END OPENSSH PRIVATE KEY-----
        """,
        passphrase: "correct horse",
        publicKey: """
        ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBN0BcfB959NwjLxi8q7nz2fgRsGG\
        rMQcyxE0ApGrPbJLLvIzEVQH1OMIowAifx+rwn5C8IdbjqeKXh5qZEDk5CI= p256-enc@matcha
        """,
        fingerprint: "SHA256:oaWDWEHY/Rse8GeKiZHyI9Eo1ffKuUvSBcdU6KYgucA",
        bits: nil,
    )

    static let p384Encrypted = SSHKeyFixture(
        name: "ECDSA P-384, aes256-ctr",
        text: """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABB8LaBwye
        NJyRdT4vK2MHaDAAAAGAAAAAEAAACIAAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlz
        dHAzODQAAABhBNhp0bl7Y6PbPdY9dVANJdO3u3nREyBQU+V5FEuLEKH3Dnt0lsTtOQhu1H
        qkesMMraFuf8vnL0Rr3PUNg8U8+15JKtG795LwsD518C82lAuzmXb5tUzEEVjdx8UHsr7x
        3wAAAODH1AxiQk3PlxgDyY5BJF36SmLuhwdAxWJ7oal3idoVMqvzxqBc8hTMPwD65SNcsd
        UqU8NRgsSTfqX5qOOEcS//n3vO+JjPgkHCj2tBME5VPZmT2wXncBOhVXgDnjWGXn9Xuhjl
        XIdclrqwAoSlzeA5KzSaL3CPl3Nefzq9VpMdjxA06ZeMP3G0tV3HJ7QGCHDy+qfp/6N7YY
        5LoA/povZBrq9h6Cqv4T8FQdCx/igDYgVMJDMbVxly7trHQoy+3AaJMrgg5hcYM2HcnoLy
        LL+h/898O284obwZuFXAS/SPcA==
        -----END OPENSSH PRIVATE KEY-----
        """,
        passphrase: "correct horse",
        publicKey: """
        ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBNhp0bl7Y6PbPdY9dVANJdO3u3nR\
        EyBQU+V5FEuLEKH3Dnt0lsTtOQhu1HqkesMMraFuf8vnL0Rr3PUNg8U8+15JKtG795LwsD518C82lAuzmXb5tUzEEVjdx8UHsr7x\
        3w== p384-enc@matcha
        """,
        fingerprint: "SHA256:sStcoLrxaTUF4U5xSOWMdAddip3k2WXT3dO5Wr3svnA",
        bits: nil,
    )

    static let ed25519AES256CBC = SSHKeyFixture(
        name: "Ed25519, aes256-cbc",
        text: """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jYmMAAAAGYmNyeXB0AAAAGAAAABDgVAUDY1
        92+f+xOSO2Lc6HAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIBcyB4NmB46JXnGP
        y9RkzDkn9mSvM7MwWSHpaZ32H+BvAAAAoC95uN/e9UgBxn+eLUcY0fZZj46wJ0SwTOPCHz
        a53OlMSiVxgxBFjW7AhIF+g6grNSntNc0cufVyL3YlvHIiYqksBt5hs6RuOtbCYq9Nzxfu
        6hK72UOhyQz/CkcrIScrsRjkXQCt59TNQ0v4nAhAKaMDqvk54VEZfJPSc6qnohptCErD/V
        bgj+IWEXf1p7qcQmWGPmtFF8uth8PSX6ysj4I=
        -----END OPENSSH PRIVATE KEY-----
        """,
        passphrase: "correct horse",
        publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcyB4NmB46JXnGPy9RkzDkn9mSvM7MwWSHpaZ32H+Bv ed25519-aes256-cbc",
        fingerprint: "SHA256:NDA4K2tzcOwqZn7WvDgwy8YTUgslAP/zHx/JM60uxv4",
        bits: nil,
    )

    static let ed25519AES128CTR = SSHKeyFixture(
        name: "Ed25519, aes128-ctr",
        text: """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAACmFlczEyOC1jdHIAAAAGYmNyeXB0AAAAGAAAABCKzdAinS
        H5ekRcb9rJ1SCWAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAILnS9nG2HGk0XTX8
        LzoMRVYXnSvBSv2i6uloTJ2K+yDBAAAAoCCmWThgtgTftr0ZOLQlhyaLo+XiKZtmm05B/k
        +q3PrEc/lyu/bXukfOLhF6adeE+qSeK8j2IZgSGzEpyy5VKfCCcZn8RIk/uNMkPkH3uiIb
        KFyvmsMM6mAh9BVj523DSGDh5MH/5LsoGavPtNZ+WzIT7sRhQoqh4yo15iW9wlS6eOyd3r
        enSzbuIXtOQKvw+o981qq5f+V921KamhC/Rrc=
        -----END OPENSSH PRIVATE KEY-----
        """,
        passphrase: "correct horse",
        publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILnS9nG2HGk0XTX8LzoMRVYXnSvBSv2i6uloTJ2K+yDB ed25519-aes128-ctr",
        fingerprint: "SHA256:ijGR8qpwFF2ZVhJG3f4JIjrIyovzripbwvTl/xifECg",
        bits: nil,
    )

    static let ed25519AES256GCM = SSHKeyFixture(
        name: "Ed25519, aes256-gcm@openssh.com",
        text: """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAAFmFlczI1Ni1nY21Ab3BlbnNzaC5jb20AAAAGYmNyeXB0AA
        AAGAAAABB3/FJ4c/ngsGxa9ydJF1orAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAA
        IAHRcciNh1ETbBZyrzy+2g34qPJotnekEUbPlpGnMrTrAAAAsAhYUNtevn/EJZqLTPdWt9
        +Lapj2J3OWfp2Z/XziaXcV3apSkpp4SJ1s8/lBn/XMugiqeakNqhUlSxoazRwc7gRjiuuH
        A/VbkEVAsApa2+uRKGkcHopZUQQjci0vNjX+oh4U1T+vshTbQT1/pOYL/KTrc/r/eJ4DBZ
        5JzqpGjgrwcpdnpAWPi4K9dPsz7Aq6A6jqNhHSRc9ijLeEKK2QRwhDmQsxhOsgdX6WG6/A
        NogEVr9sTceuYtqVw1juSI6AwQ==
        -----END OPENSSH PRIVATE KEY-----
        """,
        passphrase: "correct horse",
        publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAHRcciNh1ETbBZyrzy+2g34qPJotnekEUbPlpGnMrTr ed25519-aes256-gcm@openssh.com",
        fingerprint: "SHA256:w1HmY98jDyWqYoF3/XT4hF+4A1nHZ+h8fLJQ+ITmUeI",
        bits: nil,
    )

    static let ed25519ChaCha20 = SSHKeyFixture(
        name: "Ed25519, chacha20-poly1305@openssh.com",
        text: """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAAHWNoYWNoYTIwLXBvbHkxMzA1QG9wZW5zc2guY29tAAAABm
        JjcnlwdAAAABgAAAAQrftXSM2gMEJLOIDIQre/iQAAABgAAAABAAAAMwAAAAtzc2gtZWQy
        NTUxOQAAACD1ai29E6l1AdARHLlUZ2grflMLGnBCSewp2JEk7HalnQAAAKi1gklP81H+kg
        fleAWUYgvJt0pHE77gO7wSN3wRbGm9CvioPVrX0DB1ShZEuDJUkpGqQYI57yPzzlcCc5G3
        Rjr+bAtt+k8t6l9KDexpV9n5bK+ngdTxQDny7Au7TuqwbbXixSE2xaNTvooqfpycIJoMIp
        s8VENQJNY9r6mcZ5KKOK6QJ4riJHqMoF88Yzw6qzxmkZPczpmQcIhJuIxlpuBb4Rd2PvnB
        Zny1iSG4WLsTHbwibIRRZeFx
        -----END OPENSSH PRIVATE KEY-----
        """,
        passphrase: "correct horse",
        publicKey: """
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPVqLb0TqXUB0BEcuVRnaCt+UwsacEJJ7CnYkSTsdqWd ed25519-chacha20-po\
        ly1305@openssh.com
        """,
        fingerprint: "SHA256:tzvlS90OxfYuGY50qUlFmOE370W7LRNzHzrbjFKrGHM",
        bits: nil,
    )
}
