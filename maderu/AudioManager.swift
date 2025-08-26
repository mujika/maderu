import Foundation
import AVFoundation
import Accelerate

class AudioManager: NSObject, ObservableObject {
    @Published var amplitude: Float = 0.0
    @Published var frequency: Float = 0.0
    @Published var isRecording = false
    @Published var spectrumData: [Float] = Array(repeating: 0, count: 8)
    @Published var dominantFrequencyHz: Float = 0.0
    @Published var bassEnergy: Float = 0.0
    @Published var midEnergy: Float = 0.0
    @Published var highEnergy: Float = 0.0
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var bus: AVAudioNodeBus = 0
    
    private let bufferSize: AVAudioFrameCount = 1024
    private var fftSetup: FFTSetup?
    private var window: [Float] = []
    
    override init() {
        super.init()
        setupAudio()
    }
    
    deinit {
        if let fftSetup = fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }
    
    private func setupAudio() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            if granted {
                DispatchQueue.main.async {
                    self?.setupAudioEngine()
                }
            } else {
                print("Audio permission denied")
            }
        }
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("Failed to create AVAudioEngine")
            return
        }
        
        inputNode = audioEngine.inputNode
        
        let log2n = vDSP_Length(round(log2(Double(bufferSize))))
        fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2))
        
        window = [Float](repeating: 0, count: Int(bufferSize))
        vDSP_hamm_window(&window, vDSP_Length(bufferSize), 0)
        
        guard let inputNode = inputNode else {
            print("Failed to get input node")
            return
        }
        
        let format = inputNode.outputFormat(forBus: bus)
        
        if format.sampleRate == 0 {
            print("Invalid audio format - sample rate is 0")
            return
        }
        
        inputNode.installTap(onBus: bus, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        print("Audio engine setup completed with format: \(format)")
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameCount = Int(buffer.frameLength)
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))
        
        var windowed = [Float](repeating: 0, count: frameCount)
        vDSP_vmul(channelData, 1, window, 1, &windowed, 1, vDSP_Length(frameCount))
        
        let (dominantFreq, spectrum) = calculateSpectrumData(windowed, sampleRate: Float(buffer.format.sampleRate))
        
        DispatchQueue.main.async {
            self.amplitude = min(rms * 10, 1.0)
            self.frequency = dominantFreq / 1000.0
            self.dominantFrequencyHz = dominantFreq
            self.spectrumData = spectrum
            
            // Calculate energy bands
            self.bassEnergy = (spectrum[0] + spectrum[1]) / 2.0
            self.midEnergy = (spectrum[2] + spectrum[3] + spectrum[4]) / 3.0
            self.highEnergy = (spectrum[5] + spectrum[6] + spectrum[7]) / 3.0
        }
    }
    
    private func calculateSpectrumData(_ samples: [Float], sampleRate: Float) -> (dominantFreq: Float, spectrum: [Float]) {
        guard let fftSetup = fftSetup else { return (0, Array(repeating: 0, count: 8)) }
        
        let log2n = vDSP_Length(round(log2(Double(samples.count))))
        let n = Int(1 << log2n)
        let nOver2 = n / 2
        
        var realp = [Float](repeating: 0, count: nOver2)
        var imagp = [Float](repeating: 0, count: nOver2)
        
        return realp.withUnsafeMutableBufferPointer { realPtr in
            return imagp.withUnsafeMutableBufferPointer { imagPtr in
                var output = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                
                samples.withUnsafeBufferPointer { samplesPtr in
                    samplesPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &output, 1, vDSP_Length(nOver2))
                    }
                }
                
                vDSP_fft_zrip(fftSetup, &output, 1, log2n, Int32(FFT_FORWARD))
                
                var magnitudes = [Float](repeating: 0, count: nOver2)
                vDSP_zvmags(&output, 1, &magnitudes, 1, vDSP_Length(nOver2))
                
                // Find dominant frequency
                var maxValue: Float = 0
                var maxIndex: vDSP_Length = 0
                vDSP_maxvi(magnitudes, 1, &maxValue, &maxIndex, vDSP_Length(nOver2))
                let dominantFrequency = Float(maxIndex) * sampleRate / Float(n)
                
                // Calculate 8-band spectrum (logarithmic scale)
                var spectrum = [Float](repeating: 0, count: 8)
                let nyquist = sampleRate / 2.0
                
                // Define frequency bands (Hz)
                let bands: [(Float, Float)] = [
                    (20, 60),      // Sub-bass
                    (60, 250),     // Bass
                    (250, 500),    // Low-mid
                    (500, 1000),   // Mid
                    (1000, 2000),  // Upper-mid
                    (2000, 4000),  // Presence
                    (4000, 8000),  // Brilliance
                    (8000, nyquist) // Air
                ]
                
                for (index, band) in bands.enumerated() {
                    let startBin = Int((band.0 * Float(n)) / sampleRate)
                    let endBin = min(Int((band.1 * Float(n)) / sampleRate), nOver2 - 1)
                    
                    if startBin < endBin {
                        var bandEnergy: Float = 0
                        for bin in startBin...endBin {
                            bandEnergy += magnitudes[bin]
                        }
                        
                        // Normalize and apply logarithmic scaling
                        let avgEnergy = bandEnergy / Float(endBin - startBin + 1)
                        spectrum[index] = min(log10(1 + avgEnergy * 10) / 2.0, 1.0)
                    }
                }
                
                return (dominantFrequency, spectrum)
            }
        }
    }
    
    private func calculateDominantFrequency(_ samples: [Float], sampleRate: Float) -> Float {
        guard let fftSetup = fftSetup else { return 0 }
        
        let log2n = vDSP_Length(round(log2(Double(samples.count))))
        let n = Int(1 << log2n)
        let nOver2 = n / 2
        
        var realp = [Float](repeating: 0, count: nOver2)
        var imagp = [Float](repeating: 0, count: nOver2)
        
        return realp.withUnsafeMutableBufferPointer { realPtr in
            return imagp.withUnsafeMutableBufferPointer { imagPtr in
                var output = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                
                samples.withUnsafeBufferPointer { samplesPtr in
                    samplesPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &output, 1, vDSP_Length(nOver2))
                    }
                }
                
                vDSP_fft_zrip(fftSetup, &output, 1, log2n, Int32(FFT_FORWARD))
                
                var magnitudes = [Float](repeating: 0, count: nOver2)
                vDSP_zvmags(&output, 1, &magnitudes, 1, vDSP_Length(nOver2))
                
                var maxValue: Float = 0
                var maxIndex: vDSP_Length = 0
                vDSP_maxvi(magnitudes, 1, &maxValue, &maxIndex, vDSP_Length(nOver2))
                
                let dominantFrequency = Float(maxIndex) * sampleRate / Float(n)
                return dominantFrequency
            }
        }
    }
    
    func startRecording() {
        guard let audioEngine = audioEngine else {
            print("Audio engine not initialized. Attempting to setup...")
            setupAudioEngine()
            return
        }
        
        do {
            if !audioEngine.isRunning {
                try audioEngine.start()
                isRecording = true
                print("Audio recording started")
            }
        } catch {
            print("Error starting audio engine: \(error.localizedDescription)")
            
            if (error as NSError).code == -10877 {
                print("Audio input device error. Please check your microphone settings.")
            }
            
            isRecording = false
        }
    }
    
    func stopRecording() {
        if let audioEngine = audioEngine, audioEngine.isRunning {
            audioEngine.stop()
            print("Audio recording stopped")
        }
        isRecording = false
    }
}