//
//  AudioTrimView.swift
//  medra
//
//  Audio trimming and editing interface
//

import SwiftUI
import UniformTypeIdentifiers

struct AudioTrimView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AudioTrimViewModel()
    
    @State private var showFileImporter = false
    @State private var showExportSheet = false
    @State private var showSaveSuccess = false
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.audioURL == nil {
                    // Empty state - prompt to select file
                    emptyStateView
                } else if viewModel.isLoadingWaveform {
                    // Loading state
                    loadingView
                } else {
                    // Main editing interface
                    editorView
                }
            }
            .navigationTitle("Audio Trim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        viewModel.cleanup()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.audioURL != nil && !viewModel.isExporting {
                        Button(action: { showExportSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .sheet(isPresented: $showExportSheet) {
                exportSheet
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = viewModel.exportedFileURL {
                    DocumentExporter(url: url) { success in
                        showShareSheet = false
                        if success {
                            showSaveSuccess = true
                        }
                    }
                }
            }
            .alert("Save Complete", isPresented: $showSaveSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Audio saved successfully")
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
            
            Text("Select an Audio File")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Choose an audio file to trim and edit")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button(action: { showFileImporter = true }) {
                HStack {
                    Image(systemName: "folder")
                    Text("Select File")
                }
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Loading State
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading audio...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Editor View
    
    private var editorView: some View {
        VStack(spacing: 0) {
            // Waveform
            waveformSection
            
            // Time display
            timeDisplaySection
            
            // Playback controls
            playbackControlsSection
            
            // Edit tools
            editToolsSection
            
            // Segment list
            segmentListSection
            Spacer()
        }
    }
    
    // MARK: - Waveform Section
    
    private var waveformSection: some View {
        VStack(spacing: 8) {
            AudioWaveformView(
                samples: viewModel.waveformSamples,
                currentTime: $viewModel.currentTime,
                duration: viewModel.duration,
                segments: viewModel.segments,
                onSeek: { time in
                    viewModel.seek(to: time)
                },
                onSegmentTap: { segment in
                    viewModel.toggleSegmentSelection(segment)
                }
            )
            .padding(.horizontal)
        }
        .padding(.vertical, 16)
        .background(Color(uiColor: .systemBackground))
    }
    
    // MARK: - Time Display
    
    private var timeDisplaySection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.formatTime(viewModel.duration))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            VStack {
                Text("Current")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.formatTime(viewModel.currentTime))
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text("Kept")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.formatTime(viewModel.segments.reduce(0) { $0 + $1.duration }))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground))
    }
    
    // MARK: - Playback Controls
    
    private var playbackControlsSection: some View {
        HStack(spacing: 32) {
            // Rewind to first segment start
            Button(action: {
                if let first = viewModel.segments.first {
                    viewModel.seek(to: first.startTime)
                }
            }) {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
            }
            
            // Skip backward 5s
            Button(action: {
                viewModel.seek(to: max(0, viewModel.currentTime - 5))
            }) {
                Image(systemName: "gobackward.5")
                    .font(.title2)
            }
            
            // Play/Pause
            Button(action: {
                viewModel.togglePlayback()
            }) {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
            }
            
            // Skip forward 5s
            Button(action: {
                viewModel.seek(to: min(viewModel.duration, viewModel.currentTime + 5))
            }) {
                Image(systemName: "goforward.5")
                    .font(.title2)
            }
            
            // Jump to last segment end
            Button(action: {
                if let last = viewModel.segments.last {
                    viewModel.seek(to: last.endTime)
                }
            }) {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
            }
        }
        .padding(.vertical, 16)
        .background(Color(uiColor: .systemBackground))
    }
    
    // MARK: - Edit Tools
    
    private var editToolsSection: some View {
        HStack(spacing: 16) {
            // Split button
            Button(action: {
                viewModel.splitAtCurrentPosition()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "scissors")
                        .font(.title2)
                    Text("Split")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.segments.count >= 10 || !viewModel.segments.contains { $0.contains(time: viewModel.currentTime) })
            
            // Merge button
            Button(action: {
                viewModel.mergeSelectedSegments()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.title2)
                    Text("Merge")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.segments.filter { $0.isSelected }.count < 2)
            
            // Delete button
            Button(action: {
                viewModel.deleteSelectedSegments()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.title2)
                    Text("Delete")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(!viewModel.segments.contains { $0.isSelected })
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground))
    }
    
    // MARK: - Segment List
    
    private var segmentListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Segments")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    if viewModel.segments.allSatisfy({ $0.isSelected }) {
                        viewModel.deselectAllSegments()
                    } else {
                        viewModel.selectAllSegments()
                    }
                }) {
                    Text(viewModel.segments.allSatisfy({ $0.isSelected }) ? "Deselect All" : "Select All")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.segments.enumerated()), id: \.element.id) { index, segment in
                        SegmentCard(
                            index: index + 1,
                            segment: segment,
                            formatTime: viewModel.formatTime
                        ) {
                            viewModel.toggleSegmentSelection(segment)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
    
    // MARK: - Export Sheet
    
    private var exportSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Format picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Output Format")
                        .font(.headline)
                    
                    Picker("Format", selection: $viewModel.outputFormat) {
                        ForEach(AudioFormat.allCases.filter { $0 != .original }, id: \.self) { format in
                            Text("\(format.rawValue) · \(format.description)")
                                .tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal)
                
                // Duration info
                HStack {
                    Text("Duration:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.formatTime(viewModel.segments.reduce(0) { $0 + $1.duration }))
                        .fontWeight(.medium)
                }
                .padding(.horizontal)
                
                // Segments count
                HStack {
                    Text("Segments:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.segments.count)")
                        .fontWeight(.medium)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Export button
                if viewModel.isExporting {
                    VStack(spacing: 8) {
                        ProgressView(value: viewModel.exportProgress)
                        Text("Exporting... \(Int(viewModel.exportProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                } else {
                    Button(action: {
                        Task {
                            await viewModel.exportAudio()
                            if viewModel.exportedFileURL != nil {
                                showExportSheet = false
                                // Small delay to allow sheet dismiss animation
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    showShareSheet = true
                                }
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Export Audio")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showExportSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Helper Functions
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                if url.startAccessingSecurityScopedResource() {
                    Task {
                        await viewModel.loadAudio(from: url)
                    }
                }
            }
        case .failure(let error):
            viewModel.errorMessage = "File selection failed: \(error.localizedDescription)"
            viewModel.showError = true
        }
    }
}

// MARK: - Segment Card

struct SegmentCard: View {
    let index: Int
    let segment: AudioSegment
    let formatTime: (Double) -> String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Segment \(index)")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    if segment.isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                
                Text(formatTime(segment.duration))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                Text("\(formatTime(segment.startTime)) - \(formatTime(segment.endTime))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(segment.isSelected ? Color.blue.opacity(0.15) : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(segment.isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Share Sheet

struct DocumentExporter: UIViewControllerRepresentable {
    let url: URL
    let onComplete: (Bool) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onComplete: (Bool) -> Void
        
        init(onComplete: @escaping (Bool) -> Void) {
            self.onComplete = onComplete
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onComplete(true)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete(false)
        }
    }
}

// MARK: - Preview

#Preview {
    AudioTrimView()
}
