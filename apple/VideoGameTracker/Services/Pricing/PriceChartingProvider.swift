import Foundation

/// Adapter for the **PriceCharting Prices API**
/// (https://www.pricecharting.com/api-documentation).
///
/// Notes from their docs, baked into this adapter:
/// - Prices are integer **pennies** (`1732` → `$17.32`); we divide by 100.
/// - Dates are `YYYY-MM-DD`; ids are strings.
/// - Auth is a 40-char `t` token on a **paid** plan. No token → `isConfigured`
///   is false and `PricingService` skips this provider.
/// - **1 request / second** hard cap (enforced by the caller, not here).
/// - `/api/product` returns the single best match by `id`, `upc`, or `q`.
nonisolated struct PriceChartingProvider: PricingProvider {
    let id: PricingProviderID = .priceCharting

    private let token: String?
    private let session: URLSession
    private let baseURL = URL(string: "https://www.pricecharting.com")!

    var isConfigured: Bool { !(token ?? "").isEmpty }

    init(token: String? = PriceChartingProvider.tokenFromEnvironment(),
         session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    /// Dev convenience: `PRICECHARTING_TOKEN` in the scheme's environment.
    /// Production should inject this from the backend / Keychain instead.
    static func tokenFromEnvironment() -> String? {
        ProcessInfo.processInfo.environment["PRICECHARTING_TOKEN"]
    }

    func priceReport(for query: PriceQuery) async throws -> ProviderPriceReport {
        guard let token, !token.isEmpty else { throw PricingProviderError.notConfigured }

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("api/product"),
            resolvingAgainstBaseURL: false
        )!
        var q = [URLQueryItem(name: "t", value: token)]
        if let pcID = query.knownProductIDs[PricingProviderID.priceCharting.rawValue] {
            q.append(URLQueryItem(name: "id", value: pcID))
        } else if let upc = query.upc, !upc.isEmpty {
            q.append(URLQueryItem(name: "upc", value: upc))
        } else {
            q.append(URLQueryItem(name: "q", value: "\(query.title) \(query.platform)"))
        }
        comps.queryItems = q

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: comps.url!)
        } catch {
            throw PricingProviderError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PricingProviderError.transport("non-HTTP response")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 429 { throw PricingProviderError.rateLimited }
            throw PricingProviderError.upstream(
                status: http.statusCode,
                message: String(data: data, encoding: .utf8)
            )
        }

        let product: PriceChartingProduct
        do {
            product = try JSONDecoder().decode(PriceChartingProduct.self, from: data)
        } catch {
            throw PricingProviderError.decoding(error.localizedDescription)
        }
        guard product.status != "error" else {
            throw PricingProviderError.upstream(status: 200, message: product.errorMessage)
        }
        guard product.id != nil else { throw PricingProviderError.notFound }

        return Self.map(product, retrievedAt: .now)
    }

    // MARK: - Mapping (pure, unit-tested separately from the network)

    static func map(_ p: PriceChartingProduct, retrievedAt: Date) -> ProviderPriceReport {
        let productURL = p.id.flatMap { URL(string: "https://www.pricecharting.com/game/\($0)") }
        var points: [PricePoint] = []

        func add(_ minor: Int?, _ condition: MarketCondition, _ kind: PriceKind = .marketValue) {
            if let pt = PricePoint.fromMinorUnits(
                minor, condition: condition, kind: kind,
                observedAt: retrievedAt,
                sampleSize: kind == .marketValue ? p.salesVolume : nil,
                sourceURL: productURL
            ) {
                points.append(pt)
            }
        }

        // Headline market values.
        add(p.loosePrice, .loose)
        add(p.cibPrice, .completeInBox)
        add(p.newPrice, .new)
        add(p.gradedPrice, .graded)
        add(p.boxOnlyPrice, .boxOnly)
        add(p.manualOnlyPrice, .manualOnly)

        // Dealer spreads.
        add(p.retailLooseBuy, .loose, .retailBuy)
        add(p.retailCibBuy, .completeInBox, .retailBuy)
        add(p.retailNewBuy, .new, .retailBuy)
        add(p.retailLooseSell, .loose, .retailSell)
        add(p.retailCibSell, .completeInBox, .retailSell)
        add(p.retailNewSell, .new, .retailSell)

        // GameStop pre-owned (roughly a CIB-condition retail number).
        add(p.gamestopPrice, .completeInBox, .gamestopPreowned)

        return ProviderPriceReport(
            provider: .priceCharting,
            matchedProductID: p.id,
            matchedTitle: p.productName,
            matchedPlatform: p.consoleName,
            points: points,
            salesVolumeYearly: p.salesVolume,
            retrievedAt: retrievedAt
        )
    }
}

