/// RSA keys in OpenSSH's format, unencrypted and encrypted.
extension SSHKeyFixtures {
    static let rsa3072 = SSHKeyFixture(
        name: "RSA 3072",
        text: """
        -----BEGIN OPENSSH PRIVATE KEY-----
        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
        -----END OPENSSH PRIVATE KEY-----
        """,
        passphrase: nil,
        publicKey: """
        ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDEfzGniVpzgYv8sTSjFhg/5GLwx58NHb7/PgHBZRWrFuq0cc6tBVX7h1O+8wWq\
        qQ5KLG7AF58m5Ye6Zqd9WyM6yPeQdlvikfud1TZnooCYSHjTeA0GNe2COjN+VjXebF9GyX2CXytci+QiWzURnDpCpaacMLPoOnNl\
        qb2r89Oz7MzX7v8LDkPQWaM9q2l+Bg2d4lWFtc+YzCjgc/Ef69E2mROsrNDDvqREjG21iV8mJJj9aUx7jlsezKX8foyynBImaO8W\
        j+uKIRJOjEDUCJoJuHrGnja+jhSQMQlTfU2rWCEWyjtPvKIYU59PKaOH1JC8Sw9Owf/Y4E8nwz0CkVzc7EyOeEMGMWNaMLl/huPG\
        N9zY44NU4NiNe5hYXeyXbiB/TzU6/EB0Xsm1pQ3ndTT6bVzzc8czqB22e0LYl0fufD55Mnv9YHxKUgZ3giPuuymuWsmYwhWu5bf9\
        /PSlVqTXMtHOQtawwGdAdx1lA0tLoHJ2ZmvvoBVVC68vFM8RKIc= rsa3072@matcha
        """,
        fingerprint: "SHA256:v2wex/PbIDw0ajM9aheLhjJ+flkj9VTghg2uDjEmkxA",
        bits: 3072,
    )

    static let rsa3072Encrypted = SSHKeyFixture(
        name: "RSA 3072, aes256-ctr",
        text: """
        -----BEGIN OPENSSH PRIVATE KEY-----
        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
        NM0egAkMQKFiJ0BdaxEUzqjizfs=
        -----END OPENSSH PRIVATE KEY-----
        """,
        passphrase: "correct horse",
        publicKey: """
        ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC9xjy0iMSvtv3PdiNWf831qcLax9yp6mZLvpKpdV4qN8WiZeHI5mpDQuEU9b3k\
        m5sZPVOEs0JoTvKnUJ2w729BhsGtGsGUFiIcQMgrmFZ+AFzBOHTC3jo7ewZQ6G0wVi2Mpw0V+aw6W8G/wsJckth9Y6l2tWYGMul6\
        C8PTMedpRlbCIgxlGnig0aUhygJEdjsSPkDVPWcCcl0/BdSe/lQ5PI0T7yMvFxsxHUcHTTM4vCQ4+pqDUclXLBFkix94EJs+8p10\
        7kGaT5ARbk4Uql+uiPqyi5urSsdLW8+WJlNscfWF9p3B764vOqtCV4d8B3NT0hrNWC0MZ3NY9rvG933Sf00OhgqI5V8yrx9pP2sl\
        DhtC21wZlYYq+tSx+wORShd6x9a9HEAhrTkd1Eqnvo4zfhnUjYYUtSVJKIomL3xVFZtVJNr+M8fHdkEsYUIQ4wnDlu5bIKubljhb\
        Z88e2dFIL/efoId5GJSW7HUDTZQfKMJd5mJYv5X6fbmFh9mbK9s= rsa3072-enc@matcha
        """,
        fingerprint: "SHA256:ooqWJdeaiFFjf6+77NQXjytqNbRZP4VSFnl/eVrvdg0",
        bits: 3072,
    )
}
