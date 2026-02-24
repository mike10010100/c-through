import SwiftUI

struct HostMacBookNode: View {
    var body: some View {
        VStack(spacing: 2) {
            // Lid (display)
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(
                        colors: [Color(white: 0.42), Color(white: 0.32)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: 340, height: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)
                    .frame(width: 300, height: 185)
                    .overlay(
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.12))
                                .blur(radius: 30)
                                .frame(width: 160)
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        }
                    )
            }
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)

            // Base (keyboard deck)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color(white: 0.35), Color(white: 0.28)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: 370, height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )

                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 300, height: 40)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 120, height: 30)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                }

                // USB-C port indents on left side of base
                VStack(spacing: 20) {
                    Capsule().fill(Color.black.opacity(0.6)).frame(width: 5, height: 16)
                    Capsule().fill(Color.black.opacity(0.6)).frame(width: 5, height: 16)
                }
                .offset(x: -183)
            }
            .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
        }
    }
}
