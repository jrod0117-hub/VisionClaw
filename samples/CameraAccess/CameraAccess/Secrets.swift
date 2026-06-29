// Secrets.swift — VisionClaw iOS app configuration
// DO NOT commit this file with real values — it's gitignored.
//
// Point hermesHost to your PC's Tailscale MagicDNS name (e.g. "jay-pc.tail097ee0.ts.net")
// or LAN IP (e.g. "192.168.4.33") when on the same WiFi.

import Foundation

enum Secrets {
    // ── Hermes Vision Bridge ─────────────────────────────────────────────────
    // Your PC's Tailscale hostname or LAN IP running hermes_vision_bridge.py
    static let hermesHost      = "jrod0.tail097ee0.ts.net"
    static let hermesWsPort    = 8767   // websocket
    static let hermesHttpPort  = 8768   // HTTP /frame endpoint

    // ── OpenClaw (Hermes gateway) ─────────────────────────────────────────────
    static let openClawHost         = "http://jrod0.tail097ee0.ts.net"
    static let openClawPort         = 18789
    static let openClawGatewayToken = "visionclaw2026token"
    static let openClawHookToken    = ""

    // ── WebRTC (optional live POV stream) ────────────────────────────────────
    static let webrtcSignalingURL   = ""

    // ── Legacy Gemini key — NOT used, kept so old references compile ─────────
    static let geminiAPIKey         = ""
}
