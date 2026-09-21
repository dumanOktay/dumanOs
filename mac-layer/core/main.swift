//
//  main.swift
//  dumanOS Mac Android Layer - Native GUI Host Window & Engine
//

import Cocoa
import Virtualization

class AppDelegate: NSObject, NSApplicationDelegate, VZVirtualMachineDelegate {
    var window: NSWindow!
    var vmView: VZVirtualMachineView!
    var virtualMachine: VZVirtualMachine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Create Native macOS Window
        let windowRect = NSRect(x: 100, y: 100, width: 1100, height: 750)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "dumanOS Mac Android Layer (Apple Silicon Native)"
        window.center()

        // 2. Create Metal-Accelerated Virtual Machine View
        vmView = VZVirtualMachineView(frame: window.contentView!.bounds)
        vmView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(vmView)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        print("[dumanOS Mac Layer] Native macOS GUI Window created successfully.")
        
        // 3. Initialize Virtualization Engine & Boot ISO
        self.setupAndBootVirtualMachine()
    }

    func findISOPath() -> URL? {
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser

        let candidates = [
            currentDir.appendingPathComponent("output/dumanOS-arm64.iso"),
            currentDir.appendingPathComponent("../output/dumanOS-arm64.iso"),
            homeDir.appendingPathComponent("Documents/dumanOs/output/dumanOS-arm64.iso"),
            homeDir.appendingPathComponent("Downloads/dumanOS-arm64.iso")
        ]

        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    func setupAndBootVirtualMachine() {
        let config = VZVirtualMachineConfiguration()

        // CPU & RAM
        config.cpuCount = 4
        config.memorySize = 4 * 1024 * 1024 * 1024 // 4 GB RAM

        // EFI Bootloader for ISO boot
        let efiBootLoader = VZEFIBootLoader()
        let tempEfiStore = URL(fileURLWithPath: "/tmp/dumanos_nvram.bin")
        if !FileManager.default.fileExists(atPath: tempEfiStore.path) {
            _ = try? VZEFIVariableStore(creatingVariableStoreAt: tempEfiStore)
        }
        if let variableStore = try? VZEFIVariableStore(url: tempEfiStore) {
            efiBootLoader.variableStore = variableStore
        }
        config.bootLoader = efiBootLoader

        // Generic Platform
        let platform = VZGenericPlatformConfiguration()
        config.platform = platform

        // Storage: Attach dumanOS ARM64 ISO
        if let isoPath = findISOPath() {
            do {
                let attachment = try VZDiskImageStorageDeviceAttachment(url: isoPath, readOnly: true)
                let blockDevice = VZVirtioBlockDeviceConfiguration(attachment: attachment)
                config.storageDevices = [blockDevice]
                print("[dumanOS Mac Layer] Attached ISO: \(isoPath.path)")
            } catch {
                print("[-] Failed to attach ISO: \(error)")
            }
        } else {
            print("[-] ISO could not be found in standard locations.")
        }

        // Graphics Device (Metal paravirtualized GPU)
        let graphicsDevice = VZVirtioGraphicsDeviceConfiguration()
        let scanout = VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1920, heightInPixels: 1080)
        graphicsDevice.scanouts = [scanout]
        config.graphicsDevices = [graphicsDevice]

        // Network (NAT)
        let networkDevice = VZVirtioNetworkDeviceConfiguration()
        networkDevice.attachment = VZNATNetworkDeviceAttachment()
        config.networkDevices = [networkDevice]

        // Keyboard & Pointing Device
        config.keyboards = [VZUSBKeyboardConfiguration()]
        config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

        // Audio
        let soundDevice = VZVirtioSoundDeviceConfiguration()
        let outputStream = VZVirtioSoundDeviceOutputStreamConfiguration()
        outputStream.sink = VZHostAudioOutputStreamSink()
        soundDevice.streams = [outputStream]
        config.audioDevices = [soundDevice]

        // Validate & Start VM
        do {
            try config.validate()
            let vm = VZVirtualMachine(configuration: config)
            vm.delegate = self
            self.virtualMachine = vm
            self.vmView.virtualMachine = vm

            vm.start { result in
                switch result {
                case .success:
                    print("[✓] dumanOS Virtual Machine started successfully in native Mac window!")
                case .failure(let error):
                    print("[-] Failed to start VM: \(error)")
                }
            }
        } catch {
            print("[-] Validation error: \(error)")
        }
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        print("[dumanOS Mac Layer] VM stopped.")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
