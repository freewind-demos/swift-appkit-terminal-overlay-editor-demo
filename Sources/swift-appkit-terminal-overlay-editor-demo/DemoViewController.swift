import AppKit
import SwiftTerm

@MainActor
final class DemoViewController: NSViewController {
    private let workingDirectoryURL = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["PWD"] ?? FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
    private lazy var sampleFileURL = workingDirectoryURL.appendingPathComponent("demo-note.txt")
    private let terminalView = EditInterceptingTerminalView(frame: .zero)
    private let editorOverlayView = EditorOverlayView(frame: .zero)

    private var currentFileURL: URL?
    private var shellConfigDirectoryURL: URL?

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        ensureSampleFile()
        startTerminal()
    }

    private func setupView() {
        view.wantsLayer = true

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.processDelegate = self
        terminalView.onEditRequest = { [weak self] fileURL in
            self?.openEditor(for: fileURL)
        }

        editorOverlayView.translatesAutoresizingMaskIntoConstraints = false
        editorOverlayView.isHidden = true
        editorOverlayView.onSave = { [weak self] in
            self?.saveCurrentFile()
        }
        editorOverlayView.onClose = { [weak self] in
            self?.closeEditor()
        }

        view.addSubview(terminalView)
        view.addSubview(editorOverlayView)

        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: view.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            editorOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            editorOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editorOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            editorOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func ensureSampleFile() {
        guard !FileManager.default.fileExists(atPath: sampleFileURL.path) else {
            return
        }

        let text = """
        Overlay editor demo

        1. Terminal 输入: edit demo-note.txt
        2. 文件会覆盖 terminal 打开
        3. Save 写回
        4. Close 回到原 terminal
        """

        try? text.write(to: sampleFileURL, atomically: true, encoding: .utf8)
    }

    private func startTerminal() {
        do {
            let shellConfigDirectoryURL = try makeShellConfigDirectory()
            self.shellConfigDirectoryURL = shellConfigDirectoryURL

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
        } catch {
            terminalView.feed(text: "Failed to prepare shell config: \(error.localizedDescription)\r\n")
        }
    }

    private func makeShellConfigDirectory() throws -> URL {
        let directoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("overlay-editor-demo-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let zshrcURL = directoryURL.appendingPathComponent(".zshrc")
        let script = """
        PROMPT='%n@overlay-demo %1~ %# '
        edit() {
          if [[ -z "$1" ]]; then
            print -r -- "usage: edit <file>"
            return 1
          fi
          local target=${1:A}
          printf '\\033]1337;DemoEdit=%s\\007' "$target"
        }
        print -r -- "Overlay editor demo ready."
        print -r -- "Try: edit demo-note.txt"
        """

        try script.write(to: zshrcURL, atomically: true, encoding: .utf8)
        return directoryURL
    }

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

    private func closeEditor() {
        editorOverlayView.isHidden = true
        currentFileURL = nil
        editorOverlayView.setStatus("")
        view.window?.makeFirstResponder(terminalView)
    }
}

extension DemoViewController: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak self] in
            self?.view.window?.title = title.isEmpty ? "Overlay Editor Demo" : title
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        let code = exitCode.map(String.init) ?? "nil"
        Task { @MainActor [weak self] in
            self?.terminalView.feed(text: "\r\n[process terminated: \(code)]\r\n")
        }
    }
}
