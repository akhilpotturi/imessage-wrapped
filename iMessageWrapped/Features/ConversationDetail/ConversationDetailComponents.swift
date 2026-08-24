import SwiftUI

// MARK: - Shared conversation detail components

struct SectionLoadingOverlay: View {
    let title: String
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(AppTheme.pink.opacity(0.3), lineWidth: 3)
                        .frame(width: 58, height: 58)
                        .scaleEffect(isPulsing ? 1.55 : 0.75)
                        .opacity(isPulsing ? 0 : 1)
                        .animation(
                            .easeOut(duration: 1.1).repeatForever(autoreverses: false),
                            value: isPulsing
                        )

                    Image(systemName: "sparkles")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(AppTheme.heroGradient, in: Circle())
                        .scaleEffect(isPulsing ? 1.05 : 0.95)
                        .animation(
                            .easeInOut(duration: 0.65).repeatForever(autoreverses: true),
                            value: isPulsing
                        )
                }

                Text(title)
                    .font(.headline)
            }
            .padding(24)
        }
        .onAppear {
            isPulsing = true
        }
        .transition(.opacity)
    }
}

struct BrandedMenuLabel: View {
    let icon: String?
    let title: String
    let colors: [Color]

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
            }
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.bold())
                .opacity(0.7)
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .shadow(color: colors[0].opacity(0.2), radius: 10, y: 4)
    }
}

struct FilterPillLabel: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.pink)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.caption2.bold())
                .foregroundStyle(AppTheme.purple.opacity(0.7))
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [AppTheme.purple.opacity(0.12), AppTheme.pink.opacity(0.08)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.purple.opacity(0.45), AppTheme.pink.opacity(0.35)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        }
    }
}
