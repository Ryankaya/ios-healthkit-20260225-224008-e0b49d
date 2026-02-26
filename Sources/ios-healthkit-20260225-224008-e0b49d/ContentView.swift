import SwiftUI
import HealthKit
import Charts

struct DailyStep: Identifiable {
    let date: Date
    let steps: Double

    var id: Date { date }
}

enum HealthAuthorizationState: Equatable {
    case unknown
    case requesting
    case authorized
    case denied
    case unavailable
    case failed(String)

    var title: String {
        switch self {
        case .unknown:
            return "Not Requested"
        case .requesting:
            return "Requesting Access"
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .unavailable:
            return "Unavailable"
        case .failed:
            return "Error"
        }
    }

    var symbol: String {
        switch self {
        case .unknown:
            return "questionmark.circle"
        case .requesting:
            return "hourglass.circle"
        case .authorized:
            return "checkmark.shield"
        case .denied:
            return "xmark.shield"
        case .unavailable:
            return "iphone.slash"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .unknown, .requesting:
            return .orange
        case .authorized:
            return .green
        case .denied, .failed:
            return .red
        case .unavailable:
            return .gray
        }
    }

    var detail: String {
        switch self {
        case .unknown:
            return "HealthKit permission has not been requested yet."
        case .requesting:
            return "Waiting for user authorization response."
        case .authorized:
            return "Read access granted for step count."
        case .denied:
            return "Grant Health access in Settings to load step data."
        case .unavailable:
            return "Health data is unavailable on this device."
        case .failed(let message):
            return message
        }
    }
}

@MainActor
final class HealthKitViewModel: ObservableObject {
    @Published var authorizationState: HealthAuthorizationState = .unknown
    @Published var todaySteps: Double = 0
    @Published var weeklySteps: [DailyStep] = []
    @Published var isRefreshing = false
    @Published var lastUpdated: Date?

    let dailyGoal: Double = 10_000

    private let healthStore = HKHealthStore()
    private let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)

    func bootstrap() async {
        updateAuthorizationState()
        if authorizationState == .authorized {
            await refreshData()
        }
    }

    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            return
        }

        guard let stepType else {
            authorizationState = .failed("Step count type is unavailable.")
            return
        }

        authorizationState = .requesting

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [stepType])
            updateAuthorizationState()
            if authorizationState == .authorized {
                await refreshData()
            }
        } catch {
            authorizationState = .failed("Authorization failed: \(error.localizedDescription)")
        }
    }

    func refreshData() async {
        guard authorizationState == .authorized else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let today = fetchTodaySteps()
            async let week = fetchLastSevenDays()
            todaySteps = try await today
            weeklySteps = try await week
            lastUpdated = Date()
        } catch {
            authorizationState = .failed("Query failed: \(error.localizedDescription)")
        }
    }

    func updateAuthorizationState() {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            return
        }

        guard let stepType else {
            authorizationState = .failed("Step count type is unavailable.")
            return
        }

        switch healthStore.authorizationStatus(for: stepType) {
        case .notDetermined:
            authorizationState = .unknown
        case .sharingDenied:
            authorizationState = .denied
        case .sharingAuthorized:
            authorizationState = .authorized
        @unknown default:
            authorizationState = .failed("Unknown authorization state.")
        }
    }

    private func fetchTodaySteps() async throws -> Double {
        guard let stepType else {
            return 0
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = result?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func fetchLastSevenDays() async throws -> [DailyStep] {
        guard let stepType else {
            return []
        }

        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: endDate)) ?? calendar.startOfDay(for: endDate)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let anchorDate = calendar.startOfDay(for: endDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: DateComponents(day: 1)
            )

            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }

                var values: [DailyStep] = []
                collection.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    let count = statistics.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                    values.append(DailyStep(date: statistics.startDate, steps: count))
                }

                continuation.resume(returning: values)
            }

            healthStore.execute(query)
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = HealthKitViewModel()

    private var completionRatio: Double {
        guard viewModel.dailyGoal > 0 else { return 0 }
        return min(viewModel.todaySteps / viewModel.dailyGoal, 1)
    }

    private var weeklyAverage: Double {
        guard !viewModel.weeklySteps.isEmpty else { return 0 }
        let total = viewModel.weeklySteps.reduce(0) { $0 + $1.steps }
        return total / Double(viewModel.weeklySteps.count)
    }

    private var maxChartValue: Double {
        max(12_000, (viewModel.weeklySteps.map(\.steps).max() ?? 0) * 1.2)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.teal.opacity(0.22), Color.cyan.opacity(0.12), Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        accessCard
                        todayCard
                        chartCard
                    }
                    .padding()
                }
            }
            .navigationTitle("HealthKit Steps")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refreshData() }
                    } label: {
                        if viewModel.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.authorizationState != .authorized || viewModel.isRefreshing)
                }
            }
            .task {
                await viewModel.bootstrap()
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Step Dashboard", systemImage: "figure.walk")
                .font(.title3.bold())

            Text("Request HealthKit access, track today's progress, and view a 7-day step trend.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(viewModel.authorizationState.title, systemImage: viewModel.authorizationState.symbol)
                    .font(.headline)
                    .foregroundStyle(viewModel.authorizationState.tint)

                Spacer()
            }

            Text(viewModel.authorizationState.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Request Access") {
                    Task { await viewModel.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.authorizationState == .requesting || viewModel.authorizationState == .unavailable)

                Button("Refresh Data") {
                    Task { await viewModel.refreshData() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.authorizationState != .authorized || viewModel.isRefreshing)
            }

            if let lastUpdated = viewModel.lastUpdated {
                Text("Updated \(lastUpdated, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)

            Text("\(Int(viewModel.todaySteps), format: .number.grouping(.automatic)) steps")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            ProgressView(value: completionRatio) {
                Text("Goal: \(Int(viewModel.dailyGoal), format: .number.grouping(.automatic))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tint(.teal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last 7 Days")
                    .font(.headline)

                Spacer()

                Text("Avg \(Int(weeklyAverage), format: .number.grouping(.automatic))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if viewModel.weeklySteps.isEmpty {
                Text("Authorize HealthKit and tap Refresh Data to populate the chart.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                Chart(viewModel.weeklySteps) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Steps", day.steps)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.teal, Color.cyan],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(6)
                }
                .chartYScale(domain: 0...maxChartValue)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 210)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    ContentView()
}