// MARK: - DTO

/// Verbatim mirror of the PriceCharting `/api/product` response (video-game
/// subset). Key names are copied from their "Description of Keys" table. Ints are
/// decoded leniently because their docs say non-price keys are strings and
/// real-world responses have been inconsistent.
nonisolated struct PriceChartingProduct: Decodable, Sendable {
    var status: String?
    var errorMessage: String?

    var id: String?
    var productName: String?
    var consoleName: String?
    var genre: String?
    var releaseDate: String?          // YYYY-MM-DD
    var upc: String?
    var asin: String?
    var epid: String?
    var salesVolume: Int?             // yearly units sold

    // Market values — pennies
    var loosePrice: Int?
    var cibPrice: Int?
    var newPrice: Int?
    var gradedPrice: Int?
    var boxOnlyPrice: Int?
    var manualOnlyPrice: Int?

    // Dealer / retail — pennies
    var gamestopPrice: Int?
    var retailLooseBuy: Int?
    var retailLooseSell: Int?
    var retailCibBuy: Int?
    var retailCibSell: Int?
    var retailNewBuy: Int?
    var retailNewSell: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case errorMessage = "error-message"
        case id
        case productName = "product-name"
        case consoleName = "console-name"
        case genre
        case releaseDate = "release-date"
        case upc, asin, epid
        case salesVolume = "sales-volume"
        case loosePrice = "loose-price"
        case cibPrice = "cib-price"
        case newPrice = "new-price"
        case gradedPrice = "graded-price"
        case boxOnlyPrice = "box-only-price"
        case manualOnlyPrice = "manual-only-price"
        case gamestopPrice = "gamestop-price"
        case retailLooseBuy = "retail-loose-buy"
        case retailLooseSell = "retail-loose-sell"
        case retailCibBuy = "retail-cib-buy"
        case retailCibSell = "retail-cib-sell"
        case retailNewBuy = "retail-new-buy"
        case retailNewSell = "retail-new-sell"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: k) }
        func int(_ k: CodingKeys) -> Int? {
            if let i = try? c.decodeIfPresent(Int.self, forKey: k) { return i }
            if let s = try? c.decodeIfPresent(String.self, forKey: k), !s.isEmpty {
                return Int(s) ?? Double(s).map { Int($0) }
            }
            return nil
        }

        status = str(.status)
        errorMessage = str(.errorMessage)
        id = { if let s = str(.id) { return s }; if let i = int(.id) { return String(i) }; return nil }()
        productName = str(.productName)
        consoleName = str(.consoleName)
        genre = str(.genre)
        releaseDate = str(.releaseDate)
        upc = str(.upc)
        asin = str(.asin)
        epid = str(.epid)
        salesVolume = int(.salesVolume)

        loosePrice = int(.loosePrice)
        cibPrice = int(.cibPrice)
        newPrice = int(.newPrice)
        gradedPrice = int(.gradedPrice)
        boxOnlyPrice = int(.boxOnlyPrice)
        manualOnlyPrice = int(.manualOnlyPrice)
        gamestopPrice = int(.gamestopPrice)
        retailLooseBuy = int(.retailLooseBuy)
        retailLooseSell = int(.retailLooseSell)
        retailCibBuy = int(.retailCibBuy)
        retailCibSell = int(.retailCibSell)
        retailNewBuy = int(.retailNewBuy)
        retailNewSell = int(.retailNewSell)
    }
}
