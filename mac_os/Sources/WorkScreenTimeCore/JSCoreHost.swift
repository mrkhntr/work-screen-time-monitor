import Foundation
import JavaScriptCore

/// Loads the shared TypeScript brain (`core.js`) into JavaScriptCore and exposes
/// its `WSTCore` JSON-string API to Swift. All access is serialized because
/// `JSContext`/`JSValue` are not thread-safe.
public final class JSCoreHost {
    private let context: JSContext
    private let queue = DispatchQueue(label: "com.mrkhntr.workscreentime.jscore")

    public init?(bundle: Bundle? = nil) {
        let bundle = bundle ?? .module
        guard
            let url = bundle.url(forResource: "core", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8),
            let context = JSContext()
        else {
            return nil
        }
        self.context = context
        context.evaluateScript(source)
        if context.exception != nil { return nil }
        guard context.objectForKeyedSubscript("WSTCore") != nil else { return nil }
    }

    private func call(_ function: String, _ arguments: [String]) -> String {
        queue.sync {
            guard
                let wst = context.objectForKeyedSubscript("WSTCore"),
                let fn = wst.objectForKeyedSubscript(function),
                let result = fn.call(withArguments: arguments)
            else {
                return ""
            }
            return result.toString() ?? ""
        }
    }

    /// `reduce(state, event, now, config) -> { state, effects }` — all JSON strings.
    public func reduce(state: String, event: String, now: String, config: String) -> String {
        call("reduce", [state, event, now, config])
    }

    public func defaultConfigJSON() -> String { call("defaultConfig", []) }
    public func normalizeConfigJSON(_ json: String) -> String { call("normalizeConfig", [json]) }
    public func defaultStateJSON() -> String { call("defaultState", []) }
}
