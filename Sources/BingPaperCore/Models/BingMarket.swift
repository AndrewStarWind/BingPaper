import Foundation

public enum BingMarket: String, CaseIterable, Codable, Sendable, Identifiable {
    case auto = "auto"
    case enUS = "en-US"
    case enGB = "en-GB"
    case enCA = "en-CA"
    case enAU = "en-AU"
    case deDE = "de-DE"
    case frFR = "fr-FR"
    case esES = "es-ES"
    case itIT = "it-IT"
    case jaJP = "ja-JP"
    case zhCN = "zh-CN"
    case ptBR = "pt-BR"
    case enIN = "en-IN"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: "Automatic (System Region)"
        case .enUS: "United States (en-US)"
        case .enGB: "United Kingdom (en-GB)"
        case .enCA: "Canada (en-CA)"
        case .enAU: "Australia (en-AU)"
        case .deDE: "Germany (de-DE)"
        case .frFR: "France (fr-FR)"
        case .esES: "Spain (es-ES)"
        case .itIT: "Italy (it-IT)"
        case .jaJP: "Japan (ja-JP)"
        case .zhCN: "China (zh-CN)"
        case .ptBR: "Brazil (pt-BR)"
        case .enIN: "India (en-IN)"
        }
    }

    /// Resolves `.auto` to the closest supported Bing market for the user's current locale.
    public func resolvedMarketCode(locale: Locale = .current) -> String {
        if self != .auto {
            return rawValue
        }
        let lang = locale.language.languageCode?.identifier.lowercased() ?? "en"
        let region = locale.region?.identifier.uppercased() ?? "US"
        let combined = "\(lang)-\(region)"

        if let exact = BingMarket.allCases.first(where: { $0 != .auto && $0.rawValue.caseInsensitiveCompare(combined) == .orderedSame }) {
            return exact.rawValue
        }
        switch region {
        case "GB", "UK": return BingMarket.enGB.rawValue
        case "CA": return BingMarket.enCA.rawValue
        case "AU", "NZ": return BingMarket.enAU.rawValue
        case "DE", "AT", "CH": return BingMarket.deDE.rawValue
        case "FR", "BE": return BingMarket.frFR.rawValue
        case "ES": return BingMarket.esES.rawValue
        case "IT": return BingMarket.itIT.rawValue
        case "JP": return BingMarket.jaJP.rawValue
        case "CN": return BingMarket.zhCN.rawValue
        case "BR": return BingMarket.ptBR.rawValue
        case "IN": return BingMarket.enIN.rawValue
        default: return BingMarket.enUS.rawValue
        }
    }
}
