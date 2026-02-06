import SwiftUI

/// A minimal unobtrusive audio visualizer shown as a small circle.
/// The circle gently scales with the current audio amplitude.
struct MiniVisualizerView: View {
    var amplitude: Float

    var body: some View {
        Circle()
            .strokeBorder(Color.white.opacity(0.5), lineWidth: 2)
            .background(
                Circle().fill(Color.white.opacity(0.2))
            )
            .frame(width: 20, height: 20)
            .scaleEffect(1 + CGFloat(amplitude) * 0.8)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: amplitude)
    }
}

#Preview {
    MiniVisualizerView(amplitude: 0.5)
        .padding()
        .background(Color.black)
}
