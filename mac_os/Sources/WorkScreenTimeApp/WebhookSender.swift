import Foundation

/// Sends an already-rendered webhook request from the core's `sendWebhook`
/// effect. The core builds the URL/headers/body; native only performs the POST.
struct WebhookSender {
    func send(_ request: [String: Any]) {
        guard
            let urlString = request["url"] as? String,
            let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme)
        else {
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = (request["method"] as? String) ?? "POST"

        if let headers = request["headers"] as? [String: Any] {
            for (name, value) in headers {
                urlRequest.setValue("\(value)", forHTTPHeaderField: name)
            }
        }

        if let body = request["body"] as? [String: Any],
           JSONSerialization.isValidJSONObject(body),
           let data = try? JSONSerialization.data(withJSONObject: body) {
            urlRequest.httpBody = data
        }

        URLSession.shared.dataTask(with: urlRequest).resume()
    }
}
