import SwiftUI
import Charts

struct TelemetryView: View {
    @ObservedObject private var telemetryManager = TelemetryManager.shared
    @State private var selectedTab: String = "Dia"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Gráfico de Velocidade")
                    .font(.headline)
                    .padding(.top, 8)

                Picker("", selection: $selectedTab) {
                    Text("Dia").tag("Dia")
                    Text("Semana").tag("Semana")
                    Text("Mês").tag("Mês")
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                chartSection
                Divider().padding(.horizontal)
                statsSection
                Spacer()
            }
            .navigationBarTitle("Telemetria", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    // MARK: - Chart Section

    private var chartSection: some View {
        VStack {
            if selectedTab == "Dia" {
                dynamicChart(for: filteredDailyData, title: "Hoje")
            } else if selectedTab == "Semana" {
                dynamicChart(for: weeklyAggregatedData, title: currentMonthName)
            } else {
                dynamicChart(for: monthlyAggregatedData, title: currentMonthName)
            }
        }
        .padding(.horizontal)
        .frame(height: 280)
    }

    // MARK: - Chart Builder

    private func dynamicChart(for dataPoints: [SpeedDataPoint], title: String) -> some View {
        let valid = dataPoints.filter { $0.speed >= 15 }
        let speeds = valid.map(\.speed)
        let minDate = valid.first?.timestamp ?? Date()
        let maxDate = valid.last?.timestamp ?? Date()
        let maxSpeed = (speeds.max() ?? 0) * 1.1

        return VStack(spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
                .padding(.top, 4)

            Chart {
                ForEach(valid) { point in
                    LineMark(
                        x: .value("Hora", point.timestamp),
                        y: .value("Velocidade", point.speed)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)

                    PointMark(
                        x: .value("Hora", point.timestamp),
                        y: .value("Velocidade", point.speed)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(15)
                }
            }
            .chartXScale(domain: minDate...maxDate)
            .chartYScale(domain: 0...maxSpeed)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v)) km/h")
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisValueLabel {
                        if selectedTab == "Dia" {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(.dateTime.hour()))
                            }
                        } else {
                            if let date = value.as(Date.self) {
                                let day = Calendar.current.component(.day, from: date)
                                Text(String(day))
                            }
                        }
                    }
                    AxisGridLine()
                }
            }
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Estatísticas de Viagem (Geral)")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 8) {
                HStack {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Velocidade Máxima Registrada")
                            Text("\(telemetryManager.maxSpeed, specifier: "%.1f") km/h")
                                .font(.title3.bold())
                        }
                    } icon: {
                        Image(systemName: "hare.fill").foregroundColor(.red)
                    }
                    Spacer()
                }

                Divider()

                HStack {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Velocidade Média Geral")
                            Text("\(telemetryManager.averageSpeed, specifier: "%.1f") km/h")
                                .font(.title3.bold())
                        }
                    } icon: {
                        Image(systemName: "tortoise.fill").foregroundColor(.blue)
                    }
                    Spacer()
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    // MARK: - Data

    private var filteredDailyData: [SpeedDataPoint] {
        telemetryManager.dataPoints
            .filter { Calendar.current.isDateInToday($0.timestamp) && $0.speed >= 15 }
            .sorted(by: { $0.timestamp < $1.timestamp })
    }

    private var weeklyAggregatedData: [SpeedDataPoint] {
        aggregateData(for: .weekOfYear)
    }

    private var monthlyAggregatedData: [SpeedDataPoint] {
        aggregateData(for: .month)
    }

    private func aggregateData(for component: Calendar.Component) -> [SpeedDataPoint] {
        let filtered = telemetryManager.dataPoints.filter { $0.speed >= 15 }
        let grouped = Dictionary(grouping: filtered) {
            Calendar.current.dateInterval(of: component, for: $0.timestamp)?.start ?? $0.timestamp
        }

        return grouped.map { key, points in
            let avg = points.reduce(0) { $0 + $1.speed } / Double(points.count)
            return SpeedDataPoint(timestamp: key, speed: avg)
        }
        .sorted(by: { $0.timestamp < $1.timestamp })
    }

    private var currentMonthName: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: Date()).capitalized
    }
}

