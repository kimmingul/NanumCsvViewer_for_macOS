import Foundation

enum MemoryMetrics {
    /// Current process physical memory footprint in bytes (the same figure
    /// Instruments reports as "Memory"), or nil if the kernel query fails.
    static func currentFootprintBytes() -> Int64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS, info.phys_footprint > 0 else { return nil }
        return Int64(info.phys_footprint)
    }
}

enum GridRowDensity: String, CaseIterable, Sendable {
    case compact
    case regular
    case comfortable

    var rowHeight: CGFloat {
        switch self {
        case .compact:
            return 18
        case .regular:
            return 24
        case .comfortable:
            return 32
        }
    }

    var title: String {
        switch self {
        case .compact:
            return L.t("Compact", "촘촘하게")
        case .regular:
            return L.t("Regular", "보통")
        case .comfortable:
            return L.t("Comfortable", "여유롭게")
        }
    }
}
