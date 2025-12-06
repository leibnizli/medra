//
//  AudioWaveformView.swift
//  medra
//
//  Waveform visualization with segment display and zoom
//

import SwiftUI

struct AudioWaveformView: View {
    // Waveform data (normalized 0-1)
    let samples: [Float]
    
    // Time properties
    @Binding var currentTime: Double
    let duration: Double
    
    // Segments for visualization (kept segments)
    let segments: [AudioSegment]
    
    // Callbacks
    var onSeek: ((Double) -> Void)?
    var onSegmentTap: ((AudioSegment) -> Void)?
    
    // Zoom state
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    
    // Internal state
    @State private var isDraggingPlayhead = false
    
    // Colors
    private let activeWaveformColor = Color.blue
    private let deletedWaveformColor = Color.red.opacity(0.5)
    private let playheadColor = Color.green
    private let segmentBorderColor = Color.orange
    
    // Zoom limits
    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 10.0
    
    var body: some View {
        VStack(spacing: 8) {
            // Zoom controls
            HStack {
                Button(action: { zoomOut() }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.title3)
                }
                .disabled(zoomScale <= minZoom)
                
                Text("\(Int(zoomScale * 100))%")
                    .font(.caption)
                    .frame(width: 50)
                
                Button(action: { zoomIn() }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.title3)
                }
                .disabled(zoomScale >= maxZoom)
                
                Spacer()
                
                Button(action: { resetZoom() }) {
                    Text("Reset")
                        .font(.caption)
                }
                .disabled(zoomScale == 1.0)
            }
            .padding(.horizontal)
            
