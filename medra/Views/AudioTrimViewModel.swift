//
//  AudioTrimViewModel.swift
//  medra
//
//  ViewModel for audio editing operations
//

import Foundation
import AVFoundation
import SwiftUI
import Combine
import ffmpegkit

@MainActor
class AudioTrimViewModel: ObservableObject {
    // MARK: - Published Properties
    
    // Audio file info
    @Published var audioURL: URL?
    @Published var duration: Double = 0
    @Published var sampleRate: Int = 44100
    @Published var channels: Int = 2
    
    // Waveform data (normalized amplitude values 0-1)
    @Published var waveformSamples: [Float] = []
    @Published var isLoadingWaveform: Bool = false
    
    // Selection range
    @Published var selectionStart: Double = 0
    @Published var selectionEnd: Double = 0
    
    // Segments (for split/delete/merge operations)
    @Published var segments: [AudioSegment] = []
    
    // Playback state
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    
    // Export state
    @Published var isExporting: Bool = false
    @Published var exportProgress: Float = 0
    @Published var outputFormat: AudioFormat {
        didSet {
            UserDefaults.standard.set(outputFormat.rawValue, forKey: "audioTrimOutputFormat")
        }
    }
    @Published var exportedFileURL: URL?
    
    // Error handling
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    
    // MARK: - Private Properties
    
    private var player: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var editHistory: [AudioEditAction] = []
    private let waveformSampleCount = 200 // Number of samples to display
    
    // MARK: - Initialization
    
    init() {
        // Load saved output format
        if let savedFormat = UserDefaults.standard.string(forKey: "audioTrimOutputFormat"),
           let format = AudioFormat(rawValue: savedFormat) {
            self.outputFormat = format
        } else {
            self.outputFormat = .m4a
        }
    }
    
    init(audioURL: URL) {
        // Load saved output format
        if let savedFormat = UserDefaults.standard.string(forKey: "audioTrimOutputFormat"),
           let format = AudioFormat(rawValue: savedFormat) {
            self.outputFormat = format
        } else {
            self.outputFormat = .m4a
        }
        self.audioURL = audioURL
    }
    
    // MARK: - Audio Loading
    
    func loadAudio(from url: URL) async {
        audioURL = url
        isLoadingWaveform = true
        errorMessage = nil
        
        do {
            // Load audio metadata
            let asset = AVURLAsset(url: url)
            let durationCMTime = try await asset.load(.duration)
            duration = CMTimeGetSeconds(durationCMTime)
            
            // Get audio track info
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            if let audioTrack = tracks.first {
                let formatDescriptions = audioTrack.formatDescriptions as! [CMFormatDescription]
                if let formatDescription = formatDescriptions.first {
                    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
                        sampleRate = Int(asbd.pointee.mSampleRate)
                        channels = Int(asbd.pointee.mChannelsPerFrame)
                    }
                }
            }
            
            // Set initial selection to full audio
            selectionStart = 0
            selectionEnd = duration
            
            // Create initial segment
            segments = [AudioSegment(startTime: 0, endTime: duration)]
            
            // Extract waveform
            await extractWaveformData()
            
            print("✅ [AudioTrim] Audio loaded: duration=\(duration)s, sampleRate=\(sampleRate)Hz, channels=\(channels)")
            
        } catch {
            errorMessage = "Failed to load audio: \(error.localizedDescription)"
            showError = true
            print("❌ [AudioTrim] Failed to load audio: \(error)")
        }
        
