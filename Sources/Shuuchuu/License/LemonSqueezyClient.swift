import Foundation

/// Typed errors from license API interactions.
enum LSError: Error, Equatable, Sendable {
    case network                  // URLError / transport failure (offline, timeout, TLS)
    case malformedResponse        // server returned non-JSON / unexpected shape
    case licenseNotFound
    case activationLimitReached
    case licenseDisabled
    case licenseExpired
    case alreadyActivatedOnThisMachine
    case server(status: Int)
}

/// Result of a successful activation.
struct LSActivation: Equatable, Sendable {
    let instanceId: String
}

/// Result of a validate call.
struct LSValidation: Equatable, Sendable {
    enum Status: String, Sendable { case active, inactive, expired, disabled, unknown }
    let valid: Bool
    let status: Status
}

/// Pluggable abstraction so tests can inject a fake without touching URLSession.
protocol LemonSqueezyAPI: Sendable {
    func activate(licenseKey: String, instanceName: String) async -> Result<LSActivation, LSError>
    func validate(licenseKey: String, instanceId: String) async -> Result<LSValidation, LSError>
    func deactivate(licenseKey: String, instanceId: String) async -> Result<Void, LSError>
}

/// Production client. Talks to LemonSqueezy's `/v1/licenses/*` endpoints over `URLSession`.
actor LemonSqueezyClient: LemonSqueezyAPI {
    let apiBase: URL
    private let session: URLSession

    init(apiBase: URL, session: URLSession = .shared) {
        self.apiBase = apiBase
        self.session = session
    }

    func activate(licenseKey: String, instanceName: String) async -> Result<LSActivation, LSError> {
        let body = formEncode([
            "license_key": licenseKey,
            "instance_name": instanceName
        ])
        switch await postJSON(path: "activate", body: body) {
        case .failure(let err):
            return .failure(err)
        case .success(let json):
            // LS returns 200 with `activated:false` on most "your input was bad" cases;
            // we map common ones to typed errors.
            if let activated = json["activated"] as? Bool, activated,
               let instance = json["instance"] as? [String: Any],
               let id = instance["id"] as? String {
                return .success(LSActivation(instanceId: id))
            }
            // Activation limit / not found / disabled — LS reports these in `error`.
            let errStr = (json["error"] as? String)?.lowercased() ?? ""
            if errStr.contains("activation limit") {
                return .failure(.activationLimitReached)
            }
            if errStr.contains("not found") || errStr.contains("does not exist") {
                return .failure(.licenseNotFound)
            }
            if errStr.contains("disabled") {
                return .failure(.licenseDisabled)
            }
            if errStr.contains("expired") {
                return .failure(.licenseExpired)
            }
            return .failure(.malformedResponse)
        }
    }

    func validate(licenseKey: String, instanceId: String) async -> Result<LSValidation, LSError> {
        let body = formEncode([
            "license_key": licenseKey,
            "instance_id": instanceId
        ])
        switch await postJSON(path: "validate", body: body) {
        case .failure(let err): return .failure(err)
        case .success(let json):
            let valid = (json["valid"] as? Bool) ?? false
            let lk = json["license_key"] as? [String: Any]
            let raw = (lk?["status"] as? String)?.lowercased() ?? "unknown"
            let status = LSValidation.Status(rawValue: raw) ?? .unknown
            return .success(LSValidation(valid: valid, status: status))
        }
    }

    func deactivate(licenseKey: String, instanceId: String) async -> Result<Void, LSError> {
        let body = formEncode([
            "license_key": licenseKey,
            "instance_id": instanceId
        ])
        switch await postJSON(path: "deactivate", body: body) {
        case .failure(let err): return .failure(err)
        case .success: return .success(())
        }
    }

    // MARK: - HTTP

    private func postJSON(path: String, body: String) async -> Result<[String: Any], LSError> {
        var req = URLRequest(url: apiBase.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = Data(body.utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            return .failure(.network)
        }
        guard let http = response as? HTTPURLResponse else { return .failure(.malformedResponse) }
        guard let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(.malformedResponse)
        }
        if (200..<300).contains(http.statusCode) {
            return .success(parsed)
        }
        // Some 4xx responses still contain a useful `error` string — surface it as malformed
        // unless we have a more specific mapping the caller can derive from `parsed`.
        return .failure(.server(status: http.statusCode))
    }

    private func formEncode(_ fields: [String: String]) -> String {
        fields
            .map { "\(percent($0.key))=\(percent($0.value))" }
            .joined(separator: "&")
    }

    private func percent(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
