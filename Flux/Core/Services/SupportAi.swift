import Foundation

/// Flux Support AI client. The LLM API key NEVER lives in the app — all
/// requests go through a server-side proxy (Cloud Function).
///
/// The proxy URL is injected the same way as on Android
/// (`--dart-define=FLUX_SUPPORT_AI_URL=...`): iOS reads the
/// `FLUX_SUPPORT_AI_URL` environment variable (Xcode scheme environment
/// variable / launch environment). When it is absent the assistant reports
/// itself as unavailable.
enum SupportAi {
    static let endpoint: String =
        ProcessInfo.processInfo.environment["FLUX_SUPPORT_AI_URL"] ?? ""

    static var available: Bool { !endpoint.isEmpty }

    /// Sends the conversation `history` (oldest first, entries
    /// `["role": "user"|"assistant", "content": ...]`) and returns the
    /// assistant reply, or nil when the proxy is missing / unreachable.
    static func ask(history: [[String: String]]) async -> String? {
        guard available, let url = URL(string: endpoint) else { return nil }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30

            let recent = history.suffix(20)
            let payload: [String: Any] = [
                "messages": Array(recent),
                "lang": "ru",
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let reply = body["reply"] as? String else {
                return nil
            }
            let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }
}
