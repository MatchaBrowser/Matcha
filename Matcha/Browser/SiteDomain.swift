import Foundation

/// Site d'une adresse web, pour savoir si un lien quitte le site de la page : le domaine enregistrable,
/// approché sans la liste publique des suffixes (aucune API publique d'Apple ne la donne). Ce sont les deux
/// dernières étiquettes de l'hôte (« mail.google.com » → « google.com »), ou les trois dernières sous un
/// suffixe connu à deux étiquettes (« news.bbc.co.uk » → « bbc.co.uk », « moi.github.io »). Une adresse IP,
/// `localhost` ou un nom sans point est pris en entier. Le port et le schéma (http ou https) ne comptent pas.
nonisolated enum SiteDomain {
    /// Suffixes publics à deux étiquettes les plus courants (registres nationaux, hébergeurs de pages).
    static let twoLabelSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "net.uk", "ltd.uk", "plc.uk", "sch.uk", "nhs.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au", "asn.au", "id.au",
        "co.nz", "net.nz", "org.nz", "ac.nz", "govt.nz",
        "co.jp", "ne.jp", "or.jp", "ac.jp", "go.jp", "ed.jp", "gr.jp", "lg.jp",
        "co.kr", "or.kr", "ne.kr", "go.kr", "ac.kr",
        "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn", "com.hk", "org.hk", "gov.hk", "edu.hk",
        "com.tw", "org.tw", "gov.tw", "edu.tw", "com.sg", "gov.sg", "edu.sg",
        "co.in", "net.in", "org.in", "gov.in", "ac.in", "edu.in", "co.id", "or.id", "ac.id", "go.id",
        "co.th", "ac.th", "go.th", "in.th", "com.my", "com.ph", "com.vn", "com.pk",
        "co.za", "org.za", "gov.za", "ac.za", "co.ke", "com.ng", "com.eg", "com.sa", "co.il", "org.il", "ac.il",
        "gov.il", "com.tr", "gov.tr", "org.tr", "com.ua", "gov.ua",
        "com.br", "net.br", "org.br", "gov.br", "edu.br", "com.ar", "gob.ar", "com.mx", "gob.mx", "org.mx",
        "com.co", "gov.co", "com.pe", "gob.pe", "com.uy", "com.ec",
        "gouv.fr", "asso.fr", "com.es", "gob.es", "org.es", "com.pt", "gov.pt", "com.pl", "org.pl", "gov.pl",
        "co.at", "or.at", "gv.at", "ac.at", "com.gr", "gov.gr", "gov.it", "edu.it",
        "github.io", "gitlab.io", "pages.dev", "workers.dev", "vercel.app", "netlify.app", "web.app",
        "firebaseapp.com", "appspot.com", "herokuapp.com", "blogspot.com", "azurewebsites.net",
        "cloudfront.net", "notion.site", "substack.com", "wordpress.com",
    ]

    /// Site de `url`, ou nil hors du web (`file:`, `about:`…) ou sans hôte.
    static func site(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty
        else {
            return nil
        }
        if host.hasSuffix(".") {
            host.removeLast()
        }
        if host.contains(":") || !host.contains(".") || host.allSatisfy({ $0.isNumber || $0 == "." }) {
            return host
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if labels.count >= 3, twoLabelSuffixes.contains(lastTwo) {
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    /// Vrai si `link` mène à un autre site que `page` ; faux si l'une des deux n'a pas de site.
    static func isCrossSite(from page: URL, to link: URL) -> Bool {
        guard let pageSite = site(of: page), let linkSite = site(of: link) else {
            return false
        }
        return pageSite != linkSite
    }
}
