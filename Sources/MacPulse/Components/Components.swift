import AppKit
import Charts
import SwiftUI

enum Fmt {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func bytes(_ value: UInt64) -> String {
        bytes(Int64(clamping: value))
    }

    static func memory(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    static func memory(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval) ?? "–"
    }
}

extension Color {
    static func usage(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: .green
        case ..<0.85: .orange
        default: .red
        }
    }
}

struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardBackground()
    }
}

extension View {
    func cardBackground(cornerRadius: CGFloat = 14) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        )
    }
}

struct RingGauge: View {
    let value: Double
    let caption: String
    var lineWidth: CGFloat = 11

    var body: some View {
        let clamped = min(max(value, 0), 1)
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(Color.usage(clamped).gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(Fmt.percent(clamped))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.easeOut(duration: 0.4), value: clamped)
    }
}

struct UsageBar: View {
    let fraction: Double
    var tint: Color?
    var height: CGFloat = 8

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill((tint ?? .usage(clamped)).gradient)
                    .frame(width: clamped > 0 ? max(proxy.size.width * clamped, height) : 0)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.3), value: clamped)
    }
}

struct UsageChart: View {
    let samples: [UsageSample]
    let color: Color

    var body: some View {
        Chart(samples) { sample in
            AreaMark(x: .value("Tempo", sample.id), y: .value("Uso", sample.value))
                .foregroundStyle(
                    LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                )
                .interpolationMethod(.monotone)
            LineMark(x: .value("Tempo", sample.id), y: .value("Uso", sample.value))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 0.5, 1]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let fraction = value.as(Double.self) { Text(Fmt.percent(fraction)) }
                }
            }
        }
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    var color: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let color {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

struct MiniStat: View {
    let title: String
    let fraction: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.medium))
                Spacer()
                Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            UsageBar(fraction: fraction, height: 5)
        }
    }
}

struct Checkbox: View {
    let state: SelectionState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(state == .none ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private var symbol: String {
        switch state {
        case .none: "square"
        case .partial: "minus.square.fill"
        case .all: "checkmark.square.fill"
        }
    }
}

struct FileIcon: View {
    let path: String
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: IconCache.shared.icon(forPath: path))
            .resizable()
            .frame(width: size, height: size)
    }
}

enum Finder {
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func chooseFolder(prompt: String, startingAt url: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = url
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
