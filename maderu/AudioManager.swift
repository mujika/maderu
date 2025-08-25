import Foundation
import AVFoundation
import Accelerate

class AudioManager: NSObject, ObservableObject {
    @Published var amplitude: Float = 0.0
    @Published var frequency: Float = 0.0
    @Published var isRecording = false
    
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
        
        let dominantFreq = calculateDominantFrequency(windowed, sampleRate: Float(buffer.format.sampleRate))
        
        DispatchQueue.main.async {
            self.amplitude = min(rms * 10, 1.0)
            self.frequency = dominantFreq / 1000.0
        }
    }
    
    private func calculateDominantFrequency(_ samples: [Float], sampleRate: Float) -> Float {
        guard let fftSetup = fftSetup else { return 0 }
        
        let log2n = vDSP_Length(round(log2(Double(samples.count))))
        let n = Int(1 << log2n)
        let nOver2 = n / 2
        
        var realp = [Float](repeating: 0, count: nOver2)
        var imagp = [Float](repeating: 0, count: nOver2)
        var output = DSPSplitComplex(realp: &realp, imagp: &imagp)
        
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