//
//  DumanDroidVM.swift
//  dumanOS Mac Android Layer Core Engine
//
//  Created for Apple Silicon Native Android Virtualization.
//

import Foundation
import Virtualization
import Cocoa

@available(macOS 13.0, *)
public class DumanDroidVM: NSObject, VZVirtualMachineDelegate {
    
    private var virtualMachine: VZVirtualMachine?
    public var isRunning: Bool = false
    
    public func startEngine(kernelURL: URL, initrdURL: URL, diskImageURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        let config = VZVirtualMachineConfiguration()
        
        // 1. CPU and Memory allocation
        let totalCores = ProcessInfo.processInfo.processorCount
        config.cpuCount = max(2, min(4, totalCores - 2))
        config.memorySize = 4 * 1024 * 1024 * 1024 // 4 GB RAM
        
        // 2. Linux Bootloader with kernel arguments
        let bootLoader = VZLinuxBootLoader(kernelURL: kernelURL)
        bootLoader.initialRamdiskURL = initrdURL
        bootLoader.commandLine = "console=hvc0 root=/dev/vda quiet androidboot.hardware=waydroid"
        config.bootLoader = bootLoader
        
        // 3. Storage Device (VirtIO Block)
        do {
            let diskAttachment = try VZDiskImageStorageDeviceAttachment(url: diskImageURL, readOnly: false)
            let blockDevice = VZVirtioBlockDeviceConfiguration(attachment: diskAttachment)
            config.storageDevices = [blockDevice]
        } catch {
            completion(.failure(error))
            return
        }
        
        // 4. Paravirtualized Graphics (Metal Hardware Accelerated)
        let graphicsDevice = VZVirtioGraphicsDeviceConfiguration()
        let scanout = VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1920, heightInPixels: 1080)
        graphicsDevice.scanouts = [scanout]
        config.graphicsDevices = [graphicsDevice]
        
        // 5. Network (NAT)
        let networkAttachment = VZNATNetworkDeviceAttachment()
        let networkDevice = VZVirtioNetworkDeviceConfiguration()
        networkDevice.attachment = networkAttachment
        config.networkDevices = [networkDevice]
        
        // 6. Audio
        let soundDevice = VZVirtioSoundDeviceConfiguration()
        let inputStream = VZVirtioSoundDeviceInputStreamConfiguration()
        inputStream.source = VZHostAudioInputStreamSource()
        let outputStream = VZVirtioSoundDeviceOutputStreamConfiguration()
        outputStream.sink = VZHostAudioOutputStreamSink()
        soundDevice.streams = [inputStream, outputStream]
        config.audioDevices = [soundDevice]
        
        // 7. Validate & Start
        do {
            try config.validate()
            let vm = VZVirtualMachine(configuration: config)
            vm.delegate = self
            self.virtualMachine = vm
            
            vm.start { result in
                switch result {
                case .success:
                    self.isRunning = true
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    public func stopEngine(completion: @escaping (Error?) -> Void) {
        guard let vm = self.virtualMachine, isRunning else {
            completion(nil)
            return
        }
        
        vm.requestStop { error in
            self.isRunning = false
            completion(error)
        }
    }
    
    // MARK: - VZVirtualMachineDelegate
    public func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        print("[dumanOS Mac Layer] Android VM engine stopped cleanly.")
        self.isRunning = false
    }
}
