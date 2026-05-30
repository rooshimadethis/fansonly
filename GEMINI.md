# Mac Fan Control - Developer Reference (GEMINI.md)

This reference contains the hardware-level specifications, keys, compilation instructions, and design patterns for the Apple Silicon Fan Control App.

## SMC Key Reference (Apple Silicon M1 Pro - MacBookPro18,3)

| Key | Type | Size | Description |
| :--- | :--- | :--- | :--- |
| `FNum` | `ui8` | 1 | Number of fans (returns `2`) |
| `F0Ac` | `flt ` | 4 | Fan 0 actual speed (RPM, single-precision float) |
| `F0Tg` | `flt ` | 4 | Fan 0 target speed (RPM, single-precision float) |
| `F0Mn` | `flt ` | 4 | Fan 0 minimum speed (RPM, single-precision float, typically `1200.0f`) |
| `F0Mx` | `flt ` | 4 | Fan 0 maximum speed (RPM, single-precision float, typically `5779.0f`) |
| `F1Ac` | `flt ` | 4 | Fan 1 actual speed (RPM, single-precision float) |
| `F1Tg` | `flt ` | 4 | Fan 1 target speed (RPM, single-precision float) |
| `F1Mn` | `flt ` | 4 | Fan 1 minimum speed (RPM, single-precision float, typically `1200.0f`) |
| `F1Mx` | `flt ` | 4 | Fan 1 maximum speed (RPM, single-precision float, typically `6241.0f`) |
| `F0Md` | `ui8 ` | 1 | Fan 0 mode (`0` for auto, `1` for manual) |
| `F1Md` | `ui8 ` | 1 | Fan 1 mode (`0` for auto, `1` for manual) |

### Fan Mode Control on Apple Silicon
- The system thermal daemon (`thermalmonitord`) actively manages speeds.
- To set fan speeds manually, write `1` to `F0Md` or `F1Md` and set the target speed in `F0Tg` / `F1Tg`.
- Restoring auto mode is done by writing `0` to the manual mode keys `F0Md` and `F1Md`.

---

## Privileged Helper Design (`smc-helper`)

Since writes to `AppleSMC` require root privileges, the application utilizes a command-line helper:
- Located at `/Users/rooshi/Documents/programming/mac/fan/smc-helper`.
- The SwiftUI app communicates with it by launching it via `NSTask` / `Process`. When manual mode is toggled, it prompts for administrator privileges to perform `chmod u+s` once.

### SMC Helper Commands
1. **Get Speeds (No Root Required):**
   `./smc-helper status` -> Output JSON containing fan speeds, target speeds, limits, and temperatures.
2. **Set Fan Speeds (Root Required):**
   `sudo ./smc-helper set <fan_index> <rpm>` -> Set manual target speed.
3. **Set Auto (Root Required):**
   `sudo ./smc-helper auto` -> Restores automatic system management.

---

## Build Instructions

### Compilation of the C Helper:
```bash
clang -framework IOKit -framework Foundation smc_helper.c -o smc-helper
```

### Compilation of the SwiftUI App:
```bash
swiftc -sdk $(xcrun --show-sdk-path) -target arm64-apple-macosx14.0 -framework Cocoa -framework SwiftUI -framework IOKit FanControlApp.swift MenuView.swift HelperManager.swift -o FanControl
```
