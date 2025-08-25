import SwiftUI
import MetalKit
import Metal

struct MandelbrotView: NSViewRepresentable {
    @ObservedObject var audioManager: AudioManager
    
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
            
            commandEncoder.setComputePipelineState(pipelineState)
            commandEncoder.setTexture(drawable.texture, index: 0)
            
            var params = MandelbrotParams(
                width: Float(drawable.texture.width),
                height: Float(drawable.texture.height),
                amplitude: amplitude,
                frequency: frequency,
                time: time
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
                float freqMod = params.frequency * 0.1;
                
                float zoom = 2.0 + sin(params.time * 0.5 + freqMod) * audioMod;
                float2 c = uv * zoom;
                
                c.x += cos(params.time * 0.3 + params.frequency * 10.0) * audioMod * 0.5;
                c.y += sin(params.time * 0.2 + params.frequency * 5.0) * audioMod * 0.5;
                
                float2 z = float2(0.0, 0.0);
                int iterations = 0;
                int maxIterations = int(100.0 + audioMod * 150.0);
                
                float escape = 4.0 + audioMod * 2.0;
                
                for (int i = 0; i < 256; i++) {
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
                
                float hue = value * 360.0 + params.time * 30.0 + params.frequency * 100.0;
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
}