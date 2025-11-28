import Foundation
import HealthKit

final class HealthManager: NSObject, ObservableObject {
    static let shared = HealthManager()
    private let store = HKHealthStore()

    enum HMError: Error { case unsupported, authFailed }

    // types we will read
    let readTypes: Set<HKObjectType> = [
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
        HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    ]

    func requestAuthorization() async throws -> Bool {
        if !HKHealthStore.isHealthDataAvailable() { throw HMError.unsupported }
        return try await withCheckedThrowingContinuation { cont in
            store.requestAuthorization(toShare: [], read: readTypes) { ok, err in
                if let e = err { cont.resume(throwing: e); return }
                cont.resume(returning: ok)
            }
        }
    }

    // Export NDJSON using anchored queries per-type and write incrementally to file
    func exportNDJSON(start: Date, end: Date) async throws -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = "health-export-\(ISO8601DateFormatter().string(from: Date())).ndjson"
        let outURL = docs.appendingPathComponent(filename)
        if fm.fileExists(atPath: outURL.path) { try fm.removeItem(at: outURL) }
        fm.createFile(atPath: outURL.path, contents: nil, attributes: nil)
        guard let handle = try? FileHandle(forWritingTo: outURL) else { throw HMError.unsupported }

        let types: [(HKSampleType, String)] = [
            (HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!, "SleepAnalysis"),
            (HKObjectType.quantityType(forIdentifier: .heartRate)!, "HeartRate"),
            (HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!, "HRV"),
            (HKObjectType.quantityType(forIdentifier: .respiratoryRate)!, "RespiratoryRate"),
            (HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!, "OxygenSaturation"),
        ]

        for (sampleType, label) in types {
            try await queryAndWrite(sampleType: sampleType, label: label, start: start, end: end, handle: handle)
        }

        try handle.close()
        return outURL
    }

    private func queryAndWrite(sampleType: HKSampleType, label: String, start: Date, end: Date, handle: FileHandle) async throws {
        // We'll fetch using HKSampleQuery (paginated)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        var anchor: HKQueryAnchor? = nil
        let semaphore = DispatchSemaphore(value: 0)
        var lastError: Error? = nil

        let query = HKAnchoredObjectQuery(type: sampleType, predicate: predicate, anchor: anchor, limit: HKObjectQueryNoLimit) { q, added, deleted, newAnchor, err in
            if let err = err { lastError = err; semaphore.signal(); return }
            if let added = added {
                for obj in added {
                    if let rec = self.compactify(sample: obj, label: label) {
                        if let data = try? JSONSerialization.data(withJSONObject: rec, options: []) {
                            handle.seekToEndOfFile()
                            handle.write(data)
                            handle.write("\n".data(using: .utf8)!)
                        }
                    }
                }
            }
            anchor = newAnchor
            semaphore.signal()
        }
        query.updateHandler = { q, added, deleted, newAnchor, err in
            if let added = added {
                for obj in added {
                    if let rec = self.compactify(sample: obj, label: label) {
                        if let data = try? JSONSerialization.data(withJSONObject: rec, options: []) {
                            handle.seekToEndOfFile()
                            handle.write(data)
                            handle.write("\n".data(using: .utf8)!)
                        }
                    }
                }
            }
        }
        store.execute(query)
        _ = semaphore.wait(timeout: .now() + 30)
        if let err = lastError { throw err }
    }

    private func compactify(sample: HKObject, label: String) -> [String: Any]? {
        guard let s = sample as? HKSample else { return nil }
        var dict: [String: Any] = [:]
        dict["type"] = label
        dict["startDate"] = Int64(s.startDate.timeIntervalSince1970 * 1000.0)
        dict["endDate"] = Int64(s.endDate.timeIntervalSince1970 * 1000.0)
        dict["source"] = s.sourceRevision.source.name
        if let q = s as? HKQuantitySample {
            // Use different units depending on type identifier
            let id = q.quantityType.identifier
            if id == HKQuantityTypeIdentifier.heartRate.rawValue {
                dict["value"] = q.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                dict["unit"] = "count/min"
            } else if id == HKQuantityTypeIdentifier.respiratoryRate.rawValue {
                dict["value"] = q.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                dict["unit"] = "breaths/min"
            } else if id == HKQuantityTypeIdentifier.oxygenSaturation.rawValue {
                dict["value"] = q.quantity.doubleValue(for: HKUnit.percent()) * 100.0
                dict["unit"] = "%"
            } else if id == HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue {
                dict["value"] = q.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                dict["unit"] = "ms"
            } else {
                dict["value"] = q.quantity.doubleValue(for: HKUnit.count())
                dict["unit"] = "count"
            }
        }
        if label == "SleepAnalysis", let cat = s as? HKCategorySample {
            var stage = "Unknown"
            if cat.value == HKCategoryValueSleepAnalysis.inBed.rawValue { stage = "InBed" }
            else if cat.value == HKCategoryValueSleepAnalysis.asleep.rawValue { stage = "Asleep" }
            else if cat.value == HKCategoryValueSleepAnalysis.awake.rawValue { stage = "Awake" }
            dict["metadata"] = ["stage": stage]
        }
        return dict
    }
}
