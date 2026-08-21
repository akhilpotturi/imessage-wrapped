import SwiftUI

enum AppTheme {
    static let purple = Color(red: 0.48, green: 0.25, blue: 0.98)
    static let pink = Color(red: 1.00, green: 0.25, blue: 0.58)
    static let orange = Color(red: 1.00, green: 0.55, blue: 0.16)
    static let cyan = Color(red: 0.08, green: 0.72, blue: 0.92)
    static let mint = Color(red: 0.12, green: 0.78, blue: 0.60)

    static let heroGradient = LinearGradient(
        colors: [purple, pink, orange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let coolGradient = LinearGradient(
        colors: [cyan, purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct PlayfulBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            Circle()
                .fill(AppTheme.purple.opacity(0.16))
                .frame(width: 480, height: 480)
                .blur(radius: 80)
                .offset(x: 350, y: -260)

            Circle()
                .fill(AppTheme.pink.opacity(0.12))
                .frame(width: 380, height: 380)
                .blur(radius: 75)
                .offset(x: -390, y: 260)

            Circle()
                .fill(AppTheme.cyan.opacity(0.11))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: 250, y: 340)
        }
        .ignoresSafeArea()
    }
}

struct ColorfulCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: AppTheme.purple.opacity(0.08), radius: 20, y: 8)
    }
}
