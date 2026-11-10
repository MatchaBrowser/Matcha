/// Keys in PEM: PKCS#8, PKCS#1 and SEC1, unencrypted and encrypted.
extension SSHKeyFixtures {
    static let p256SEC1 = SSHKeyFixture(
        name: "SEC1 P-256, explicit parameters (ssh-keygen -m PEM)",
        text: """
        -----BEGIN EC PRIVATE KEY-----
        MIIBaAIBAQQgvIH+qLta/98aFSdAoYs+f6CVEDOO64Z/IgLWkAgfrTmggfowgfcC
        AQEwLAYHKoZIzj0BAQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////
        MFsEIP////8AAAABAAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57Pr
        vVV2mIa8ZR0GsMxTsPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEE
        axfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54W
        K84zV2sxXs7LtkBoN79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8
        YyVRAgEBoUQDQgAEiL6PZpEnLwWkVbQTksjJa6RXTUVe4q2+NNlLEXwMOXK1wqg9
        WrKOXLKYxj7qQV/SFCuCdkNUB2N9hQzfZEhASQ==
        -----END EC PRIVATE KEY-----
        """,
        passphrase: nil,
        publicKey: """
        ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBIi+j2aRJy8FpFW0E5LIyWukV01F\
        XuKtvjTZSxF8DDlytcKoPVqyjlyymMY+6kFf0hQrgnZDVAdjfYUM32RIQEk=
        """,
        fingerprint: "SHA256:yXR9Gc1jCRlTtOlMjfYrAhS+t5Vbka11VXZ+aoBrxU8",
        bits: nil,
    )

    static let p384PKCS8 = SSHKeyFixture(
        name: "PKCS#8 P-384, explicit parameters (ssh-keygen -m PKCS8)",
        text: """
        -----BEGIN PRIVATE KEY-----
        MIICDAIBADCCAWQGByqGSM49AgEwggFXAgEBMDwGByqGSM49AQECMQD/////////
        /////////////////////////////////v////8AAAAAAAAAAP////8wewQw////
        //////////////////////////////////////7/////AAAAAAAAAAD////8BDCz
        MS+n4j7n5JiOBWvj+C0ZGB2cbv6BQRIDFAiPUBOHWsZWOY2KLtGdKoXI7dPsKu8D
        FQCjNZJqoxmieh0AiWpnc6SCes2scwRhBKqHyiK+iwU3jrHHHvMgrXRuHTtii6eb
        mFn3QeCCVCo4VQLyXb9VKWw6VF44cnYKtzYX3kqWJixvXZ6Yv5KS3Cn49B29KJoU
        fOnaMRO18LjACmCxzh1+gZ16Qx18kOoOXwIxAP//////////////////////////
        /////8djTYH0Ny3fWBoNskiwp3rs7BlqzMUpcwIBAQSBnjCBmwIBAQQwiIwcLAUU
        fK8ZmiV0z+4edRd//24z6XM0ScYmWj3OotKSigNruK0k8TJ7EzZ/VsvvoWQDYgAE
        72IvRll2JFZjQnIoJJVseghYEJf3HM/bXRW2VMkovA59XmZCInDcS0yu3HUmmOfi
        l+TbQNF9IoPTzgbjC5WlImPnPhALk+jWwkab0jjFQInAY8JXIzPXO/SfPp6sQNYG
        -----END PRIVATE KEY-----
        """,
        passphrase: nil,
        publicKey: """
        ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBO9iL0ZZdiRWY0JyKCSVbHoIWBCX\
        9xzP210VtlTJKLwOfV5mQiJw3EtMrtx1Jpjn4pfk20DRfSKD084G4wuVpSJj5z4QC5Po1sJGm9I4xUCJwGPCVyMz1zv0nz6erEDW\
        Bg==
        """,
        fingerprint: "SHA256:CpZlixy4uImPu9PRCJl2GaeqcmFt8G7rgB1eFOwk4Z0",
        bits: nil,
    )

