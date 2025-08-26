import SwiftUI

struct SpectrumView: View {
    @ObservedObject var audioManager: AudioManager
    
    private let bandNames = ["Sub", "Bass", "L-Mid", "Mid", "U-Mid", "Pres", "Brill", "Air"]
    private let bandColors: [Color] = [
        .purple,
        .indigo,
        .blue,
        .cyan,
        .green,
        .yellow,
        .orange,
        .pink
    ]
    
    var body: some View {
        VStack(spacing: 4) {
            // Main spectrum display
            HStack(spacing: 3) {
                ForEach(0..<8) { index in
                    VStack(spacing: 2) {
                        Spacer()
                        
                        // Bar visualization
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        bandColors[index].opacity(0.3),
                                        bandColors[index],
                                        bandColors[index].opacity(0.8)
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(
                                width: 25,
                                height: CGFloat(audioManager.spectrumData[safe: index] ?? 0) * 80
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(bandColors[index].opacity(0.5), lineWidth: 1)
                            )
                            .shadow(
                                color: bandColors[index].opacity(audioManager.spectrumData[safe: index] ?? 0),
                                radius: 4
                            )
                            .animation(.spring(response: 0.1, dampingFraction: 0.7), value: audioManager.spectrumData[safe: index] ?? 0)
                        
                        // Band label
                        Text(bandNames[index])
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(height: 100)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.3))
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            
            // Frequency info
            HStack(spacing: 16) {
                // Dominant frequency display
                VStack(alignment: .leading, spacing: 2) {
                    Text("Frequency")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(Int(audioManager.dominantFrequencyHz)) Hz")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                    Text(noteFromFrequency(audioManager.dominantFrequencyHz))
                        .font(.system(size: 10))
                        .foregroundColor(.cyan.opacity(0.8))
                }
                
                Divider()
                    .frame(height: 30)
                    .overlay(Color.white.opacity(0.2))
                
                // Energy levels
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 12) {
                        EnergyIndicator(label: "Bass", value: audioManager.bassEnergy, color: .indigo)
                        EnergyIndicator(label: "Mid", value: audioManager.midEnergy, color: .green)
                        EnergyIndicator(label: "High", value: audioManager.highEnergy, color: .orange)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.4))
            )
        }
    }
    
    private func noteFromFrequency(_ frequency: Float) -> String {
        guard frequency > 0 else { return "--" }
        
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let a4 = Float(440.0)
        let c0 = a4 * pow(2, -4.75)
        
        if frequency > c0 {
            let halfSteps = 12 * log2(frequency / c0)
            let noteIndex = Int(round(halfSteps)) % 12
            let octave = Int(round(halfSteps)) / 12
            return "\(noteNames[noteIndex])\(octave)"
        }
        
        return "--"
    }
}

struct EnergyIndicator: View {
    let label: String
    let value: Float
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.5))
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 40, height: 4)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: CGFloat(value) * 40, height: 4)
            }
        }
    }
}

// Safe array access extension
extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct SpectrumView_Previews: PreviewProvider {
    static var previews: some View {
        SpectrumView(audioManager: AudioManager())
            .background(Color.black)
    }
}