        isLoadingWaveform = false
    }
    
    // MARK: - Waveform Extraction
    
    private func extractWaveformData() async {
        guard let url = audioURL else { return }
        
        do {
            let asset = AVURLAsset(url: url)
            let reader = try AVAssetReader(asset: asset)
            
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                print("❌ [AudioTrim] No audio track found")
                return
            }
            
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            reader.add(output)
            reader.startReading()
            
            var allSamples: [Int16] = []
            
            while let sampleBuffer = output.copyNextSampleBuffer() {
                if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                    let length = CMBlockBufferGetDataLength(blockBuffer)
                    var data = Data(count: length)
                    data.withUnsafeMutableBytes { ptr in
                        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
                    }
                    
                    // Convert bytes to Int16 samples
                    let samples = data.withUnsafeBytes { ptr in
                        Array(ptr.bindMemory(to: Int16.self))
                    }
                    allSamples.append(contentsOf: samples)
                }
            }
            
            // Downsample to target sample count
            let samplesPerPoint = max(1, allSamples.count / waveformSampleCount)
            var waveform: [Float] = []
            
            for i in 0..<waveformSampleCount {
                let startIndex = i * samplesPerPoint
                let endIndex = min(startIndex + samplesPerPoint, allSamples.count)
                
                if startIndex < allSamples.count {
                    // Calculate RMS for this chunk
                    var sum: Float = 0
                    for j in startIndex..<endIndex {
                        let sample = Float(allSamples[j]) / Float(Int16.max)
                        sum += sample * sample
                    }
                    let rms = sqrt(sum / Float(endIndex - startIndex))
                    waveform.append(rms)
                }
            }
            
            // Normalize waveform
            if let maxValue = waveform.max(), maxValue > 0 {
                waveform = waveform.map { $0 / maxValue }
            }
            
            waveformSamples = waveform
            print("✅ [AudioTrim] Waveform extracted: \(waveformSamples.count) samples")
            
        } catch {
            print("❌ [AudioTrim] Failed to extract waveform: \(error)")
        }
    }
    
    // MARK: - Playback Control
    
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func play() {
        guard let url = audioURL else { return }
        
        do {
            // Configure audio session
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.currentTime = currentTime
            player?.play()
            isPlaying = true
            
            startPlaybackTimer()
            print("▶️ [AudioTrim] Playing from \(currentTime)s")
            
        } catch {
            print("❌ [AudioTrim] Playback failed: \(error)")
            errorMessage = "Playback failed: \(error.localizedDescription)"
            showError = true
        }
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        stopPlaybackTimer()
        print("⏸️ [AudioTrim] Paused at \(currentTime)s")
    }
    
    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = selectionStart
        stopPlaybackTimer()
    }
    
    func seek(to time: Double) {
        currentTime = max(0, min(time, duration))
        player?.currentTime = currentTime
    }
    
    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.player else { return }
                self.currentTime = player.currentTime
                
                // Stop at end of audio
                if self.currentTime >= self.duration {
                    self.pause()
                    self.currentTime = 0
                }
            }
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    // MARK: - Edit Operations
    
    /// Split the audio at the current playhead position
    func splitAtCurrentPosition() {
        guard currentTime > selectionStart && currentTime < selectionEnd else {
            errorMessage = "Cannot split: playhead must be within selection"
            showError = true
            return
        }
        
        // Find the segment that contains the current time
        guard let index = segments.firstIndex(where: { $0.contains(time: currentTime) }) else {
            return
        }
        
        let segment = segments[index]
        
        // Create two new segments
        let segment1 = AudioSegment(startTime: segment.startTime, endTime: currentTime)
        let segment2 = AudioSegment(startTime: currentTime, endTime: segment.endTime)
        
        // Replace the original segment
        segments.remove(at: index)
        segments.insert(segment1, at: index)
        segments.insert(segment2, at: index + 1)
        
        // Record action for undo
        editHistory.append(AudioEditAction(type: .split(segmentId: segment.id, splitTime: currentTime)))
        
        print("✂️ [AudioTrim] Split at \(formatTime(currentTime))")
    }
    
    /// Delete selected segments
    func deleteSelectedSegments() {
        let selectedSegments = segments.filter { $0.isSelected }
        guard !selectedSegments.isEmpty else {
            errorMessage = "No segments selected"
            showError = true
            return
        }
        
        // Record for undo
        editHistory.append(AudioEditAction(type: .delete(segments: selectedSegments)))
        
        // Remove selected segments
        segments.removeAll { $0.isSelected }
        
        // Update selection range
        updateSelectionFromSegments()
        
        print("🗑️ [AudioTrim] Deleted \(selectedSegments.count) segment(s)")
    }
    
    /// Merge selected segments (must be adjacent)
    func mergeSelectedSegments() {
        let selectedSegments = segments.filter { $0.isSelected }.sorted { $0.startTime < $1.startTime }
        guard selectedSegments.count >= 2 else {
            errorMessage = "Select at least 2 segments to merge"
            showError = true
            return
        }
        
        // Check if segments are adjacent
        for i in 0..<(selectedSegments.count - 1) {
            if abs(selectedSegments[i].endTime - selectedSegments[i + 1].startTime) > 0.001 {
                errorMessage = "Segments must be adjacent to merge"
                showError = true
                return
            }
        }
        
        // Create merged segment
        let mergedSegment = AudioSegment(
            startTime: selectedSegments.first!.startTime,
            endTime: selectedSegments.last!.endTime
        )
        
        // Record for undo
        editHistory.append(AudioEditAction(type: .merge(segments: selectedSegments, resultSegment: mergedSegment)))
        
        // Remove selected segments and insert merged one
        guard let firstIndex = segments.firstIndex(where: { $0.id == selectedSegments.first!.id }) else { return }
        
        for segment in selectedSegments {
            segments.removeAll { $0.id == segment.id }
        }
        segments.insert(mergedSegment, at: firstIndex)
        
        print("🔗 [AudioTrim] Merged \(selectedSegments.count) segments")
    }
    
    /// Toggle selection state of a segment
    func toggleSegmentSelection(_ segment: AudioSegment) {
        if let index = segments.firstIndex(where: { $0.id == segment.id }) {
            segments[index].isSelected.toggle()
        }
    }
    
    /// Select all segments
    func selectAllSegments() {
        for i in 0..<segments.count {
            segments[i].isSelected = true
        }
    }
    
    /// Deselect all segments
    func deselectAllSegments() {
        for i in 0..<segments.count {
            segments[i].isSelected = false
        }
    }
    
    private func updateSelectionFromSegments() {
        if let firstSegment = segments.first, let lastSegment = segments.last {
            selectionStart = firstSegment.startTime
            selectionEnd = lastSegment.endTime
        }
    }
    
    // MARK: - Export
    
    func exportAudio() async {
        guard let sourceURL = audioURL else { return }
        guard !segments.isEmpty else {
            errorMessage = "No segments to export"
            showError = true
            return
        }
        
        isExporting = true
        exportProgress = 0
        
        do {
            let exportedURL = try await performExport(from: sourceURL)
            exportedFileURL = exportedURL
            
            // Verify exported file duration
            let asset = AVURLAsset(url: exportedURL)
            let durationCMTime = try await asset.load(.duration)
            let exportedDuration = CMTimeGetSeconds(durationCMTime)
            let expectedDuration = segments.reduce(0) { $0 + $1.duration }
            print("✅ [AudioTrim] Export completed: \(exportedURL.path)")
            print("📊 [AudioTrim] Exported file duration: \(formatTime(exportedDuration)) (expected: \(formatTime(expectedDuration)))")
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
            showError = true
            print("❌ [AudioTrim] Export failed: \(error)")
        }
        
        isExporting = false
    }
    
    private func performExport(from sourceURL: URL) async throws -> URL {
        let outputExtension = outputFormat.fileExtension
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("trimmed_\(UUID().uuidString)")
            .appendingPathExtension(outputExtension)
        
        // Debug: Log segments being exported
        print("📤 [AudioTrim] Exporting \(segments.count) segment(s):")
        for (index, segment) in segments.enumerated() {
            print("   Segment \(index + 1): \(formatTime(segment.startTime)) - \(formatTime(segment.endTime)) (duration: \(formatTime(segment.duration)))")
        }
        
        // Build FFmpeg filter complex for segments
        var filterParts: [String] = []
        
        for (index, segment) in segments.enumerated() {
            let startTime = formatTimeForFFmpeg(segment.startTime)
            let endTime = formatTimeForFFmpeg(segment.endTime)
            filterParts.append("[0:a]atrim=start=\(startTime):end=\(endTime),asetpts=PTS-STARTPTS[a\(index)]")
        }
        
        // Concat all segments
        let concatInputs = (0..<segments.count).map { "[a\($0)]" }.joined()
        let filterComplex: String
        
        if segments.count > 1 {
            filterComplex = filterParts.joined(separator: ";") + ";\(concatInputs)concat=n=\(segments.count):v=0:a=1[out]"
        } else {
            filterComplex = filterParts[0].replacingOccurrences(of: "[a0]", with: "[out]")
        }
        
        // Build encoder options
        var encoderOptions = ""
        switch outputFormat {
        case .original:
            encoderOptions = "-c:a copy"
        case .mp3:
            encoderOptions = "-c:a libmp3lame -b:a 192k -q:a 2"
        case .m4a:
            encoderOptions = "-c:a aac -b:a 192k"
        case .flac:
            encoderOptions = "-c:a flac -compression_level 8"
        case .wav:
            encoderOptions = "-c:a pcm_s16le"
        case .webm:
            encoderOptions = "-c:a libopus -b:a 128k -vbr on"
        }
        
        let command = "-i \"\(sourceURL.path)\" -filter_complex \"\(filterComplex)\" -map \"[out]\" \(encoderOptions) -vn \"\(outputURL.path)\""
        
        print("🎬 [AudioTrim] FFmpeg command: ffmpeg \(command)")
        
        return try await withCheckedThrowingContinuation { continuation in
            FFmpegKit.executeAsync(command, withCompleteCallback: { session in
                guard let session = session else {
                    continuation.resume(throwing: NSError(domain: "FFmpeg", code: -1, userInfo: [NSLocalizedDescriptionKey: "Session creation failed"]))
                    return
                }
                
                let returnCode = session.getReturnCode()
                if ReturnCode.isSuccess(returnCode) {
                    continuation.resume(returning: outputURL)
                } else {
                    let errorLog = session.getOutput() ?? "Unknown error"
                    continuation.resume(throwing: NSError(domain: "FFmpeg", code: Int(returnCode?.getValue() ?? -1), userInfo: [NSLocalizedDescriptionKey: errorLog]))
                }
            }, withLogCallback: { log in
                // Log callback
            }, withStatisticsCallback: { [weak self] statistics in
                guard let statistics = statistics, let self = self else { return }
                let time = Double(statistics.getTime()) / 1000.0
                let totalDuration = self.segments.reduce(0) { $0 + $1.duration }
                if totalDuration > 0 {
                    let progress = Float(time / totalDuration)
                    Task { @MainActor in
                        self.exportProgress = min(progress, 0.99)
                    }
                }
            })
        }
    }
    
    // MARK: - Helper Functions
    
    func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", mins, secs, ms)
    }
    
    private func formatTimeForFFmpeg(_ seconds: Double) -> String {
        // Use pure seconds format for more accurate trimming
        return String(format: "%.3f", seconds)
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        stop()
        waveformSamples = []
        segments = []
        editHistory = []
    }
}