    static let p256SEC1Named = SSHKeyFixture(
        name: "SEC1 P-256, named curve (OpenSSL)",
        text: """
        -----BEGIN EC PRIVATE KEY-----
        MHcCAQEEIPZPrAURrqm4g34ymcygG3mo00kk0NTdHgv5AJfagFHroAoGCCqGSM49
        AwEHoUQDQgAE7V8u6ie8JC40gQd50xXq+oPE21IttpwcNuHCzMdlWgLNPLjMYHiv
        mHgFLpboSNv44ZGNRiN7h6+dEZVtDV7wTg==
        -----END EC PRIVATE KEY-----
        """,
        passphrase: nil,
        publicKey: """
        ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBO1fLuonvCQuNIEHedMV6vqDxNtS\
        LbacHDbhwszHZVoCzTy4zGB4r5h4BS6W6Ejb+OGRjUYje4evnRGVbQ1e8E4=
        """,
        fingerprint: "SHA256:2P3MMCjXtF3YbljTheYVyuWQLevymWn/FVVIP2CZcno",
        bits: nil,
    )

    static let p256PKCS8Named = SSHKeyFixture(
        name: "PKCS#8 P-256, named curve (OpenSSL)",
        text: """
        -----BEGIN PRIVATE KEY-----
        MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg9k+sBRGuqbiDfjKZ
        zKAbeajTSSTQ1N0eC/kAl9qAUeuhRANCAATtXy7qJ7wkLjSBB3nTFer6g8TbUi22
        nBw24cLMx2VaAs08uMxgeK+YeAUuluhI2/jhkY1GI3uHr50RlW0NXvBO
        -----END PRIVATE KEY-----
        """,
        passphrase: nil,
        publicKey: """
        ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBO1fLuonvCQuNIEHedMV6vqDxNtS\
        LbacHDbhwszHZVoCzTy4zGB4r5h4BS6W6Ejb+OGRjUYje4evnRGVbQ1e8E4=
        """,
        fingerprint: "SHA256:2P3MMCjXtF3YbljTheYVyuWQLevymWn/FVVIP2CZcno",
        bits: nil,
    )

    static let ed25519PKCS8 = SSHKeyFixture(
        name: "PKCS#8 Ed25519 (OpenSSL)",
        text: """
        -----BEGIN PRIVATE KEY-----
        MC4CAQAwBQYDK2VwBCIEIAJ0AyOHe5k7skiLiXxpd2dZd/EYIBpjDU77ym9clNSQ
        -----END PRIVATE KEY-----
        """,
        passphrase: nil,
        publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJC7drgBE8fuXT1JbgRLFYNcB2BbYNNsUNh04QjCLMRv",
        fingerprint: "SHA256:nJ/ZSMqjpJrJEhSRmP+Zy0wZ0WxjhJL3hzJnf9fUg0M",
        bits: nil,
    )

