import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var manager: ClipboardManager
    @AppStorage("launchAtLogin") var launchAtLogin = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Clipboard Sync")
                .font(.headline)
            
            Divider()
            
            // 状态显示
            HStack {
                Circle()
                    .fill(manager.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(manager.isConnected ? "已连接" : "未连接")
                    .foregroundColor(manager.isConnected ? .green : .red)
            }
            
            // 服务器配置
            VStack(alignment: .leading) {
                Text("服务器地址 (带 Token):")
                    .font(.caption)
                TextField("wss://...", text: $manager.serverURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            // 开机启动 (满足要求 1)
            Toggle("开机自动启动", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    launchAtLogin = newValue
                    setLaunchAtLogin(enabled: newValue)
                }
            ))
            
            Divider()
            
            // 日志区域
            Text("运行日志:")
                .font(.caption)
            ScrollView {
                Text(manager.log)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(5)
            }
            .frame(height: 100)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(5)
            
            HStack {
                Button(manager.isConnected ? "断开" : "重连") {
                    if manager.isConnected {
                        manager.disconnect()
                    } else {
                        manager.connect()
                    }
                }
                
                Spacer()
                
                Button("退出程序") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundColor(.red)
            }
        }
        .padding()
        .frame(width: 300)
    }
    
    // macOS 13+ 开机启动逻辑
    private func setLaunchAtLogin(enabled: Bool) {
        do {
            let service = SMAppService.mainApp
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
    }
}
