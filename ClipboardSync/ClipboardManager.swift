import SwiftUI
import Combine

class ClipboardManager: ObservableObject {
    // 状态发布，用于 UI 更新
    @Published var isConnected: Bool = false
    @Published var serverURL: String = ""
    @Published var log: String = "Ready..."
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var reconnectTimer: Timer?
    private var clipboardCheckTimer: Timer?
    private var lastChangeCount: Int = 0
    
    init() {
        // 启动时连接
        connect()
        // 启动剪贴板监听
        startClipboardMonitoring()
    }
    
    // --- WebSocket 连接逻辑 ---
    func connect() {
        guard let url = URL(string: serverURL) else {
            appendLog("无效的 URL")
            return
        }
        
        appendLog("正在连接...")
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        receiveMessage()
        sendPing()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        appendLog("断开连接")
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.appendLog("连接错误: \(error.localizedDescription)")
                    self.scheduleReconnect() // 触发重连
                }
            case .success(let message):
                DispatchQueue.main.async {
                    self.isConnected = true // 收到消息说明连接是活的
                    self.reconnectTimer?.invalidate() // 取消重连计时器
                }
                
                switch message {
                case .string(let text):
                    self.handleIncomingJSON(text)
                default:
                    break
                }
                
                // 继续监听下一条消息
                self.receiveMessage()
            }
        }
    }
    
    private func sendPing() {
        // 每 15 秒发送一次 Ping 保活
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self, self.isConnected else { return }
            let pingMsg = "{\"type\":\"ping\"}"
            self.webSocketTask?.send(.string(pingMsg)) { error in
                if error != nil {
                    DispatchQueue.main.async { self.isConnected = false }
                }
            }
            self.sendPing()
        }
    }
    
    private func scheduleReconnect() {
        guard reconnectTimer == nil || !(reconnectTimer!.isValid) else { return }
        appendLog("5秒后重试...")
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            self.connect()
        }
    }
    
    // --- 剪贴板逻辑 ---
    
    private func startClipboardMonitoring() {
        // 每 0.5 秒检查一次剪贴板变化
        clipboardCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.checkClipboard()
        }
    }
    
    private func checkClipboard() {
        let currentCount = NSPasteboard.general.changeCount
        if currentCount != lastChangeCount {
            lastChangeCount = currentCount
            
            // 获取最新文本
            if let content = NSPasteboard.general.string(forType: .string) {
                // 避免回环：如果是刚刚从服务器收到的内容，不要再发回去
                // 这里做一个简单判断：通常不需要，因为 setString 会增加 changeCount
                // 严谨的做法是加一个 "ignoreNextChange" 标志位
                
                if !isReceiving {
                    sendText(content)
                }
            }
        }
    }
    
    private var isReceiving = false
    
    private func handleIncomingJSON(_ jsonString: String) {
            guard let data = jsonString.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = dict["type"] as? String else { return }
            
            if type == "text", let content = dict["content"] as? String {
                // 必须强制在主线程执行
                DispatchQueue.main.async {
                    self.isReceiving = true
                    self.appendLog("收到内容: \(content.prefix(10))...")
                    
                    let pasteboard = NSPasteboard.general
                    
                    // 1. 【核心修复】清除旧内容
                    pasteboard.clearContents()
                    
                    // 2. 【核心修复】霸道声明所有权 (这是解决无法粘贴的关键！)
                    // 不加这一行，后台应用经常写入失败
                    pasteboard.declareTypes([.string], owner: nil)
                    
                    // 3. 写入新内容
                    let success = pasteboard.setString(content, forType: .string)
                    
                    if success {
                        // 4. 双重验证：读回来看看是不是自己写的
                        if let readBack = pasteboard.string(forType: .string) {
                            if readBack == content {
                                self.appendLog("写入成功且验证通过！")
                                self.lastChangeCount = pasteboard.changeCount
                            } else {
                                self.appendLog("写入被系统拦截 (内容不一致)")
                            }
                        } else {
                            self.appendLog("写入后剪贴板为空")
                        }
                    } else {
                        self.appendLog("API 调用返回失败")
                    }
                    
                    // 延迟重置防止回环
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isReceiving = false
                    }
                }
            }
        }
    
    func sendText(_ text: String) {
        guard isConnected else { return }
        
        let json: [String: Any] = ["type": "text", "content": text]
        if let data = try? JSONSerialization.data(withJSONObject: json),
           let str = String(data: data, encoding: .utf8) {
            
            webSocketTask?.send(.string(str)) { error in
                if let error = error {
                    DispatchQueue.main.async { self.appendLog("发送失败: \(error)") }
                } else {
                    DispatchQueue.main.async { self.appendLog("已同步") }
                }
            }
        }
    }
    
    private func appendLog(_ msg: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        log = "[\(formatter.string(from: Date()))] \(msg)\n" + log
    }
}
