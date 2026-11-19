//
//  SystemMonitorService.swift
//  EduVis Native AI
//
//  Pemantau memori sistem (Unified Memory) macOS dan proses LiteRT-LM lokal.
//

import Foundation
import Combine

@MainActor
final class SystemMonitorService: ObservableObject {
    @Published var totalMemoryGB: Double = 16.0
    @Published var usedMemoryGB: Double = 0.0
    @Published var litertMemoryMB: Double = 0.0
    @Published var memoryPressurePercentage: Double = 0.0
    @Published var thermalStateLabel: String = "🟢 Nominal"
    @Published var lastTokensPerSecond: Double = 0.0

    private var timer: Timer?

    init() {
        totalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        refreshStats()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStats()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refreshStats() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        if result == KERN_SUCCESS {
            let pageSize = Double(vm_kernel_page_size)
            let active = Double(stats.active_count) * pageSize
            let wired = Double(stats.wire_count) * pageSize
            let compressed = Double(stats.compressor_page_count) * pageSize
            let usedBytes = active + wired + compressed
            self.usedMemoryGB = usedBytes / (1024 * 1024 * 1024)
            self.memoryPressurePercentage = min(100.0, (self.usedMemoryGB / self.totalMemoryGB) * 100.0)
        }

        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            self.thermalStateLabel = "🟢 Dingin"
        case .fair:
            self.thermalStateLabel = "🟡 Hangat"
        case .serious:
            self.thermalStateLabel = "🟠 Panas"
        case .critical:
            self.thermalStateLabel = "🔴 Kritis"
        @unknown default:
            self.thermalStateLabel = "🟢 Normal"
        }
    }
}
