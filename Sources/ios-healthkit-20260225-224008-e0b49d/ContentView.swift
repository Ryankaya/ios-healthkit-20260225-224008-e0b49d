import SwiftUI
import HealthKit

@MainActor
final class HealthKitViewModel: ObservableObject {
    @Published var status: String = "Not requested"
    @Published var todaySteps: String = "-"

    private let healthStore = HKHealthStore()

    func requestAccessAndLoadSteps() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = "Health data unavailable on this device."
            return
        }

        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            status = "Step count type unavailable."
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [stepType])
            status = "Authorized to read step count."
            try await loadTodaySteps(stepType: stepType)
        } catch {
            status = "Authorization/query failed: \(error.localizedDescription)"
        }
    }

    private func loadTodaySteps(stepType: HKQuantityType) async throws {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: stepType, predicate: predicate),
            options: .cumulativeSum
        )

        let result = try await descriptor.result(for: healthStore)
        let count = result.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
        todaySteps = NumberFormatter.localizedString(from: NSNumber(value: Int(count)), number: .decimal)
    }
}

struct ContentView: View {
    @StateObject private var viewModel = HealthKitViewModel()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("HealthKit Step Count")
                    .font(.title2.weight(.semibold))

                Text("Demonstrates requesting HealthKit authorization and reading today's cumulative steps.")
                    .foregroundStyle(.secondary)

                LabeledContent("Authorization", value: viewModel.status)
                LabeledContent("Today", value: "\(viewModel.todaySteps) steps")

                Button("Request Access + Load Steps") {
                    Task {
                        await viewModel.requestAccessAndLoadSteps()
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("HealthKit Demo")
        }
    }
}

#Preview {
    ContentView()
}