    static let rsa2048PKCS1 = SSHKeyFixture(
        name: "PKCS#1 RSA 2048 (OpenSSL)",
        text: """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEogIBAAKCAQEAzJnWsDj7WMTkA5QSmLgU5DmiGdvDbzZBhpygudqYssVMBvLQ
        7YQ1AHMRGF4emCCOR5+6sxeydc57kaKSVpgEHr9SUtb+yLaaKvqWlbTKamj40Hau
        DDLaUUFMuPPY+H6eOyvxCNe7K2ild/TN3TGRhHKNiu+5VZXWuWMXCjWyvIPmgeGW
        fhdnsq0d51LT5h1HWCAtYgJmQUpW9uo1u9XesCgpvwHY1as5RtAeH3E8TGOnLHGv
        Q6Fd4WO6Kw+mFMYMtOqY7UZp/YyirGbaPbJI9qYSHGDG1I7w5E1yUgI4VHJVrihI
        w2ccEZKQQA86PJOh27qJEJuwJIq+j9UnL/RsVwIDAQABAoIBAGSLw1/1mLt+gqkp
        htwLNqUTl5BKmefYy2nKJgg/nyPXZm3RvQ/EFUHjykZl1nYfJZyYJ+lkH1zafIpM
        0MqCSSANGHlCU5Iyfl/Zps/qOUEC1ien8w9mnDgrNXd8yicQHlVo2jpkvgPumMZz
        BQoLFn52xw08kqE3Ef8n7YYkbnJKJKzZq12BCJ0Z5ucMWBsGgp5uNcj2jHEE7lNn
        7lx4aJxCVQNHpqO4jWLyidjiAfwLF8Q2sq9gfftUUZXVwkN7YoZvSfBf8gE6gOAi
        r5Abz2oLZ+3/RY0fKJp4SOYHx2jMQoIrlpmaWZZgsNBZMkL+eDM9mI/xkHEAC9fJ
        RsQOwHECgYEA6Wf6tCnhd39Y3Ak5DPO0abSQxQww+wT5+fwLyjz2LpecsYCo2iFN
        qATnVhVz4QPHt302nRzJMJ3y9Qg+fugoVPlRbtCPvp08m4wU0V0hWCsRJTAodEgO
        /3Hhz+da0TfCgnlIbOisXT4qFAW2q3J4dw+wS0nUJMdveqxyyGhsDecCgYEA4GgJ
        9cQhGIj/BfZp8EkChmkH/+hgqtEXQsxXz3eeUjBDopTZHurujQtt8ZhxjUPCgkWo
        BETLM6C3V+RJKGeH3NjEfnBNlaOcOi8EYdc8Q0rDMO28kpir6uZx0tRl6vfzVb2h
        lBudexG5SlBO4RzasplYQ26CEdPVG3BHMXUMgBECgYBE1PwzK3Kpae3LnhCsCCa5
        UZ2r7qd3L4WEulbDwmybWuzDz/x7r3yWQzPxyAvPXO0F6LA1byrJ4pqmtlKv3Ekg
        nhHsyybJANfBy3LMN1nBBZpdzDDx8doybOQ6CrFWp8n97kR0kb1bFh0UoIa5Ut3B
        xuennFMqsYHnvHlxLpJHGwKBgHevxbAo/SXi23HIrVQU/J3HoxagT/6LKobcCfGD
        cROQ3mH2VZ8h2j2r3OXAUr/vZeypTiWIs4BDtcXQ4hwEq/fkPVjaeObYrlhx/zpX
        27JgS57rDWp6tya/5fF2iy05NbWDQIyH9gRPva2fC5MRGqurEeJVLFZpzv2lcrM0
        JIihAoGANfDkXgJawavDi5b9IiBfLjhG0IcgJ7YCSgGxVwZxGWLsEbcxFz1qUCKa
        8NH90rcbf63woZnh3WJE2P7849g2yj9VWLlPXhRP3ZsMcsIEDfBDYJApHcbZc36N
        Qra6onVHEH1BalF598cfzkcF95Xrk1smwI7+dztx/qoTvSgYUH4=
        -----END RSA PRIVATE KEY-----
        """,
        passphrase: nil,
        publicKey: """
        ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDMmdawOPtYxOQDlBKYuBTkOaIZ28NvNkGGnKC52piyxUwG8tDthDUAcxEYXh6Y\
        II5Hn7qzF7J1znuRopJWmAQev1JS1v7Itpoq+paVtMpqaPjQdq4MMtpRQUy489j4fp47K/EI17sraKV39M3dMZGEco2K77lVlda5\
        YxcKNbK8g+aB4ZZ+F2eyrR3nUtPmHUdYIC1iAmZBSlb26jW71d6wKCm/AdjVqzlG0B4fcTxMY6csca9DoV3hY7orD6YUxgy06pjt\
        Rmn9jKKsZto9skj2phIcYMbUjvDkTXJSAjhUclWuKEjDZxwRkpBADzo8k6HbuokQm7Akir6P1Scv9GxX
        """,
        fingerprint: "SHA256:1EGDli/ATpldW7CBVYVjH80TF99OXSe8CPgyJK8EBDY",
        bits: 2048,
    )

