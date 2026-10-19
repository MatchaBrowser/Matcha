import Foundation

/// Site of a web address, to know whether a link leaves the page's site: the registrable domain, approximated without
/// the public suffix list (no public Apple API provides it). It is the last two labels of the host
/// (“mail.google.com” → “google.com”), or the last three under a known two-label suffix (“news.bbc.co.uk” →
/// “bbc.co.uk”, “me.github.io”). An IP address, `localhost` or a name without a dot is taken whole. The port and the
/// scheme (http or https) do not count.
nonisolated enum SiteDomain {
    /// Most common two-label public suffixes (national registries, page hosts).
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

    /// Site of `url`, or nil outside the web (`file:`, `about:`…) or without a host.
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

    /// True if `link` leads to a site other than that of `page`; false if either one has no site.
    static func isCrossSite(from page: URL, to link: URL) -> Bool {
        guard let pageSite = site(of: page), let linkSite = site(of: link) else {
            return false
        }
        return pageSite != linkSite
    }
}
