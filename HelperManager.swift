import Foundation
import ServiceManagement

struct FanInfo: Codable, Identifiable {
    let index: Int
    let actual: Float
    let target: Float
    let min: Float
    let max: Float
    let mode: String
    
    var id: Int { index }
}

struct SMCStatus: Codable {
    let cpu_temp: Float
    let gpu_temp: Float
    let system_temp: Float
    let fans: [FanInfo]
}

class HelperManager: ObservableObject {
    @Published var status: SMCStatus? = nil
    @Published var isPrivileged: Bool = false
    @Published var launchAtLoginEnabled: Bool = false
    @Published var errorMessage: String? = nil
    
    private var timer: Timer? = nil
    private var watchdogProcess: Process? = nil
    
    var helperPath: String {
        return "/usr/local/bin/smc-helper"
    }
    
    var bundleHelperPath: String {
        let bundlePath = Bundle.main.bundlePath
        return bundlePath + "/Contents/MacOS/smc-helper"
    }
    
    init() {
        checkPrivileges()
        refreshLaunchAtLoginStatus()
        startPolling()
        startWatchdog()
    }
    
    deinit {
        stopPolling()
        stopWatchdog()
    }
    
    func checkPrivileges() {
        let path = helperPath
        guard FileManager.default.fileExists(atPath: path) else {
            isPrivileged = false
            return
        }
        
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let owner = attrs[.ownerAccountName] as? String
            let perms = attrs[.posixPermissions] as? NSNumber
            
            if let permsVal = perms?.uint16Value, let ownerVal = owner {
                // Check if owned by root and has setuid bit (0o4000)
                let hasSetuid = (permsVal & 0o4000) != 0
                isPrivileged = (ownerVal == "root" && hasSetuid)
            } else {
                isPrivileged = false
            }
        } catch {
            isPrivileged = false
        }
    }

    func refreshLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            updateLaunchAtLoginState()
        } else {
            launchAtLoginEnabled = false
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }

                updateLaunchAtLoginState(showApprovalMessage: true)
            } catch {
                refreshLaunchAtLoginStatus()
                errorMessage = "Failed to update launch at login: \(error.localizedDescription)"
            }
        } else {
            launchAtLoginEnabled = false
            errorMessage = "Launch at login requires macOS 13 or newer."
        }
    }

    @available(macOS 13.0, *)
    private func updateLaunchAtLoginState(showApprovalMessage: Bool = false) {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled

        if showApprovalMessage && status == .requiresApproval {
            errorMessage = "Enable launch at login in System Settings > General > Login Items."
        } else {
            errorMessage = nil
        }
    }
    
    func installPrivileges(completion: @escaping (Bool) -> Void) {
        let source = bundleHelperPath
        let dest = helperPath
        
        // Validate paths don't contain shell-unsafe characters to prevent injection
        let unsafeChars = CharacterSet(charactersIn: "'\"\n\\`$")
        guard source.rangeOfCharacter(from: unsafeChars) == nil,
              dest.rangeOfCharacter(from: unsafeChars) == nil else {
            DispatchQueue.main.async {
                self.errorMessage = "Cannot install: app path contains unsafe characters. Move the app to a safe location."
            }
            completion(false)
            return
        }
        
        let script = "do shell script \"mkdir -p /usr/local/bin && cp '\(source)' '\(dest)' && chown root:admin '\(dest)' && chmod 4550 '\(dest)'\" with administrator privileges"
        
        DispatchQueue.global(qos: .userInitiated).async {
            let appleScript = NSAppleScript(source: script)
            var errorInfo: NSDictionary?
            let result = appleScript?.executeAndReturnError(&errorInfo)
            
            DispatchQueue.main.async {
                if result != nil {
                    self.checkPrivileges()
                    self.startWatchdog()
                    completion(true)
                } else {
                    if let errDesc = errorInfo?["NSAppleScriptErrorMessage"] as? String {
                        self.errorMessage = "Authorization failed: \(errDesc)"
                    } else {
                        self.errorMessage = "Permission prompt failed or was cancelled."
                    }
                    completion(false)
                }
            }
        }
    }
    
    func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        refreshStatus()
    }
    
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    func refreshStatus() {
        var path = helperPath
        if !FileManager.default.fileExists(atPath: path) {
            path = bundleHelperPath
        }
        
        guard FileManager.default.fileExists(atPath: path) else {
            DispatchQueue.main.async {
                self.errorMessage = "smc-helper binary not found at \(path)"
            }
            return
        }
        
        let resolvedPath = path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: resolvedPath)
            process.arguments = ["status"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                // Read pipe before waitUntilExit to avoid potential deadlock
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                if let statusObj = try? JSONDecoder().decode(SMCStatus.self, from: data) {
                    DispatchQueue.main.async {
                        self?.status = statusObj
                        self?.errorMessage = nil
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to run helper: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func setFanSpeed(index: Int, rpm: Float) {
        runHelperCommand(args: ["set", String(index), String(Int(rpm))])
    }
    
    func setAutoMode() {
        runHelperCommand(args: ["auto"])
    }
    
    func setFanAutoMode(index: Int) {
        runHelperCommand(args: ["auto", String(index)])
    }
    
    private func runHelperCommand(args: [String]) {
        let path = helperPath
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            
            do {
                try process.run()
                process.waitUntilExit()
                
                // Refresh status to update UI
                self?.refreshStatus()
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to execute command: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func startWatchdog() {
        stopWatchdog()
        
        guard isPrivileged else { return }
        
        let path = helperPath
        let pid = ProcessInfo.processInfo.processIdentifier
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["watchdog", String(pid)]
        
        // Run watchdog detached
        do {
            try process.run()
            watchdogProcess = process
        } catch {
            print("Failed to start watchdog: \(error)")
        }
    }
    
    func stopWatchdog() {
        if let process = watchdogProcess, process.isRunning {
            process.terminate()
        }
        watchdogProcess = nil
    }
}
