import Foundation

/// Client for the public ETA Spot feed that powers Stanford's Marguerite live
/// map (https://supublic.etaspot.net).
struct MargueriteAPI {
    enum APIError: Error { case badResponse }

    private let base = URL(string: "https://supublic.etaspot.net/service.php")!
    private let token = "TESTING"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Every line in the network, running or not, with shapes and stop orders.
    func lines() async throws -> [Line] {
        try await fetch(service: "get_patterns", key: "get_patterns")
    }

    /// Every stop in the network.
    func stops() async throws -> [Stop] {
        try await fetch(service: "get_stops", key: "get_stops")
    }

    /// Buses reporting positions right now.
    func vehicles() async throws -> [Vehicle] {
        try await fetch(service: "get_vehicles", key: "get_vehicles")
    }

    /// Predicted arrivals at a single stop.
    func arrivals(stopID: Int) async throws -> [Arrival] {
        let payload: [StopArrivals] = try await fetch(
            service: "get_stop_etas",
            key: "get_stop_etas",
            query: [URLQueryItem(name: "stopID", value: String(stopID))]
        )
        return payload.flatMap(\.enRoute)
    }

    /// Predicted arrivals at several stops, fetched concurrently because the
    /// feed only answers one stop per request.
    func arrivals(stopIDs: [Int]) async -> [Int: [Arrival]] {
        await withTaskGroup(of: (Int, [Arrival]).self) { group in
            for stopID in stopIDs {
                group.addTask {
                    let arrivals = (try? await arrivals(stopID: stopID)) ?? []
                    return (stopID, arrivals)
                }
            }
            var result: [Int: [Arrival]] = [:]
            for await (stopID, arrivals) in group where !arrivals.isEmpty {
                result[stopID] = arrivals.sorted { $0.minutes < $1.minutes }
            }
            return result
        }
    }

    private func fetch<T: Decodable>(service: String, key: String, query: [URLQueryItem] = []) async throws -> [T] {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "service", value: service)] + query
            + [URLQueryItem(name: "token", value: token)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw APIError.badResponse }
        let envelope = try JSONDecoder().decode([String: [T]].self, from: data)
        guard let payload = envelope[key] else { throw APIError.badResponse }
        return payload
    }
}
