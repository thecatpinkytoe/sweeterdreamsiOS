import SwiftUI

struct ContentView: View {
    @StateObject private var manager = HealthManager.shared
    @State private var status = "Idle"
    @State private var exporting = false
    @State private var startDate = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
    @State private var endDate = Date()

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Health Exporter (cloud build)").font(.headline)
                Text(status).font(.subheadline).foregroundColor(.gray)
                DatePicker("Start", selection: $startDate, displayedComponents: .date)
                DatePicker("End", selection: $endDate, displayedComponents: .date)
                HStack {
                    Button("Authorize") { Task { await authorize() } }
                    Button("Export") { Task { await export() } }.disabled(exporting)
                }
                Spacer()
            }.padding()
        }
    }

    func authorize() async {
        do {
            let ok = try await manager.requestAuthorization()
            status = ok ? "Authorized" : "Authorization failed"
        } catch {
            status = "Auth error: \(error.localizedDescription)"
        }
    }

    func export() async {
        exporting = true
        status = "Starting export..."
        do {
            let url = try await manager.exportNDJSON(start: startDate, end: endDate)
            status = "Exported to: \(url.lastPathComponent)"
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
        exporting = false
    }
}