    static let rsa2048PKCS8 = SSHKeyFixture(
        name: "PKCS#8 RSA 2048 (OpenSSL)",
        text: """
        -----BEGIN PRIVATE KEY-----
        MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDMmdawOPtYxOQD
        lBKYuBTkOaIZ28NvNkGGnKC52piyxUwG8tDthDUAcxEYXh6YII5Hn7qzF7J1znuR
        opJWmAQev1JS1v7Itpoq+paVtMpqaPjQdq4MMtpRQUy489j4fp47K/EI17sraKV3
        9M3dMZGEco2K77lVlda5YxcKNbK8g+aB4ZZ+F2eyrR3nUtPmHUdYIC1iAmZBSlb2
        6jW71d6wKCm/AdjVqzlG0B4fcTxMY6csca9DoV3hY7orD6YUxgy06pjtRmn9jKKs
        Zto9skj2phIcYMbUjvDkTXJSAjhUclWuKEjDZxwRkpBADzo8k6HbuokQm7Akir6P
        1Scv9GxXAgMBAAECggEAZIvDX/WYu36CqSmG3As2pROXkEqZ59jLacomCD+fI9dm
        bdG9D8QVQePKRmXWdh8lnJgn6WQfXNp8ikzQyoJJIA0YeUJTkjJ+X9mmz+o5QQLW
        J6fzD2acOCs1d3zKJxAeVWjaOmS+A+6YxnMFCgsWfnbHDTySoTcR/yfthiRuckok
        rNmrXYEInRnm5wxYGwaCnm41yPaMcQTuU2fuXHhonEJVA0emo7iNYvKJ2OIB/AsX
        xDayr2B9+1RRldXCQ3tihm9J8F/yATqA4CKvkBvPagtn7f9FjR8omnhI5gfHaMxC
        giuWmZpZlmCw0FkyQv54Mz2Yj/GQcQAL18lGxA7AcQKBgQDpZ/q0KeF3f1jcCTkM
        87RptJDFDDD7BPn5/AvKPPYul5yxgKjaIU2oBOdWFXPhA8e3fTadHMkwnfL1CD5+
        6ChU+VFu0I++nTybjBTRXSFYKxElMCh0SA7/ceHP51rRN8KCeUhs6KxdPioUBbar
        cnh3D7BLSdQkx296rHLIaGwN5wKBgQDgaAn1xCEYiP8F9mnwSQKGaQf/6GCq0RdC
        zFfPd55SMEOilNke6u6NC23xmHGNQ8KCRagERMszoLdX5EkoZ4fc2MR+cE2Vo5w6
        LwRh1zxDSsMw7bySmKvq5nHS1GXq9/NVvaGUG517EblKUE7hHNqymVhDboIR09Ub
        cEcxdQyAEQKBgETU/DMrcqlp7cueEKwIJrlRnavup3cvhYS6VsPCbJta7MPP/Huv
        fJZDM/HIC89c7QXosDVvKsnimqa2Uq/cSSCeEezLJskA18HLcsw3WcEFml3MMPHx
        2jJs5DoKsVanyf3uRHSRvVsWHRSghrlS3cHG56ecUyqxgee8eXEukkcbAoGAd6/F
        sCj9JeLbccitVBT8ncejFqBP/osqhtwJ8YNxE5DeYfZVnyHaPavc5cBSv+9l7KlO
        JYizgEO1xdDiHASr9+Q9WNp45tiuWHH/OlfbsmBLnusNanq3Jr/l8XaLLTk1tYNA
        jIf2BE+9rZ8LkxEaq6sR4lUsVmnO/aVyszQkiKECgYA18OReAlrBq8OLlv0iIF8u
        OEbQhyAntgJKAbFXBnEZYuwRtzEXPWpQIprw0f3Stxt/rfChmeHdYkTY/vzj2DbK
        P1VYuU9eFE/dmwxywgQN8ENgkCkdxtlzfo1CtrqidUcQfUFqUXn3xx/ORwX3leuT
        WybAjv53O3H+qhO9KBhQfg==
        -----END PRIVATE KEY-----
        """,
        passphrase: nil,
        publicKey: """
        ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDMmdawOPtYxOQDlBKYuBTkOaIZ28NvNkGGnKC52piyxUwG8tDthDUAcxEYXh6Y\
        II5Hn7qzF7J1znuRopJWmAQev1JS1v7Itpoq+paVtMpqaPjQdq4MMtpRQUy489j4fp47K/EI17sraKV39M3dMZGEco2K77lVlda5\
        YxcKNbK8g+aB4ZZ+F2eyrR3nUtPmHUdYIC1iAmZBSlb26jW71d6wKCm/AdjVqzlG0B4fcTxMY6csca9DoV3hY7orD6YUxgy06pjt\
        Rmn9jKKsZto9skj2phIcYMbUjvDkTXJSAjhUclWuKEjDZxwRkpBADzo8k6HbuokQm7Akir6P1Scv9GxX
        """,
        fingerprint: "SHA256:1EGDli/ATpldW7CBVYVjH80TF99OXSe8CPgyJK8EBDY",
        bits: 2048,
    )

