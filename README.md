# Maderu - Mandelbrot Audio Visualizer

Real-time Mandelbrot set visualization that responds to audio input using Metal on macOS.

## Features

- **Real-time Mandelbrot Set Rendering**: High-performance fractal rendering using Metal compute shaders
- **Audio-Reactive Visualization**: Visualizer responds to microphone input amplitude and frequency
- **FFT Analysis**: Real-time frequency analysis using vDSP framework
- **60 FPS Performance**: Smooth animation with Metal optimization

## Requirements

- macOS 11.0+
- Xcode 14.0+
- Metal-capable Mac

## Setup

1. Clone the repository
2. Open `maderu.xcodeproj` in Xcode
3. Allow microphone access when prompted
4. Build and run (⌘R)

## Usage

- Click the play button to start audio capture
- The Mandelbrot visualization will respond to sound input
- Louder sounds create more dramatic zoom and color effects
- Different frequencies affect the movement patterns

## Technical Stack

- **SwiftUI** for the user interface
- **Metal** for GPU-accelerated fractal computation
- **AVFoundation** for audio capture
- **Accelerate/vDSP** for FFT processing

## License

MIT
