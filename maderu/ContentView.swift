//
//  ContentView.swift
//  maderu
//
//  Created by 新村彰啓 on 8/25/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @State private var showSettings = false
    @State private var zoomLevel: Float = 2.0
    @State private var currentLocation: String = "Mandelbrot Set"
    
    var body: some View {
        ZStack {
            MandelbrotView(audioManager: audioManager, zoomLevel: $zoomLevel, currentLocation: $currentLocation)
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Mandelbrot Audio Visualizer")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                        
                        HStack {
                            Circle()
                                .fill(audioManager.isRecording ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            Text(audioManager.isRecording ? "Recording" : "Stopped")
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }
                        
                        Text("Location: \(currentLocation)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(radius: 2)
                        
                        Text("Zoom: \(formatZoomLevel(zoomLevel))")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(radius: 2)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack {
                            Text("Amplitude:")
                                .foregroundColor(.white.opacity(0.8))
                            ProgressView(value: Double(audioManager.amplitude))
                                .frame(width: 100)
                                .tint(.green)
                        }
                        
                        HStack {
                            Text("Frequency:")
                                .foregroundColor(.white.opacity(0.8))
                            ProgressView(value: Double(min(audioManager.frequency, 1.0)))
                                .frame(width: 100)
                                .tint(.blue)
                        }
                    }
                    
                    Button(action: {
                        if audioManager.isRecording {
                            audioManager.stopRecording()
                        } else {
                            audioManager.startRecording()
                        }
                    }) {
                        Image(systemName: audioManager.isRecording ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(audioManager.isRecording ? .red : .green)
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 20)
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .cornerRadius(12)
                
                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
    private func formatZoomLevel(_ zoom: Float) -> String {
        if zoom >= 0.1 {
            return String(format: "%.2fx", 2.0 / zoom)
        } else if zoom >= 0.001 {
            return String(format: "%.0fx", 2.0 / zoom)
        } else {
            let exponent = Int(log10(2.0 / zoom))
            return "10^\(exponent)x"
        }
    }
}

#Preview {
    ContentView()
}
