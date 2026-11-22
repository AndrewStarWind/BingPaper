import Foundation

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

public enum BingAPIError: LocalizedError, Sendable, Equatable {
    case invalidEndpoint
    case httpError(statusCode: Int, url: String)
    case emptyArchive
    case invalidImageData
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "Failed to construct the Bing daily image endpoint URL."
        case .httpError(let code, let url):
            "Bing returned HTTP \(code) for \(url)."
        case .emptyArchive:
            "Bing returned no daily images for the selected region."
        case .invalidImageData:
            "The downloaded file was not a valid image."
        case .downloadFailed(let detail):
            "Could not download wallpaper image: \(detail)"
        }
    }
}

public struct BingAPIClient: Sendable {
    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// Fetches up to `count` recent Bing daily image entries starting at `daysAgo` (0 = today, 1 = yesterday, up to 7).
    public func fetchArchive(daysAgo: Int = 0, count: Int = 8, market: String = "en-US") async throws -> [BingImageMetadata] {
        var components = URLComponents(string: "https://www.bing.com/HPImageArchive.aspx")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "js"),
            URLQueryItem(name: "idx", value: String(max(0, min(7, daysAgo)))),
            URLQueryItem(name: "n", value: String(max(1, min(8, count)))),
            URLQueryItem(name: "uhd", value: "1"),
            URLQueryItem(name: "mkt", value: market)
        ]

        guard let url = components?.url else {
            throw BingAPIError.invalidEndpoint
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("BingPaper/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw BingAPIError.httpError(statusCode: http.statusCode, url: url.absoluteString)
        }

        let decoded = try JSONDecoder().decode(BingArchiveResponse.self, from: data)
        guard !decoded.images.isEmpty else {
            throw BingAPIError.emptyArchive
        }
        return decoded.images
    }

    /// Fetches today's Bing daily image metadata.
    public func fetchTodayMetadata(market: String = "en-US") async throws -> BingImageMetadata {
        let images = try await fetchArchive(daysAgo: 0, count: 1, market: market)
        guard let first = images.first else {
            throw BingAPIError.emptyArchive
        }
        return first
    }

    /// Downloads the highest available resolution image for the given metadata, falling back from UHD to 1080p if needed.
    public func downloadImageData(for metadata: BingImageMetadata, preferUHD: Bool = true) async throws -> (data: Data, sourceURL: URL) {
        let candidates = metadata.imageURLs(preferUHD: preferUHD)
        var lastError: Error = BingAPIError.downloadFailed("No image URLs available.")

        for candidate in candidates {
            do {
                var request = URLRequest(url: candidate, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
                request.setValue("BingPaper/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await transport.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    lastError = BingAPIError.httpError(statusCode: http.statusCode, url: candidate.absoluteString)
                    continue
                }
                guard Self.isValidImageData(data) else {
                    lastError = BingAPIError.invalidImageData
                    continue
                }
                return (data, candidate)
            } catch {
                lastError = error
            }
        }

        if let apiError = lastError as? BingAPIError {
            throw apiError
        }
        throw BingAPIError.downloadFailed(lastError.localizedDescription)
    }

    /// Validates JPEG, PNG, HEIC, or WebP magic headers and minimum non-empty size.
    public static func isValidImageData(_ data: Data) -> Bool {
        guard data.count >= 16 else { return false }
        let bytes = [UInt8](data.prefix(12))
        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return true
        }
        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return true
        }
        // WebP: RIFF....WEBP
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46
            && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
            return true
        }
        return false
    }
}
