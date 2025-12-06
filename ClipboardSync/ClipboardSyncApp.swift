import SwiftUI

@main
struct ClipboardSyncApp: App {
    // 保持 manager 的生命周期
    @StateObject var manager = ClipboardManager()
    
    var body: some Scene {
        // MenuBarExtra 专门用于创建菜单栏应用
        MenuBarExtra {
            // 这里是点击图标后弹出的菜单内容
            // 我们直接复用 SettingsView，或者在这里放简略菜单，点击打开详细设置
            // 为了简单直观，我们直接把 SettingsView 作为一个弹窗视图
            SettingsView(manager: manager)
            
        } label: {
            // 状态栏图标 logic
            let image = manager.isConnected ? "doc.on.clipboard" : "exclamationmark.triangle"
            Image(systemName: image)
        }
        .menuBarExtraStyle(.window) // .window 样式会让点击图标弹出一个小窗口，而不是长条菜单
    }
}