    static let rsa1024PKCS8 = SSHKeyFixture(
        name: "PKCS#8 RSA 1024 (OpenSSL)",
        text: """
        -----BEGIN PRIVATE KEY-----
        MIICdgIBADANBgkqhkiG9w0BAQEFAASCAmAwggJcAgEAAoGBAMfxFrjVZoFTqhda
        r06SfrAbA96CO+v1uij8QY/7199WK/vpDH8hQWVVy4Z2LY8hsntU0ii9b1TZPf7Y
        io72lgvirm0KVKwH2Q7OjYTcXJL45SK8CvSIuWJ61nNRGhcq67Gxo1WKsmJmHUv3
        Fwai/hWcek8MmcgeXZGDwYFf2xVfAgMBAAECgYAB8kjkV799ttDLFWjrfOWa1Uh+
        XAo1S9kaGQqSWkNJu08GTsh+XFaEpActMe1TnWJdbP/2wZFZ5BuEZZtDtQbU5mGT
        4q/9NA67TubK1hp8kXBoFHP7ij1t6wrq/1q5SgwFT/AYQmb2Gpis/tWzoXCKNBnw
        NpFBN8RoQ/c6/LvKkQJBAOrVvlux90SBlM1GfzfEDQ8By55hdK+QfKFv+CTphS53
        nOzsY/3bhd2NgvpblvBMQ5xwurkGYk9CXIixxVoc51sCQQDZ9kSlDkk1UuqA1fk+
        8u/f3epusLmKIAG/YnPXPFmAV3KtrgltDTqatN0/D4NNgp2Uccd76iebF/vaXGSQ
        Q61NAkBJoOKiVVY1wHsrMWNJ1MpTXji9W8j+EstAwp6G1EDRpOcq0aM4QM/j+y6J
        2JWmmgLI1f91a67/MstYgIRkEJPpAkEAw8rUOQzPOIZmPxt3TVO/pPLc31gDI4/C
        4h/XfXYp0/859chLkVl71nM396jAw0TctvdKQgbCUzDFPY8XivwwVQJAKncGpfAy
        m3Hp/MyjM/JAStrLf7uyi+OvdlOfPXVm2JLVYbqtIXHKtedWE5mt0XBgKvr6I/Hi
        9vWA9UjoGsA6pw==
        -----END PRIVATE KEY-----
        """,
        passphrase: nil,
        publicKey: """
        ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQDH8Ra41WaBU6oXWq9Okn6wGwPegjvr9boo/EGP+9ffViv76Qx/IUFlVcuGdi2P\
        IbJ7VNIovW9U2T3+2IqO9pYL4q5tClSsB9kOzo2E3FyS+OUivAr0iLlietZzURoXKuuxsaNVirJiZh1L9xcGov4VnHpPDJnIHl2R\
        g8GBX9sVXw==
        """,
        fingerprint: "SHA256:6M4RZqRfs5bR4UrxC+fJWy/bjRYirDPm15vOVo4PbUc",
        bits: 1024,
    )

