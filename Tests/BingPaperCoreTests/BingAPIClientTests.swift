import BingPaperCore
import Foundation
import Testing

struct MockHTTPTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) throws -> (Data, URLResponse)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try handler(request)
    }
}

@Suite("BingAPIClient")
struct BingAPIClientTests {
    @Test("Parses Bing HPImageArchive JSON and builds UHD + 1080p URLs")
    func parsesArchiveAndBuildsURLs() async throws {
        let json = """
        {
          "images": [
            {
              "startdate": "20261122",
              "fullstartdate": "202611220800",
              "enddate": "20261123",
              "url": "/th?id=OHR.AlpineDawn_EN-US123456_1920x1080.jpg",
              "urlbase": "/th?id=OHR.AlpineDawn_EN-US123456",
              "copyright": "Alpine dawn in Dolomites, Italy (© Jane Doe/Getty Images)",
              "copyrightlink": "/search?q=Dolomites",
              "title": "First Light Over the Dolomites",
              "hsh": "abcdef1234567890"
            }
          ]
        }
        """

        let transport = MockHTTPTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(json.utf8), response)
        }

        let client = BingAPIClient(transport: transport)
        let image = try await client.fetchTodayMetadata(market: "en-US")

        #expect(image.startdate == "20261122")
        #expect(image.displayTitle == "First Light Over the Dolomites")
        #expect(image.attribution == "© Jane Doe/Getty Images")
        #expect(image.infoURL?.absoluteString == "https://www.bing.com/search?q=Dolomites")

        let urls = image.imageURLs(preferUHD: true)
        #expect(urls.first?.absoluteString == "https://www.bing.com/th?id=OHR.AlpineDawn_EN-US123456_UHD.jpg")
        #expect(urls.contains { $0.absoluteString == "https://www.bing.com/th?id=OHR.AlpineDawn_EN-US123456_1920x1080.jpg" })
    }

    @Test("Falls back from UHD to 1080p when UHD returns 404")
    func fallsBackTo1080pOn404() async throws {
        let fakeJPEG = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: UInt8(0x42), count: 64))
        let metadata = BingImageMetadata(
            startdate: "20261122",
            url: "/th?id=OHR.Test_1920x1080.jpg",
            urlbase: "/th?id=OHR.Test",
            copyright: "Test photo (© Author)",
            title: "Test"
        )

        let transport = MockHTTPTransport { request in
            let url = request.url!
            if url.absoluteString.contains("_UHD.jpg") {
                let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (Data(), notFound)
            }
            let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (fakeJPEG, ok)
        }

        let client = BingAPIClient(transport: transport)
        let result = try await client.downloadImageData(for: metadata, preferUHD: true)

        #expect(result.sourceURL.absoluteString.hasSuffix("_1920x1080.jpg"))
        #expect(result.data == fakeJPEG)
    }

    @Test("Rejects invalid non-image response data")
    func rejectsInvalidImageData() async throws {
        let htmlData = Data("<html>Not an image</html>".utf8)
        let metadata = BingImageMetadata(
            startdate: "20261122",
            url: "/th?id=OHR.Broken_1920x1080.jpg",
            urlbase: "/th?id=OHR.Broken",
            copyright: "Broken"
        )

        let transport = MockHTTPTransport { request in
            let ok = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (htmlData, ok)
        }

        let client = BingAPIClient(transport: transport)
        await #expect(throws: BingAPIError.invalidImageData) {
            _ = try await client.downloadImageData(for: metadata, preferUHD: true)
        }
    }
}
