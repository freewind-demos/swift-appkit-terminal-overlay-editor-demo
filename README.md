# Swift AppKit Terminal Overlay Editor Demo

## 简介

这个 Demo 用 Swift 做一个 macOS window。

window 里先放一个 terminal。
terminal 里输入自定义命令 `edit <file>` 时，不是真的启动 `vim`，而是发一个 OSC 1337 事件给宿主 app。
宿主 app 收到事件后，在同一个 window 里弹出一个覆盖式 editor，把原 terminal 盖住。
点 `Close` 后，editor 消失，回到之前那个 terminal，shell session 不中断。

## 快速开始

### 环境要求

- macOS
- Xcode.app
- Swift 6

如果你当前 `xcode-select` 指到 `CommandLineTools`，而本机 CLT 又有问题，运行时直接带上：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

### 运行

```bash
cd /Volumes/SN550-2T/freewind-demos/swift-appkit-terminal-overlay-editor-demo
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run
```

启动后，在 terminal 里输入：

```bash
edit demo-note.txt
```

然后你会看到：

1. editor 覆盖 terminal
2. 可以直接修改文本
3. 点 `Save` 写回文件
4. 点 `Close` 回到原 terminal

## 概念讲解

### 第一部分：terminal 不是直接开编辑器

关键不是在 terminal 内部嵌一个真正的 `vim`。

而是让 shell 的 `edit` 函数发一个宿主可识别的 escape sequence：

```zsh
edit() {
  if [[ -z "$1" ]]; then
    print -r -- "usage: edit <file>"
    return 1
  fi
  local target=${1:A}
  printf '\033]1337;DemoEdit=%s\007' "$target"
}
```

这段命令做了两件事：

- 把相对路径转成绝对路径
- 发出 `OSC 1337;DemoEdit=/abs/path`

这样 terminal 里的 shell 还是活的，但“打开编辑器”这个动作已经交给宿主 app。

### 第二部分：SwiftTerm 拦截自定义事件

Demo 用 `SwiftTerm` 的 `LocalProcessTerminalView` 跑本地 `zsh`。

再做一个很薄的子类，专门拦 `OSC 1337`：

```swift
final class EditInterceptingTerminalView: LocalProcessTerminalView {
    private static let editPrefix = "DemoEdit="

    var onEditRequest: ((URL) -> Void)?

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
        guard let payload = String(bytes: content, encoding: .utf8) else {
            return
        }
        guard payload.hasPrefix(Self.editPrefix) else {
            return
        }

        let path = String(payload.dropFirst(Self.editPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !path.isEmpty else {
            return
        }

        onEditRequest?(URL(fileURLWithPath: path))
    }
}
```

terminal 一旦收到 `DemoEdit=...`，就把文件路径抛给上层 view controller。

### 第三部分：editor 只是覆盖层

UI 结构很简单：

- 底层是 `EditInterceptingTerminalView`
- 上层是 `EditorOverlayView`

两个 view 都放进同一个根 view，并且都约束成铺满全屏。
editor 平时 `isHidden = true`。

打开文件时：

```swift
private func openEditor(for fileURL: URL) {
    let normalizedURL = fileURL.standardizedFileURL
    let fileExists = FileManager.default.fileExists(atPath: normalizedURL.path)
    let text: String

    if fileExists, let data = try? Data(contentsOf: normalizedURL) {
        text = String(decoding: data, as: UTF8.self)
    } else {
        text = ""
    }

    currentFileURL = normalizedURL
    editorOverlayView.configure(fileURL: normalizedURL, text: text, isNewFile: !fileExists)
    editorOverlayView.isHidden = false
    view.window?.makeFirstResponder(editorOverlayView.textView)
}
```

关闭时：

```swift
private func closeEditor() {
    editorOverlayView.isHidden = true
    currentFileURL = nil
    editorOverlayView.setStatus("")
    view.window?.makeFirstResponder(terminalView)
}
```

terminal 从头到尾没被销毁。
所以 Close 之后，看到的就是刚才那个 shell。

## 完整示例

核心文件：

- `AppDelegate.swift`：创建 window
- `DemoViewController.swift`：组装 terminal + editor，处理打开/保存/关闭
- `EditInterceptingTerminalView.swift`：接 `DemoEdit`
- `EditorOverlayView.swift`：覆盖式文本编辑器

terminal 启动逻辑：

```swift
private func startTerminal() {
    let shellConfigDirectoryURL = try makeShellConfigDirectory()

    var environment = ProcessInfo.processInfo.environment
    environment["TERM"] = "xterm-256color"
    environment["COLORTERM"] = "truecolor"
    environment["LANG"] = "en_US.UTF-8"
    environment["ZDOTDIR"] = shellConfigDirectoryURL.path

    let envList = environment
        .keys
        .sorted()
        .map { key in
            "\(key)=\(environment[key] ?? "")"
        }

    terminalView.startProcess(
        executable: "/bin/zsh",
        args: ["-i"],
        environment: envList,
        currentDirectory: workingDirectoryURL.path
    )
}
```

保存逻辑：

```swift
private func saveCurrentFile() {
    guard let currentFileURL else {
        return
    }

    do {
        try FileManager.default.createDirectory(
            at: currentFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try editorOverlayView.text.write(to: currentFileURL, atomically: true, encoding: .utf8)
        editorOverlayView.setStatus("Saved")
    } catch {
        editorOverlayView.setStatus("Save failed: \(error.localizedDescription)")
    }
}
```

你可以直接读源码：

- `Sources/swift-appkit-terminal-overlay-editor-demo/DemoViewController.swift`
- `Sources/swift-appkit-terminal-overlay-editor-demo/EditInterceptingTerminalView.swift`
- `Sources/swift-appkit-terminal-overlay-editor-demo/EditorOverlayView.swift`

## 注意事项

- 这个 Demo 只处理纯文本，不做语法高亮
- `edit` 是自定义 shell fn，不是接管 `vim`
- 当前实现里 `Close` 只是关闭 editor，不自动保存
- 若你要做“编辑期间 shell 阻塞，关闭后再继续”，可再加 FIFO/pipe 同步

## 中文完整讲解

这个 Demo 的关键思路，是把“terminal 输入命令”和“宿主 app 打开编辑器”拆开。

很多人第一反应，是在 terminal 里启动 `vim`，然后想办法把 `vim` 画面搬进自己 UI。
这条路能做，但复杂很多，因为你要处理 terminal alternate screen、按键、退出时机、状态恢复。

这里换个思路：

1. terminal 只负责采集命令
2. shell 里的 `edit file.txt` 不打开 `vim`
3. 它只发一段约定好的 escape sequence
4. 宿主 app 收到这段消息后，自己打开 `NSTextView`

这样好处很直接：

- terminal session 一直活着，不用重建
- editor 可以完全按 AppKit 方式写，保存逻辑简单
- Close 时只要把 overlay 隐掉，就天然回到之前 terminal

所以本质上，这不是“terminal 里嵌编辑器”。
而是“terminal 发事件，window 内切 view”。

如果你后面想继续扩展，这个骨架可以再加：

- `Cmd+S` 之外的快捷键
- dirty 状态提示
- 多标签编辑
- 文件树
- 把 `edit` 扩成 `edit +line file`

但第一版验证概念，到这里已经够了。