    static let p256EncryptedPEM = SSHKeyFixture(
        name: "SEC1 P-256, Proc-Type ENCRYPTED (ssh-keygen -m PEM -N)",
        text: """
        -----BEGIN EC PRIVATE KEY-----
        Proc-Type: 4,ENCRYPTED
        DEK-Info: AES-128-CBC,A885714CF8E3E50BB887A2808488AC13

        QnHYuxHaO0TsX4IhPUUaxzqR06Ykqr7eZt6eYD0cU79SEMY294b5smUHCp7OP1Mo
        r5+p1TkCOG9lHGqCeE2CaKnZ5SXEfaVgNj17YYhkGUe0r5cNUhak+zpKXLcGeSlE
        x+2eb9d9HI7SbZjSWIXHFlIJp0e+nkdqN0kJPmEQ7O8ZHUNyL3mMFgofM57DAPPl
        CkqaiMNAK8QAXjCSsL+gxA2W30hNMJI3y/0PtVDn3yfsjP6Mjz/w9ISDV3MoBImM
        IM6HfWGQEzy43oL+9VMAOetPTAoK2BA+LpH6fA/3194izIkCyjoNJFgG20DAVaye
        DoUhJmZRMk6q0UNd5kLXp4QHCiim442sBOgTT0eeBmXcD6jXWJnvnZkrHaAOgD8O
        JZLuqgQLniJGU+tndLQxMk1riMIbeJZdJWDCm590onMJFOntgC37nqfUIuqJ3WIH
        umTVCbWnFd+rmbv9bB21N7Nl38+YUCLtoxB3Uk2YIfI=
        -----END EC PRIVATE KEY-----
        """,
        passphrase: nil,
        publicKey: """
        ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBIi+j2aRJy8FpFW0E5LIyWukV01F\
        XuKtvjTZSxF8DDlytcKoPVqyjlyymMY+6kFf0hQrgnZDVAdjfYUM32RIQEk=
        """,
        fingerprint: "SHA256:yXR9Gc1jCRlTtOlMjfYrAhS+t5Vbka11VXZ+aoBrxU8",
        bits: nil,
    )

    static let p256EncryptedPKCS8 = SSHKeyFixture(
        name: "Encrypted PKCS#8 P-256 (OpenSSL)",
        text: """
        -----BEGIN ENCRYPTED PRIVATE KEY-----
        MIIB5TBfBgkqhkiG9w0BBQ0wUjAxBgkqhkiG9w0BBQwwJAQQZ7qdgegkah9trFL8
        bUw4mwICCAAwDAYIKoZIhvcNAgkFADAdBglghkgBZQMEASoEEKJKplwAh8nO1h57
        g/zsPYgEggGAhN3YJPzobMcrLdiB6Nf2zXJ4YBiXcyuWexaL86/dXN8Erlm+9M72
        q794PWMlk648DCEVu4NQmpc5fBzEF9dbNjFQ9G52TXwCA3CNi9LQFKK73qYmfnfu
        jevNoyBgCIXD7TqaKcE1eeBPqgcS2Ilbwwd49R9FFAi+kWbQib4+yz1JLvRCkh+x
        HBQRaYT7Gv2eBENgcSwAsWv5eSHOnDGWpxgjHoZW/ikWNJqc/M6Y0ifYPVZdiv7y
        fXPfQIwRzrmSY42xvrai74eqIl9FuiNrLPeZXEA3gytJ1JaFdkKKctkIxE3rzcyr
        xFybbWWGDia8LDaUYY1gB65rbCogI70d/xuSSIWf0f7UgHoqTn4C6SwhW4hvmr6J
        WmfBNdHtCkPxk90l2Fh7ZNL39+AMKg3gwODf7yZJs8jpCk/zqTWeTpIsc5Q6G/41
        87bE4Tv5B3P5d6P0BxjNE97xG/I7SP+97CRfPw6E76SW4JVHsSLXz1Fy/oMXusGc
        qmBS2CW9Y1il
        -----END ENCRYPTED PRIVATE KEY-----
        """,
        passphrase: nil,
        publicKey: """
        ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBIi+j2aRJy8FpFW0E5LIyWukV01F\
        XuKtvjTZSxF8DDlytcKoPVqyjlyymMY+6kFf0hQrgnZDVAdjfYUM32RIQEk=
        """,
        fingerprint: "SHA256:yXR9Gc1jCRlTtOlMjfYrAhS+t5Vbka11VXZ+aoBrxU8",
        bits: nil,
    )
}