            // Waveform with scroll and zoom
            GeometryReader { geometry in
                let viewWidth = geometry.size.width
                let contentWidth = viewWidth * zoomScale
                let height = geometry.size.height
                
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .leading) {
                        // Background
                        Rectangle()
                            .fill(Color(uiColor: .systemGray6))
                            .frame(width: contentWidth, height: height)
                        
                        // Waveform
                        Canvas { context, size in
                            drawWaveform(context: context, size: size, contentWidth: contentWidth)
                        }
                        .frame(width: contentWidth, height: height)
                        
                        // Segment borders (show split points)
                        ForEach(segments.dropFirst()) { segment in
                            let xPos = timeToX(segment.startTime, width: contentWidth)
                            Rectangle()
                                .fill(segmentBorderColor)
                                .frame(width: 2, height: height)
                                .position(x: xPos, y: height / 2)
                        }
                        
                        // Selected segment indicators (top and bottom lines)
                        ForEach(segments.filter { $0.isSelected }) { segment in
                            let startX = timeToX(segment.startTime, width: contentWidth)
                            let endX = timeToX(segment.endTime, width: contentWidth)
                            let segmentWidth = endX - startX
                            
                            // Top line (blue)
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: segmentWidth, height: 3)
                                .position(x: startX + segmentWidth / 2, y: 1.5)
                            
                            // Bottom line (blue)
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: segmentWidth, height: 3)
                                .position(x: startX + segmentWidth / 2, y: height - 1.5)
                        }
                        
                        // Playhead
                        playhead(at: timeToX(currentTime, width: contentWidth), height: height)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        isDraggingPlayhead = true
                                        let newTime = xToTime(value.location.x, width: contentWidth)
                                        currentTime = max(0, min(newTime, duration))
                                        onSeek?(currentTime)
                                    }
                                    .onEnded { _ in
                                        isDraggingPlayhead = false
                                    }
                            )
                    }
                    .frame(width: contentWidth, height: height)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        // Tap to seek only (don't toggle segment selection)
                        let tappedTime = xToTime(location.x, width: contentWidth)
                        currentTime = max(0, min(tappedTime, duration))
                        onSeek?(currentTime)
                    }
                }
                .clipShape(Rectangle())
                // Pinch to zoom gesture
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let newScale = lastZoomScale * value
                            zoomScale = min(maxZoom, max(minZoom, newScale))
                        }
                        .onEnded { value in
                            lastZoomScale = zoomScale
                        }
                )
            }
            .frame(height: 120)
        }
    }
    
    // MARK: - Zoom Functions
    
    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = min(maxZoom, zoomScale * 1.5)
            lastZoomScale = zoomScale
        }
    }
    
    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = max(minZoom, zoomScale / 1.5)
            lastZoomScale = zoomScale
        }
    }
    
    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = 1.0
            lastZoomScale = 1.0
        }
    }
    
    // MARK: - Drawing
    
    private func drawWaveform(context: GraphicsContext, size: CGSize, contentWidth: CGFloat) {
        guard !samples.isEmpty, duration > 0, contentWidth > 0 else { return }
        
        let totalBars = samples.count
        let spacing: CGFloat = 1
        let barWidth = max(1, (contentWidth - CGFloat(totalBars - 1) * spacing) / CGFloat(totalBars))
        let centerY = size.height / 2
        
        // Track deleted regions for strikethrough line
        var deletedRegions: [(startX: CGFloat, endX: CGFloat)] = []
        var currentDeletedStart: CGFloat? = nil
        
        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * (barWidth + spacing)
            let barCenterX = x + barWidth / 2
            let sampleTime = (Double(barCenterX) / Double(contentWidth)) * duration
            
            // Check if this sample time is within ANY segment (not deleted)
            let isInAnySegment = segments.contains { segment in
                sampleTime >= segment.startTime && sampleTime <= segment.endTime
            }
            
            // Color: blue for active segments, red for deleted
            let color: Color
            if !isInAnySegment {
                color = deletedWaveformColor
                if currentDeletedStart == nil {
                    currentDeletedStart = x
                }
            } else {
                color = activeWaveformColor
                if let startX = currentDeletedStart {
                    deletedRegions.append((startX: startX, endX: x))
                    currentDeletedStart = nil
                }
            }
            
            let barHeight = max(2, CGFloat(sample) * (size.height - 10))
            let rect = CGRect(
                x: x,
                y: centerY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )
            
            context.fill(
                RoundedRectangle(cornerRadius: 1).path(in: rect),
                with: .color(color)
            )
        }
        
        // Close any final deleted region
        if let startX = currentDeletedStart {
            let endX = CGFloat(totalBars) * (barWidth + spacing)
            deletedRegions.append((startX: startX, endX: endX))
        }
        
        // Draw strikethrough lines for deleted regions
        for region in deletedRegions {
            let lineRect = CGRect(
                x: region.startX,
                y: centerY - 1,
                width: region.endX - region.startX,
                height: 2
            )
            context.fill(
                Rectangle().path(in: lineRect),
                with: .color(Color.red)
            )
        }
    }
    
    // MARK: - UI Components
    
    private func playhead(at x: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Vertical line
            Rectangle()
                .fill(playheadColor)
                .frame(width: 2, height: height)
            
            // Top triangle
            Triangle()
                .fill(playheadColor)
                .frame(width: 14, height: 10)
                .rotationEffect(.degrees(180))
                .offset(y: -height / 2 + 5)
            
            // Bottom triangle
            Triangle()
                .fill(playheadColor)
                .frame(width: 14, height: 10)
                .offset(y: height / 2 - 5)
        }
        .position(x: x, y: height / 2)
    }
    
    // MARK: - Coordinate Conversion
    
    private func timeToX(_ time: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }
    
    private func xToTime(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(x / width) * duration
    }
}

// MARK: - Triangle Shape

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview {
    AudioWaveformView(
        samples: (0..<100).map { _ in Float.random(in: 0.1...1.0) },
        currentTime: .constant(5.0),
        duration: 10.0,
        segments: [
            AudioSegment(startTime: 0, endTime: 4),
            AudioSegment(startTime: 6, endTime: 10)
        ],
        onSeek: { _ in },
        onSegmentTap: { _ in }
    )
    .padding()
}
