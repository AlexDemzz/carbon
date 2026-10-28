import CarbonCore
import Foundation
import IOKit.pwr_mgt

/// The power assertions every process holds, from `IOPMCopyAssertionsByProcess()`: one Mach round trip to `powerd`
/// (about 0.1 ms), so it is polled, off the main thread.
enum PowerAssertions {
    static func all() -> [PowerAssertion] {
        var copied: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&copied) == kIOReturnSuccess, let copied else { return [] }
        let byPID = copied.takeRetainedValue() as NSDictionary
        var assertions: [PowerAssertion] = []
        for case let (pid as NSNumber, entries as [NSDictionary]) in byPID {
            guard let owner = AudioProcesses.owner(ofPID: pid.int32Value) else { continue }
            for entry in entries {
                guard let id = entry["AssertionId"] as? NSNumber else { continue }
                assertions.append(
                    PowerAssertion(
                        app: owner, name: entry["AssertName"] as? String ?? "",
                        type: entry["AssertType"] as? String ?? "", id: id.intValue))
            }
        }
        return assertions
    }
}
