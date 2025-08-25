import SwiftUI
import MetalKit
import Metal

struct MandelbrotView: NSViewRepresentable {
    @ObservedObject var audioManager: AudioManager
    @Binding var zoomLevel: Float
    @Binding var currentLocation: String
    
    func makeNSView(context: Context) -> MTKView {
        let metalView = MTKView()
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return metalView
        }
        
        metalView.device = device
        metalView.delegate = context.coordinator
        metalView.enableSetNeedsDisplay = true
        metalView.isPaused = false
        metalView.preferredFramesPerSecond = 60
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = false
        
        context.coordinator.setupMetal(device: device)
        
        return metalView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.amplitude = audioManager.amplitude
        context.coordinator.frequency = audioManager.frequency
        DispatchQueue.main.async {
            self.zoomLevel = context.coordinator.currentZoom
            self.currentLocation = context.coordinator.getCurrentLocationName()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(audioManager: audioManager)
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        private var commandQueue: MTLCommandQueue?
        private var pipelineState: MTLComputePipelineState?
        private var device: MTLDevice?
        private var audioManager: AudioManager
        private var isMetalSetup = false
        
        var amplitude: Float = 0.0
        var frequency: Float = 0.0
        private var time: Float = 0.0
        
        // Zoom state management
        private var currentZoom: Float = 2.0
        private var targetZoom: Float = 2.0
        private var centerX: Float = -0.5
        private var centerY: Float = 0.0
        private var autoZoomEnabled = true
        private var zoomSpeed: Float = 0.995
        
        // Interesting coordinates to explore
        private let presetCoordinates: [(x: Float, y: Float, name: String)] = [
            (-0.7269, 0.1889, "Seahorse Valley"),
            (-0.8, 0.156, "Elephant Valley"),
            (-0.74529, 0.11307, "Triple Spiral"),
            (-1.25066, 0.02012, "Miniature Mandelbrot"),
            (-0.7533, 0.1138, "Dragon Valley"),
            (0.274, 0.482, "Feather"),
            (-0.835, -0.2321, "Tendrils"),
            (-0.74591, 0.11254, "Star")
        ]
        private var currentPresetIndex = 0
        private var lastVisitedPreset = ""
        
        func getCurrentLocationName() -> String {
            // Find the closest preset location
            var minDistance: Float = Float.greatestFiniteMagnitude
            var closestPreset = "Exploring..."
            
            for preset in presetCoordinates {
                let distance = sqrt(pow(centerX - preset.x, 2) + pow(centerY - preset.y, 2))
                if distance < minDistance {
                    minDistance = distance
                    closestPreset = preset.name
                }
            }
            
            if minDistance < 0.1 {
                lastVisitedPreset = closestPreset
                return closestPreset
            }
            
            return lastVisitedPreset.isEmpty ? "Exploring..." : "Near \(lastVisitedPreset)"
        }
        
        init(audioManager: AudioManager) {
            self.audioManager = audioManager
            super.init()
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            guard let device = view.device,
                  let drawable = view.currentDrawable else {
                print("Failed to get device or drawable")
                return
            }
            
            if !isMetalSetup {
                setupMetal(device: device)
                return
            }
            
            guard let commandQueue = commandQueue,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let commandEncoder = commandBuffer.makeComputeCommandEncoder(),
                  let pipelineState = pipelineState else {
                print("Metal components not ready")
                return
            }
            
            time += 0.016
            
            // Update zoom based on audio
            if autoZoomEnabled {
                let audioInfluence = amplitude * 0.5 + 0.5
                zoomSpeed = 0.995 - (audioInfluence * 0.01)
                currentZoom *= zoomSpeed
                
                // Navigate to interesting points based on frequency
                if frequency > 0.5 && Int.random(in: 0..<100) < 2 {
                    let preset = presetCoordinates[currentPresetIndex]
                    centerX = centerX * 0.99 + preset.x * 0.01
                    centerY = centerY * 0.99 + preset.y * 0.01
                    currentPresetIndex = (currentPresetIndex + 1) % presetCoordinates.count
                }
                
                // Reset zoom if it gets too deep
                if currentZoom < 1e-15 {
                    currentZoom = 2.0
                    let preset = presetCoordinates[Int.random(in: 0..<presetCoordinates.count)]
                    centerX = preset.x
                    centerY = preset.y
                }
            }
            
            commandEncoder.setComputePipelineState(pipelineState)
            commandEncoder.setTexture(drawable.texture, index: 0)
            
            var params = MandelbrotParams(
                width: Float(drawable.texture.width),
                height: Float(drawable.texture.height),
                amplitude: amplitude,
                frequency: frequency,
                time: time,
                centerX: centerX,
                centerY: centerY,
                zoomLevel: currentZoom
            )
            
            commandEncoder.setBytes(&params, length: MemoryLayout<MandelbrotParams>.size, index: 0)
            
            let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let threadgroupCount = MTLSize(
                width: (drawable.texture.width + threadgroupSize.width - 1) / threadgroupSize.width,
                height: (drawable.texture.height + threadgroupSize.height - 1) / threadgroupSize.height,
                depth: 1
            )
            
            commandEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            commandEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        
        func setupMetal(device: MTLDevice) {
            guard !isMetalSetup else { return }
            
            self.device = device
            commandQueue = device.makeCommandQueue()
            
            print("Setting up Metal with device: \(device.name)")
            
            let metalCode = """
            #include <metal_stdlib>
            using namespace metal;
            
            struct MandelbrotParams {
                float width;
                float height;
                float amplitude;
                float frequency;
                float time;
                float centerX;
                float centerY;
                float zoomLevel;
            };
            
            float3 hsv2rgb(float3 c) {
                float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
                float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
                return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
            }
            
            kernel void mandelbrotShader(texture2d<float, access::write> output [[texture(0)]],
                                        constant MandelbrotParams& params [[buffer(0)]],
                                        uint2 gid [[thread_position_in_grid]]) {
                if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
                    return;
                }
                
                float2 resolution = float2(params.width, params.height);
                float2 uv = (float2(gid) - 0.5 * resolution) / min(resolution.x, resolution.y);
                
                float audioMod = params.amplitude * 0.5 + 0.5;
                
                // Apply zoom and center transformation
                float2 c = uv * params.zoomLevel;
                c.x += params.centerX;
                c.y += params.centerY;
                
                // Add slight audio-driven wobble
                c.x += cos(params.time * 0.3 + params.frequency * 10.0) * audioMod * params.zoomLevel * 0.01;
                c.y += sin(params.time * 0.2 + params.frequency * 5.0) * audioMod * params.zoomLevel * 0.01;
                
                float2 z = float2(0.0, 0.0);
                int iterations = 0;
                
                // Increase iterations for deeper zooms
                int baseIterations = 256;
                float zoomFactor = log10(max(2.0 / params.zoomLevel, 1.0));
                int maxIterations = int(baseIterations + zoomFactor * 100.0 + audioMod * 50.0);
                
                float escape = 4.0;
                
                for (int i = 0; i < 1024; i++) {
                    if (i >= maxIterations) break;
                    
                    float x = z.x * z.x - z.y * z.y + c.x;
                    float y = 2.0 * z.x * z.y + c.y;
                    
                    z = float2(x, y);
                    
                    if (length(z) > escape) {
                        break;
                    }
                    iterations++;
                }
                
                float value = float(iterations) / float(maxIterations);
                
                // Enhanced coloring based on zoom level
                float zoomColorShift = log10(max(2.0 / params.zoomLevel, 1.0)) * 30.0;
                float hue = value * 360.0 + params.time * 30.0 + params.frequency * 100.0 + zoomColorShift;
                float saturation = 0.8 + audioMod * 0.2;
                float brightness = value > 0.99 ? 0.0 : 0.8 + audioMod * 0.2;
                
                float3 color = hsv2rgb(float3(hue / 360.0, saturation, brightness));
                
                color = pow(color, 1.0 / 2.2);
                
                output.write(float4(color, 1.0), gid);
            }
            """
            
            do {
                let library = try device.makeLibrary(source: metalCode, options: nil)
                guard let function = library.makeFunction(name: "mandelbrotShader") else {
                    print("Failed to find mandelbrotShader function")
                    return
                }
                pipelineState = try device.makeComputePipelineState(function: function)
                isMetalSetup = true
                print("Metal pipeline created successfully")
            } catch {
                print("Error creating Metal pipeline: \(error)")
                isMetalSetup = false
            }
        }
    }
}

struct MandelbrotParams {
    var width: Float
    var height: Float
    var amplitude: Float
    var frequency: Float
    var time: Float
    var centerX: Float
    var centerY: Float
    var zoomLevel: Float
}