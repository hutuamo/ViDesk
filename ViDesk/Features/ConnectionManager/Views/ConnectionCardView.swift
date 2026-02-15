import SwiftUI

/// 连接卡片视图
struct ConnectionCardView: View {
    let config: ConnectionConfig
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // 图标
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.blue.gradient)
                        .frame(width: 48, height: 48)

                    Image(systemName: "desktopcomputer")
                        .font(.title2)
                        .foregroundStyle(.white)
                }

                // 信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(config.displayTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(config.fullAddress)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if !config.username.isEmpty {
                            Text("@\(config.username)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .lineLimit(1)

                    if let lastConnected = config.lastConnectedAt {
                        Text(formattedDate(lastConnected))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // 连接按钮
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(isHovered ? 0.1 : 0.05), radius: isHovered ? 8 : 4)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "zh_CN")
        return "上次连接: " + formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// 连接卡片紧凑视图 (用于最近使用)
struct ConnectionCardCompactView: View {
    let config: ConnectionConfig
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "desktopcomputer")
                        .font(.title3)
                        .foregroundStyle(.blue)

                    Spacer()

                    if config.lastConnectedAt != nil {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(config.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(config.hostname)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding()
            .frame(width: 140, height: 100)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview("Card") {
    VStack(spacing: 16) {
        ConnectionCardView(config: .preview) {}
        ConnectionCardView(config: ConnectionConfig(name: "", hostname: "192.168.1.100")) {}
    }
    .padding()
}

#Preview("Compact") {
    HStack {
        ConnectionCardCompactView(config: .preview) {}
        ConnectionCardCompactView(config: ConnectionConfig(name: "Server", hostname: "10.0.0.1")) {}
    }
    .padding()
}
