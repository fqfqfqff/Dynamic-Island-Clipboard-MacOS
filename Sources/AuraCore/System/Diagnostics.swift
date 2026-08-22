import Darwin
import Foundation

/// Сколько памяти занимает приложение прямо сейчас.
///
/// Расход растёт незаметно: за ночь с открытой витриной приложение
/// раздувалось с 80 МБ до 286, и заметить это можно было только в «Мониторинге
/// системы». Раз цифра нужна для разбора, ей место в собственной диагностике.
enum Diagnostics {

    /// Физический след процесса в мегабайтах — та же величина, что показывает
    /// «Мониторинг системы» в колонке «Память».
    static var footprintMB: Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else { return -1 }
        return Int(info.phys_footprint / (1024 * 1024))
    }
}
