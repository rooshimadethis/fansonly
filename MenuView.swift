import SwiftUI

struct MenuView: View {
    @ObservedObject var manager: HelperManager
    @State private var fanSpeeds: [Int: Float] = [:] // Local sliders state
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Fan Control")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    manager.refreshStatus()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            // Temperature Pills Row
            if let status = manager.status {
                HStack(spacing: 12) {
                    tempBadge(label: "CPU", temp: status.cpu_temp, color: .orange)
                    tempBadge(label: "GPU", temp: status.gpu_temp, color: .blue)
                    tempBadge(label: "SYS", temp: status.system_temp, color: .green)
                }
                .padding(.horizontal)
            }
            
            // Presets Segmented Buttons
            if let status = manager.status {
                HStack(spacing: 6) {
                    presetButton(label: "Auto", action: {
                        manager.setAutoMode()
                    }, isActive: status.fans.allSatisfy { $0.mode == "auto" })
                    
                    presetButton(label: "Low", action: {
                        setPresets(percentage: 0.25)
                    }, isActive: isPresetActive(percentage: 0.25))
                    
                    presetButton(label: "Med", action: {
                        setPresets(percentage: 0.50)
                    }, isActive: isPresetActive(percentage: 0.50))
                    
                    presetButton(label: "High", action: {
                        setPresets(percentage: 0.85)
                    }, isActive: isPresetActive(percentage: 0.85))
                }
                .padding(.horizontal)
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Privilege Banner
            if !manager.isPrivileged {
                VStack(spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 18))
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Privileges Required")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            Text("SMC access requires a one-time administrator authorization to set helper permissions.")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                                .lineLimit(3)
                        }
                    }
                    
                    Button(action: {
                        manager.installPrivileges { success in
                            if success {
                                print("Privileges installed successfully.")
                            }
                        }
                    }) {
                        Text("Authorize Helper")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 16)
                            .background(Color.orange.opacity(0.8))
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(12)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
                .padding(.horizontal)
            }
            
            // Fans Control List
            if let status = manager.status {
                VStack(spacing: 14) {
                    ForEach(status.fans) { fan in
                        fanControlCard(fan: fan)
                    }
                }
                .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Reading SMC data...")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                .frame(height: 180)
            }
            
            // Error Message
            if let error = manager.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Footer
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(manager.isPrivileged ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(manager.isPrivileged ? "Watchdog Active" : "Read-Only Mode")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Button(action: {
                    manager.stopWatchdog()
                    manager.setAutoMode()
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Quit")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .menuHoverEffect()
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(width: 320)
        .background(
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.1)
                LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.08), Color.clear]), startPoint: .top, endPoint: .bottom)
            }
        )
        .preferredColorScheme(.dark)
    }
    
    // Temperature Pill Helper View
    private func tempBadge(label: String, temp: Float, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color.opacity(0.8))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(color.opacity(0.15))
                .cornerRadius(4)
            
            Text(String(format: "%.1f°C", temp))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
    }
    
    // Single Fan Control Card View
    private func fanControlCard(fan: FanInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Fan Title & Toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fan \(fan.index) (\(fan.index == 0 ? "Left" : "Right"))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                    Text(String(format: "Actual: %.0f RPM", fan.actual))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Toggle mode
                Toggle("", isOn: Binding(
                    get: { fan.mode == "manual" },
                    set: { isManual in
                        if isManual {
                            let initialSpeed = max(fan.min, min(fan.max, fan.target > 0 ? fan.target : fan.actual))
                            fanSpeeds[fan.index] = initialSpeed
                            manager.setFanSpeed(index: fan.index, rpm: initialSpeed)
                        } else {
                            manager.setAutoMode()
                        }
                    }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .disabled(!manager.isPrivileged)
            }
            
            // Slider (Manual Speed adjustment)
            if fan.mode == "manual" {
                VStack(alignment: .leading, spacing: 4) {
                    let currentSliderVal = Binding<Float>(
                        get: { fanSpeeds[fan.index] ?? fan.target },
                        set: { newVal in
                            fanSpeeds[fan.index] = newVal
                        }
                    )
                    
                    HStack {
                        Text(String(format: "Target: %.0f RPM", currentSliderVal.wrappedValue))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.blue)
                        Spacer()
                        Text(String(format: "Max: %.0f", fan.max))
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                    
                    Slider(value: currentSliderVal, in: fan.min...fan.max, step: 100, onEditingChanged: { editing in
                        if !editing {
                            manager.setFanSpeed(index: fan.index, rpm: currentSliderVal.wrappedValue)
                        }
                    })
                    .accentColor(.blue)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.2), value: fan.mode)
            } else {
                // Progress Meter (Visual actual speed)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 6)
                        
                        let width = CGFloat((fan.actual - fan.min) / (fan.max - fan.min)) * geo.size.width
                        Capsule()
                            .fill(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.cyan]), startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, min(geo.size.width, width)), height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // Preset management logic
    private func setPresets(percentage: Float) {
        guard let status = manager.status else { return }
        for fan in status.fans {
            let targetSpeed = fan.min + percentage * (fan.max - fan.min)
            manager.setFanSpeed(index: fan.index, rpm: targetSpeed)
        }
    }
    
    private func isPresetActive(percentage: Float) -> Bool {
        guard let status = manager.status else { return false }
        if status.fans.isEmpty { return false }
        return status.fans.allSatisfy { fan in
            if fan.mode != "manual" { return false }
            let targetSpeed = fan.min + percentage * (fan.max - fan.min)
            return abs(fan.target - targetSpeed) < 150 // 150 RPM tolerance
        }
    }
    
    private func presetButton(label: String, action: @escaping () -> Void, isActive: Bool) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isActive ? .white : .gray)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(isActive ? Color.blue.opacity(0.8) : Color.white.opacity(0.04))
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isActive ? Color.blue : Color.white.opacity(0.06), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!manager.isPrivileged && label != "Auto")
        .menuHoverEffect()
    }
}

// Simple Hover Effect Helper for Button UI
extension View {
    func menuHoverEffect() -> some View {
        self.modifier(HoverModifier())
    }
}

struct HoverModifier: ViewModifier {
    @State private var isHovered = false
    func body(content: Content) -> some View {
        content
            .opacity(isHovered ? 0.8 : 1.0)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hover
                }
            }
    }
}

