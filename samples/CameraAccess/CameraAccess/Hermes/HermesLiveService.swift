import Foundation
import UIKit

// MARK: - Connection State

enum HermesConnectionState: Equatable {
    case disconnected
    case connecting
    case settingUp
    case ready
    case error(String)
}

// MARK: - Message Models

struct HermesToolCall: Codable {
    let callId: String
    let task: String
    enum CodingKeys: String, CodingKey {
        case callId = "call_id"
        case task
    }
}

struct HermesToolCallCancellation: Codable {
    let callId: String
    enum CodingKeys: String, CodingKey {
        case callId = "call_id"
    }
}

// MARK: - HermesLiveService
// Replaces GeminiLiveService — connects to the local Hermes Vision Bridge (ws://8767)
// instead of the Gemini Live API. Sends JPEG frames + PCM audio; receives text/audio
// chunks and tool calls routed back through OpenClaw/Hermes.

@MainActor
class HermesLiveService: ObservableObject {
    @Published var connectionState: HermesConnectionState = .disconnected
    @Published var isModelSpeaking: Bool = false

    var onAudioReceived: ((Data) -> Void)?
    var onTurnComplete: (() -> Void)?
    var onInterrupted: (() -> Void)?
    var onDisconnected: ((String?) -> Void)?
    var onInputTranscription: ((String) -> Void)?
    var onOutputTranscription: ((String) -> Void)?
    var onToolCall: ((HermesToolCall) -> Void)?
    var onToolCallCancellation: ((HermesToolCallCancellation) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var urlSession: URLSession!
    private let sendQueue = DispatchQueue(label: "hermes.send", qos: .userInitiated)

    // Tailscale / LAN address of PC running hermes_vision_bridge.py
    private var bridgeHost: String { HermesConfig.bridgeHost }
    private var wsPort: Int { HermesConfig.wsPort }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Connect

    func connect() async -> Bool {
        guard let url = URL(string: "ws://\(bridgeHost):\(wsPort)") else {
            connectionState = .error("Invalid bridge URL")
            return false
        }
        connectionState = .connecting
        var request = URLRequest(url: url)
        request.setValue("hermes-vision-bridge", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        connectionState = .settingUp
        startReceiving()
        // Send a ping to confirm the bridge is alive
        let pingOk = await sendPing()
        if pingOk {
            connectionState = .ready
        } else {
            connectionState = .error("Bridge did not respond to ping")
            disconnect(reason: "ping timeout")
        }
        return pingOk
    }

    private func sendPing() async -> Bool {
        await withCheckedContinuation { continuation in
            sendQueue.async {
                let msg = URLSessionWebSocketTask.Message.string(
                    "{\"type\":\"ping\"}"
                )
                self.webSocketTask?.send(msg) { err in
                    continuation.resume(returning: err == nil)
                }
            }
        }
    }

    // MARK: - Receive Loop

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let task = self.webSocketTask else { break }
                do {
                    let message = try await task.receive()
                    await self.handleMessage(message)
                } catch {
                    let reason = (error as NSError).localizedDescription
                    await self.handleDisconnect(reason: reason)
                    break
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type_ = json["type"] as? String else { return }
            switch type_ {
            case "pong":
                break // connection confirmed
            case "text_chunk":
                if let text = json["text"] as? String {
                    onOutputTranscription?(text)
                }
            case "audio_chunk":
                if let b64 = json["data"] as? String,
                   let audioData = Data(base64Encoded: b64) {
                    isModelSpeaking = true
                    onAudioReceived?(audioData)
                }
            case "turn_complete":
                isModelSpeaking = false
                onTurnComplete?()
            case "interrupted":
                isModelSpeaking = false
                onInterrupted?()
            case "tool_call":
                if let callId = json["call_id"] as? String,
                   let task = json["task"] as? String {
                    onToolCall?(HermesToolCall(callId: callId, task: task))
                }
            case "tool_call_cancellation":
                if let callId = json["call_id"] as? String {
                    onToolCallCancellation?(HermesToolCallCancellation(callId: callId))
                }
            case "input_transcription":
                if let text = json["text"] as? String {
                    onInputTranscription?(text)
                }
            default:
                NSLog("[HermesLive] Unknown message type: %@", type_)
            }
        case .data(_):
            break // binary frames not expected from bridge → bridge sends JSON
        @unknown default:
            break
        }
    }

    private func handleDisconnect(reason: String) async {
        connectionState = .disconnected
        isModelSpeaking = false
        onDisconnected?(reason)
    }

    // MARK: - Send

    func sendAudio(data: Data) {
        let b64 = data.base64EncodedString()
        let payload = "{\"type\":\"audio\",\"data\":\"\(b64)\"}"
        sendString(payload)
    }

    func sendVideoFrame(_ jpeg: Data) {
        let b64 = jpeg.base64EncodedString()
        let payload = "{\"type\":\"video_frame\",\"data\":\"\(b64)\"}"
        sendString(payload)
    }

    func sendToolResponse(callId: String, result: String) {
        let escaped = result
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let payload = "{\"type\":\"tool_response\",\"call_id\":\"\(callId)\",\"result\":\"\(escaped)\"}"
        sendString(payload)
    }

    private func sendString(_ text: String) {
        sendQueue.async { [weak self] in
            self?.webSocketTask?.send(.string(text)) { _ in }
        }
    }

    // MARK: - Disconnect

    func disconnect(reason: String? = nil) {
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        isModelSpeaking = false
    }
}
