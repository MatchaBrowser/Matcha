import SwiftUI

/// Names and symbols of the vault's categories and fields, as the interface shows them.
extension VaultCategory {
    var name: String {
        switch self {
        case .login: String(localized: "Login", comment: "Vault: category of an item, a user name and password for a site")
        case .note: String(localized: "Secure Note", comment: "Vault: category of an item")
        case .card: String(localized: "Card", comment: "Vault: category of an item, a credit or debit card")
        case .identity: String(localized: "Identity", comment: "Vault: category of an item, a name and an address")
        case .document: String(localized: "Document", comment: "Vault: category of an item, a passport or an ID card")
        case .sshKey: String(localized: "SSH Key", comment: "Vault: category of an item")
        case .file: String(localized: "File", comment: "Vault: category of an item, an attached file")
        case .custom: String(localized: "Other", comment: "Vault: category of an item, custom fields only")
        case .unknown: String(localized: "Unknown Item", comment: "Vault: an item of a newer version of Matcha")
        }
    }

    var symbol: String {
        switch self {
        case .login: "key.fill"
        case .note: "note.text"
        case .card: "creditcard.fill"
        case .identity: "person.text.rectangle.fill"
        case .document: "doc.text.fill"
        case .sshKey: "terminal.fill"
        case .file: "paperclip"
        case .custom: "square.grid.2x2.fill"
        case .unknown: "questionmark.square.dashed"
        }
    }
}

extension VaultFieldSpec {
    static let oneTimeCode = String(
        localized: "One-Time Code",
        comment: "Vault: field of a login, the secret of a TOTP code or an otpauth address",
    )

    /// The label of the field in its form and its detail.
    var label: String {
        switch key {
        case "username": String(localized: "User Name", comment: "Vault: field of a login")
        case "password": String(localized: "Password", comment: "Vault: field of a login")
        case "secret": Self.oneTimeCode
        case "fullName": String(localized: "Name", comment: "Vault: field of a card or a document, the holder's name")
        case "cardType": String(localized: "Type", comment: "Vault: field of a card (Visa, Mastercard…)")
        case "number": String(localized: "Number", comment: "Vault: field of a card")
        case "expiryDate": String(localized: "Expires", comment: "Vault: field of a card or a document")
        case "validFrom": String(localized: "Valid From", comment: "Vault: field of a card")
        case "verificationNumber": String(localized: "Security Code", comment: "Vault: field of a card (CVV)")
        case "pin": String(localized: "PIN", comment: "Vault: field of a card")
        default: identityLabel
        }
    }

    private var identityLabel: String {
        switch key {
        case "title": String(localized: "Title", comment: "Vault: field of an identity (Mr, Ms…)")
        case "given": String(localized: "First Name", comment: "Vault: field of an identity")
        case "given2": String(localized: "Middle Name", comment: "Vault: field of an identity")
        case "surname": String(localized: "Last Name", comment: "Vault: field of an identity")
        case "streetAddress": String(localized: "Address", comment: "Vault: field of an identity, the street")
        case "postalCode": String(localized: "Postal Code", comment: "Vault: field of an identity")
        case "city": String(localized: "City", comment: "Vault: field of an identity")
        case "territory": String(localized: "Region", comment: "Vault: field of an identity, state or region")
        case "country": String(localized: "Country", comment: "Vault: field of an identity")
        case "tel": String(localized: "Phone", comment: "Vault: field of an identity")
        default: documentLabel
        }
    }

    private var documentLabel: String {
        switch key {
        case "documentNumber": String(localized: "Document Number", comment: "Vault: field of a document")
        case "birthDate": String(localized: "Date of Birth", comment: "Vault: field of a document")
        case "issueDate": String(localized: "Issued", comment: "Vault: field of a document, its date of issue")
        case "issuingCountry": String(localized: "Country of Issue", comment: "Vault: field of a document")
        case "issuingAuthority": String(localized: "Authority", comment: "Vault: field of a document, who issued it")
        case "privateKey": String(localized: "Private Key", comment: "Vault: field of an SSH key")
        case "publicKey": String(localized: "Public Key", comment: "Vault: field of an SSH key")
        case "fingerprint": String(localized: "Fingerprint", comment: "Vault: field of an SSH key")
        case "keyComment": String(localized: "Comment", comment: "Vault: field of an SSH key")
        default: key
        }
    }

    static func documentName(_ type: String) -> String {
        switch type {
        case VaultCredentialType.passport: String(localized: "Passport", comment: "Vault: kind of document")
        case VaultCredentialType.driversLicense: String(localized: "Driving Licence", comment: "Vault: kind of document")
        default: String(localized: "Identity Card", comment: "Vault: kind of document")
        }
    }
}

extension VaultFieldType {
    var name: String {
        switch self {
        case .text: String(localized: "Text", comment: "Vault: type of a custom field")
        case .concealed: String(localized: "Hidden", comment: "Vault: type of a custom field, a secret")
        case .url: String(localized: "Address", comment: "Vault: type of a custom field, a web address")
        case .email: String(localized: "Email", comment: "Vault: type of a custom field")
        case .phone: String(localized: "Phone", comment: "Vault: type of a custom field")
        case .date: String(localized: "Date", comment: "Vault: type of a custom field")
        case .totp: String(localized: "One-Time Code", comment: "Vault: type of a custom field")
        }
    }
}

extension VaultURLMatch {
    var name: String {
        switch self {
        case .site: String(localized: "Same Site", comment: "Vault: how a login matches pages, same registrable domain")
        case .host: String(localized: "Same Host", comment: "Vault: how a login matches pages, same host and port")
        case .page: String(localized: "Same Page", comment: "Vault: how a login matches pages, same address")
        }
    }
}
