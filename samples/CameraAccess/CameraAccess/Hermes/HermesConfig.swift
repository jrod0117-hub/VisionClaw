import Foundation

// MARK: - HermesConfig
// Single source of truth for the Hermes Vision Bridge connection.
// Edit Secrets.swift to change the host — this file just reads from it.

enum HermesConfig {
    /// PC's Tailscale MagicDNS name or LAN IP running hermes_vision_bridge.py
    static let bridgeHost: String = Secrets.hermesHost
    /// WebSocket port (hermes_vision_bridge.py WS_PORT = 8767)
    static let wsPort: Int = Secrets.hermesWsPort
    /// HTTP frame POST port (hermes_vision_bridge.py HTTP_PORT = 8768)
    static let httpPort: Int = Secrets.hermesHttpPort

    static var isConfigured: Bool {
        !bridgeHost.isEmpty && bridgeHost != "YOUR_TAILSCALE_HOST"
    }

    static var frameURL: URL? {
        URL(string: "http://\(bridgeHost):\(httpPort)/frame")
    }
}
