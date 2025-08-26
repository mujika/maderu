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
        context.coordinator.bassEnergy = audioManager.bassEnergy
        context.coordinator.midEnergy = audioManager.midEnergy
        context.coordinator.highEnergy = audioManager.highEnergy
        context.coordinator.spectrumData = audioManager.spectrumData
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
        private var juliaSetPipelineState: MTLComputePipelineState?
        private var compositePipelineState: MTLComputePipelineState?
        private var device: MTLDevice?
        private var mandelbrotTexture: MTLTexture?
        private var juliaTexture: MTLTexture?
        private var audioManager: AudioManager
        private var isMetalSetup = false
        
        var amplitude: Float = 0.0
        var frequency: Float = 0.0
        var bassEnergy: Float = 0.0
        var midEnergy: Float = 0.0
        var highEnergy: Float = 0.0
        var spectrumData: [Float] = Array(repeating: 0, count: 8)
        private var time: Float = 0.0
        
        // Zoom state management
        var currentZoom: Float = 2.0
        private var targetZoom: Float = 2.0
        private var centerX: Float = -0.5
        private var centerY: Float = 0.0
        private var targetCenterX: Float = -0.5
        private var targetCenterY: Float = 0.0
        private var autoZoomEnabled = true
        private var zoomSpeed: Float = 0.995
        private var cameraEasing: Float = 0.02
        private var zoomEasing: Float = 0.95
        
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
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                print("Failed to create command buffer")
                return
            }
            
            // Create intermediate textures if needed
            let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: drawable.texture.pixelFormat,
                width: drawable.texture.width,
                height: drawable.texture.height,
                mipmapped: false
            )
            textureDesc.usage = [.shaderWrite, .shaderRead]
            
            if mandelbrotTexture?.width != drawable.texture.width || 
               mandelbrotTexture?.height != drawable.texture.height {
                mandelbrotTexture = device.makeTexture(descriptor: textureDesc)
                juliaTexture = device.makeTexture(descriptor: textureDesc)
            }
            
            guard let mandelbrotTex = mandelbrotTexture,
                  let juliaTex = juliaTexture,
                  let pipelineState = pipelineState,
                  let juliaSetPipelineState = juliaSetPipelineState,
                  let compositePipelineState = compositePipelineState else {
                print("Metal textures or pipelines not ready")
                return
            }
            
            time += 0.016
            
            // Update zoom and camera with smooth transitions
            if autoZoomEnabled {
                let audioInfluence = amplitude * 0.5 + 0.5
                
                // Dynamic zoom speed based on audio
                zoomSpeed = 0.995 - (audioInfluence * 0.015)
                targetZoom = currentZoom * zoomSpeed
                
                // Smooth zoom transition with easing
                currentZoom = currentZoom * zoomEasing + targetZoom * (1.0 - zoomEasing)
                
                // Navigate to interesting points based on frequency
                if frequency > 0.5 && Int.random(in: 0..<100) < 3 {
                    let preset = presetCoordinates[currentPresetIndex]
                    targetCenterX = preset.x
                    targetCenterY = preset.y
                    currentPresetIndex = (currentPresetIndex + 1) % presetCoordinates.count
                    
                    // Adjust easing speed for navigation
                    cameraEasing = 0.008
                } else {
                    // Default easing speed
                    cameraEasing = 0.02
                }
                
                // Smooth camera movement with easing
                centerX += (targetCenterX - centerX) * cameraEasing
                centerY += (targetCenterY - centerY) * cameraEasing
                
                // Audio-driven micro movements for liveliness
                let microMovement = audioInfluence * currentZoom * 0.005
                centerX += cos(time * 2.0 + frequency * 20.0) * microMovement
                centerY += sin(time * 1.5 + frequency * 15.0) * microMovement
                
                // Reset zoom if it gets too deep with smooth transition
                if currentZoom < 1e-15 {
                    let preset = presetCoordinates[Int.random(in: 0..<presetCoordinates.count)]
                    currentZoom = 2.0
                    targetZoom = 2.0
                    targetCenterX = preset.x
                    targetCenterY = preset.y
                    cameraEasing = 0.05  // Faster transition for reset
                }
            }
            
            // Generate dynamic Julia set parameters
            let juliaReal = cos(time * 0.1 + frequency * 5.0) * 0.8
            let juliaImag = sin(time * 0.15 + frequency * 3.0) * 0.8
            let layerMix = amplitude * 0.7 + 0.3
            let complexity = currentZoom < 0.1 ? log10(2.0 / currentZoom) / 15.0 : 0.0
            
            var params = MandelbrotParams(
                width: Float(drawable.texture.width),
                height: Float(drawable.texture.height),
                amplitude: amplitude,
                frequency: frequency,
                time: time,
                centerX: centerX,
                centerY: centerY,
                zoomLevel: currentZoom,
                juliaReal: juliaReal,
                juliaImag: juliaImag,
                layerMix: layerMix,
                complexity: complexity,
                bassEnergy: bassEnergy,
                midEnergy: midEnergy,
                highEnergy: highEnergy,
                spectrum0: spectrumData[safe: 0] ?? 0,
                spectrum1: spectrumData[safe: 1] ?? 0,
                spectrum2: spectrumData[safe: 2] ?? 0,
                spectrum3: spectrumData[safe: 3] ?? 0,
                spectrum4: spectrumData[safe: 4] ?? 0,
                spectrum5: spectrumData[safe: 5] ?? 0,
                spectrum6: spectrumData[safe: 6] ?? 0,
                spectrum7: spectrumData[safe: 7] ?? 0
            )
            
            let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let threadgroupCount = MTLSize(
                width: (drawable.texture.width + threadgroupSize.width - 1) / threadgroupSize.width,
                height: (drawable.texture.height + threadgroupSize.height - 1) / threadgroupSize.height,
                depth: 1
            )
            
            // Step 1: Render Julia set to background texture
            guard let juliaEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
            juliaEncoder.setComputePipelineState(juliaSetPipelineState)
            juliaEncoder.setTexture(juliaTex, index: 0)
            juliaEncoder.setBytes(&params, length: MemoryLayout<MandelbrotParams>.size, index: 0)
            juliaEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            juliaEncoder.endEncoding()
            
            // Step 2: Render Mandelbrot set to main texture
            guard let mandelbrotEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
            mandelbrotEncoder.setComputePipelineState(pipelineState)
            mandelbrotEncoder.setTexture(mandelbrotTex, index: 0)
            mandelbrotEncoder.setBytes(&params, length: MemoryLayout<MandelbrotParams>.size, index: 0)
            mandelbrotEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            mandelbrotEncoder.endEncoding()
            
            // Step 3: Composite layers to final output
            guard let compositeEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
            compositeEncoder.setComputePipelineState(compositePipelineState)
            compositeEncoder.setTexture(mandelbrotTex, index: 0)
            compositeEncoder.setTexture(juliaTex, index: 1)
            compositeEncoder.setTexture(drawable.texture, index: 2)
            compositeEncoder.setBytes(&params, length: MemoryLayout<MandelbrotParams>.size, index: 0)
            compositeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            compositeEncoder.endEncoding()
            
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
                float juliaReal;
                float juliaImag;
                float layerMix;
                float complexity;
                float bassEnergy;
                float midEnergy;
                float highEnergy;
                float spectrum[8];
            };
            
            float3 hsv2rgb(float3 c) {
                float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
                float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
                return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
            }
            
            float calculateComplexity(float2 z, int iterations, int maxIterations) {
                float smoothIterations = float(iterations) + 1.0 - log2(log2(length(z)));
                float normalizedIter = smoothIterations / float(maxIterations);
                
                // Calculate fractal dimension approximation
                float dimension = 1.0 + (1.0 - normalizedIter) * 0.5;
                return dimension;
            }
            
            // Orbit trap functions for interior detail
            float circularTrap(float2 z, float radius) {
                return abs(length(z) - radius);
            }
            
            float lineTrap(float2 z) {
                return abs(z.y);  // Distance to x-axis
            }
            
            float crossTrap(float2 z) {
                return min(abs(z.x), abs(z.y));
            }
            
            float spiralTrap(float2 z, float params_time) {
                float angle = atan2(z.y, z.x);
                float radius = length(z);
                float spiral = radius - 0.1 * (angle + params_time);
                return abs(fmod(spiral, 0.2) - 0.1);
            }
            
            float3 getEnhancedColor(float value, float complexity, constant MandelbrotParams& params, float2 position, float orbitTrapValue) {
                float audioMod = params.amplitude * 0.5 + 0.5;
                
                // Multiple color layers based on complexity
                float zoomColorShift = log10(max(2.0 / params.zoomLevel, 1.0)) * 30.0;
                
                // Base color - modulated by frequency bands
                float spectrumColorShift = params.spectrum[0] * 20.0 + params.spectrum[4] * 30.0 + params.spectrum[7] * 40.0;
                float hue1 = value * 360.0 + params.time * 30.0 + params.frequency * 100.0 + zoomColorShift + spectrumColorShift;
                float baseBrightness = 0.3 + (0.5 + audioMod * 0.2) * (1.0 - value) + params.highEnergy * 0.2;
                float3 color1 = hsv2rgb(float3(hue1 / 360.0, 0.8 + audioMod * 0.2, baseBrightness));
                
                // Orbit trap based coloring for interior detail
                float trapInfluence = 1.0 / (1.0 + orbitTrapValue * 10.0);
                float hue2 = complexity * 180.0 + params.time * 50.0 + trapInfluence * 120.0;
                float3 color2 = hsv2rgb(float3(hue2 / 360.0, 0.6 + trapInfluence * 0.3, 0.4 + complexity * 0.4));
                
                // Orbit trap highlight color
                float trapHue = orbitTrapValue * 300.0 + params.time * 80.0 + params.frequency * 200.0;
                float3 trapColor = hsv2rgb(float3(trapHue / 360.0, 0.9, 0.8 + audioMod * 0.2));
                
                // Distance-based shimmer
                float dist = length(position - float2(params.centerX, params.centerY));
                float shimmer = sin(dist * params.zoomLevel * 100.0 + params.time * 10.0) * 0.1 + 0.9;
                
                // Dynamic noise pattern for interior
                float noise1 = sin(position.x * 50.0 + params.time * 5.0) * sin(position.y * 47.0 + params.time * 3.7);
                float noise2 = cos(position.x * 73.0 - params.time * 4.2) * cos(position.y * 67.0 + params.time * 6.1);
                float dynamicNoise = (noise1 + noise2) * 0.1 + 0.9;
                
                // Frequency-band driven particle effects
                float particleEffect = 0.0;
                if (params.highEnergy > 0.5) {
                    float particleX = position.x + sin(params.time * 8.0 + params.frequency * 30.0) * 0.1;
                    float particleY = position.y + cos(params.time * 6.0 + params.frequency * 25.0) * 0.1;
                    float particleDist = length(float2(particleX, particleY));
                    particleEffect = exp(-particleDist * 20.0) * audioMod * 0.3;
                }
                
                // Blend all color layers
                float3 baseColor = mix(color1, color2, complexity * 0.3);
                float3 finalColor = mix(baseColor, trapColor, trapInfluence * 0.4) * shimmer * dynamicNoise;
                
                // Add particle highlights
                float3 particleColor = float3(1.0, 0.8, 0.4) * particleEffect;
                finalColor += particleColor;
                
                return pow(finalColor, 1.0 / 2.2);
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
                
                // Increase iterations based on zoom and bass energy
                int baseIterations = 256;
                float zoomFactor = log10(max(2.0 / params.zoomLevel, 1.0));
                int maxIterations = int(baseIterations + zoomFactor * 100.0 + audioMod * 50.0 + params.bassEnergy * 100.0);
                
                float escape = 4.0;
                
                // Orbit trap variables
                float minTrapDistance = 1000.0;
                float trapRadius = 0.5 + audioMod * 0.3;
                
                for (int i = 0; i < 1024; i++) {
                    if (i >= maxIterations) break;
                    
                    // Calculate orbit traps during iteration
                    float circDist = circularTrap(z, trapRadius);
                    float lineDist = lineTrap(z);
                    float crossDist = crossTrap(z);
                    float spiralDist = spiralTrap(z, params.time);
                    
                    // Choose trap based on audio frequency
                    float trapDist;
                    if (params.frequency < 0.25) {
                        trapDist = circDist;
                    } else if (params.frequency < 0.5) {
                        trapDist = lineDist;
                    } else if (params.frequency < 0.75) {
                        trapDist = crossDist;
                    } else {
                        trapDist = spiralDist;
                    }
                    
                    minTrapDistance = min(minTrapDistance, trapDist);
                    
                    float x = z.x * z.x - z.y * z.y + c.x;
                    float y = 2.0 * z.x * z.y + c.y;
                    
                    z = float2(x, y);
                    
                    if (length(z) > escape) {
                        break;
                    }
                    iterations++;
                }
                
                float value = float(iterations) / float(maxIterations);
                float complexity = calculateComplexity(z, iterations, maxIterations);
                
                // Enhanced multi-layer coloring with orbit trap
                float3 color = getEnhancedColor(value, complexity, params, c, minTrapDistance);
                
                output.write(float4(color, 1.0), gid);
            }
            
            // Julia Set shader for background layer
            kernel void juliaShader(texture2d<float, access::write> output [[texture(0)]],
                                   constant MandelbrotParams& params [[buffer(0)]],
                                   uint2 gid [[thread_position_in_grid]]) {
                if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
                    return;
                }
                
                float2 resolution = float2(params.width, params.height);
                float2 uv = (float2(gid) - 0.5 * resolution) / min(resolution.x, resolution.y);
                
                float audioMod = params.amplitude * 0.5 + 0.5;
                
                // Julia set calculation
                float2 z = uv * (params.zoomLevel * 0.5);
                float2 c = float2(params.juliaReal, params.juliaImag);
                
                int iterations = 0;
                int maxIterations = 128;
                
                // Orbit trap for Julia set
                float minTrapDistance = 1000.0;
                float trapRadius = 0.3 + audioMod * 0.2;
                
                for (int i = 0; i < maxIterations; i++) {
                    // Calculate orbit trap
                    float trapDist = circularTrap(z, trapRadius);
                    minTrapDistance = min(minTrapDistance, trapDist);
                    
                    float x = z.x * z.x - z.y * z.y + c.x;
                    float y = 2.0 * z.x * z.y + c.y;
                    z = float2(x, y);
                    
                    if (length(z) > 2.0) {
                        break;
                    }
                    iterations++;
                }
                
                float value = float(iterations) / float(maxIterations);
                float trapInfluence = 1.0 / (1.0 + minTrapDistance * 8.0);
                
                // Enhanced ethereal colors with interior detail
                float hue = value * 240.0 + params.time * 10.0 + params.frequency * 50.0 + trapInfluence * 60.0;
                float brightness = 0.2 + value * 0.4 + trapInfluence * 0.3;
                
                // Add subtle noise pattern
                float noise = sin(uv.x * 30.0 + params.time * 2.0) * cos(uv.y * 25.0 - params.time * 1.5) * 0.05 + 0.95;
                
                float3 juliaColor = hsv2rgb(float3(hue / 360.0, 0.3 + audioMod * 0.2 + trapInfluence * 0.2, brightness)) * noise;
                
                output.write(float4(juliaColor * 0.5, 0.5), gid);
            }
            
            // Composite shader for blending layers
            kernel void compositeShader(texture2d<float, access::read> mandelbrotTex [[texture(0)]],
                                      texture2d<float, access::read> juliaTex [[texture(1)]],
                                      texture2d<float, access::write> output [[texture(2)]],
                                      constant MandelbrotParams& params [[buffer(0)]],
                                      uint2 gid [[thread_position_in_grid]]) {
                if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
                    return;
                }
                
                float4 mandelbrotColor = mandelbrotTex.read(gid);
                float4 juliaColor = juliaTex.read(gid);
                
                // Dynamic blending based on zoom and audio
                float audioMod = params.amplitude * 0.5 + 0.5;
                float zoomFactor = log10(max(2.0 / params.zoomLevel, 1.0)) / 15.0;
                float blendFactor = params.layerMix * (0.3 + zoomFactor * 0.4 + audioMod * 0.3);
                
                // Enhanced blending with depth
                float3 finalColor = mix(juliaColor.rgb, mandelbrotColor.rgb, 1.0 - blendFactor);
                
                // Add depth-based brightness adjustment
                finalColor *= 1.0 + zoomFactor * 0.5;
                
                output.write(float4(finalColor, 1.0), gid);
            }
            """
            
            do {
                let library = try device.makeLibrary(source: metalCode, options: nil)
                
                // Create Mandelbrot shader
                guard let mandelbrotFunction = library.makeFunction(name: "mandelbrotShader") else {
                    print("Failed to find mandelbrotShader function")
                    return
                }
                pipelineState = try device.makeComputePipelineState(function: mandelbrotFunction)
                
                // Create Julia Set shader
                guard let juliaFunction = library.makeFunction(name: "juliaShader") else {
                    print("Failed to find juliaShader function")
                    return
                }
                juliaSetPipelineState = try device.makeComputePipelineState(function: juliaFunction)
                
                // Create Composite shader
                guard let compositeFunction = library.makeFunction(name: "compositeShader") else {
                    print("Failed to find compositeShader function")
                    return
                }
                compositePipelineState = try device.makeComputePipelineState(function: compositeFunction)
                
                isMetalSetup = true
                print("Multi-layer Metal pipeline created successfully")
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
    var juliaReal: Float
    var juliaImag: Float
    var layerMix: Float
    var complexity: Float
    var bassEnergy: Float
    var midEnergy: Float
    var highEnergy: Float
    var spectrum0: Float
    var spectrum1: Float
    var spectrum2: Float
    var spectrum3: Float
    var spectrum4: Float
    var spectrum5: Float
    var spectrum6: Float
    var spectrum7: Float
}

// Safe array access extension
extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}