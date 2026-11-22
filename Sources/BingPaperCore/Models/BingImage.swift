import Foundation

public struct BingArchiveResponse: Codable, Sendable, Equatable {
    public let images: [BingImageMetadata]

    public init(images: [BingImageMetadata]) {
        self.images = images
    }
}

public struct BingImageMetadata: Codable, Sendable, Equatable, Identifiable {
    public let startdate: String
    public let fullstartdate: String?
    public let enddate: String?
    public let url: String
    public let urlbase: String
    public let copyright: String
    public let copyrightlink: String?
    public let title: String?
    public let hsh: String?

    public var id: String {
        "\(startdate)-\(hsh ?? urlbase)"
    }

    public init(
        startdate: String,
        fullstartdate: String? = nil,
        enddate: String? = nil,
        url: String,
        urlbase: String,
        copyright: String,
        copyrightlink: String? = nil,
        title: String? = nil,
        hsh: String? = nil
    ) {
        self.startdate = startdate
        self.fullstartdate = fullstartdate
        self.enddate = enddate
        self.url = url
        self.urlbase = urlbase
        self.copyright = copyright
        self.copyrightlink = copyrightlink
        self.title = title
        self.hsh = hsh
    }

    /// Best title available, falling back to the primary portion of `copyright`.
    public var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = copyright.range(of: " (©") {
            return String(copyright[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return copyright
    }

    /// Photographer / attribution text extracted from `copyright` when present.
    public var attribution: String {
        if let open = copyright.range(of: "(©"), let close = copyright.range(of: ")", range: open.upperBound..<copyright.endIndex) {
            return String(copyright[open.lowerBound..<close.upperBound])
                .trimmingCharacters(in: CharacterSet(charactersIn: "() "))
        }
        return copyright
    }

    /// Formatted calendar date derived from Bing's `YYYYMMDD` `startdate`.
    public var parsedDate: Date? {
        Self.dateFormatter.date(from: startdate)
    }

    public var formattedDate: String {
        guard let date = parsedDate else { return startdate }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Direct URL to the Bing story page, if available.
    public var infoURL: URL? {
        guard let copyrightlink, !copyrightlink.isEmpty else { return nil }
        if copyrightlink.hasPrefix("http://") || copyrightlink.hasPrefix("https://") {
            return URL(string: copyrightlink)
        }
        return URL(string: "https://www.bing.com\(copyrightlink)")
    }

    /// Constructs the preferred UHD (4K) image URL and a fallback 1080p URL.
    public func imageURLs(preferUHD: Bool) -> [URL] {
        var candidates: [URL] = []
        let base = urlbase.hasPrefix("http") ? urlbase : "https://www.bing.com\(urlbase)"
        let full = url.hasPrefix("http") ? url : "https://www.bing.com\(url)"

        if preferUHD, let uhd = URL(string: "\(base)_UHD.jpg") {
            candidates.append(uhd)
        }
        if let hd1920 = URL(string: "\(base)_1920x1080.jpg"), !candidates.contains(hd1920) {
            candidates.append(hd1920)
        }
        if let raw = URL(string: full), !candidates.contains(raw) {
            candidates.append(raw)
        }
        return candidates
    }

    /// Stable, unique filename per date, market, resolution, and hash so macOS never serves a stale cached image.
    public func localFilename(market: String, preferUHD: Bool) -> String {
        let safeMarket = market.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "", options: .regularExpression)
        let suffix = preferUHD ? "UHD" : "1080p"
        let shortHash = String((hsh ?? String(abs(urlbase.hashValue))).prefix(8))
        return "bing-\(startdate)-\(safeMarket)-\(suffix)-\(shortHash).jpg"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}
