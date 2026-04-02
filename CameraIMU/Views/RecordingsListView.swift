import AVKit
import SwiftUI

struct RecordingsListView: View {
    @ObservedObject var viewModel: RecordingViewModel
    @State private var selectedRecording: Recording?
    @State private var selectedIDs: Set<UUID> = []
    @State private var isSelecting = false
    @State private var showShareSheet = false
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var allSelected: Bool {
        !viewModel.recordings.isEmpty && selectedIDs.count == viewModel.recordings.count
    }

    private var shareURLs: [URL] {
        viewModel.recordings
            .filter { selectedIDs.contains($0.id) }
            .flatMap { [$0.videoURL, $0.csvURL] }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Upload progress banner
                    if let status = viewModel.uploadStatus {
                        HStack(spacing: 10) {
                            if viewModel.isUploading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: status.contains("uploaded") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(status.contains("uploaded") ? .green : .orange)
                            }
                            Text(status)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemBackground).opacity(0.95))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if viewModel.recordings.isEmpty {
                        emptyState
                    } else {
                        recordingsList
                    }
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !viewModel.recordings.isEmpty {
                        Button(isSelecting ? "Done" : "Select") {
                            withAnimation {
                                isSelecting.toggle()
                                if !isSelecting { selectedIDs.removeAll() }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    selectionToolbar
                }
            }
            .sheet(item: $selectedRecording) { recording in
                VideoPlayerView(url: recording.videoURL)
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityView(activityItems: shareURLs)
            }
            .confirmationDialog(
                "Delete \(selectedIDs.count) recording\(selectedIDs.count == 1 ? "" : "s")?",
                isPresented: $showDeleteConfirm
            ) {
                Button("Delete", role: .destructive) {
                    withAnimation {
                        for id in selectedIDs {
                            if let rec = viewModel.recordings.first(where: { $0.id == id }) {
                                viewModel.deleteRecording(rec)
                            }
                        }
                        selectedIDs.removeAll()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the selected video and IMU data files.")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No Recordings")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Start recording to capture\nvideo and IMU data")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Recordings List

    private var recordingsList: some View {
        ScrollView {
            // Select All row
            if isSelecting {
                Button {
                    withAnimation {
                        if allSelected {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = Set(viewModel.recordings.map(\.id))
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(allSelected ? .blue : .secondary)
                        Text("Select All")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }

            LazyVStack(spacing: 12) {
                ForEach(viewModel.recordings) { recording in
                    let isSelected = selectedIDs.contains(recording.id)

                    HStack(spacing: 12) {
                        if isSelecting {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(isSelected ? .blue : .secondary)
                                .transition(.scale.combined(with: .opacity))
                        }

                        RecordingCard(recording: recording, isSelecting: isSelecting) {
                            if isSelecting {
                                toggleSelection(recording.id)
                            } else {
                                selectedRecording = recording
                            }
                        } onDelete: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                viewModel.deleteRecording(recording)
                            }
                        } onShare: {
                            showShareSheet = false
                            selectedIDs = [recording.id]
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showShareSheet = true
                            }
                        } onUpload: {
                            viewModel.uploadRecordings([recording])
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelecting {
                            toggleSelection(recording.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            // Extra space for bottom toolbar
            if isSelecting {
                Spacer().frame(height: 70)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelecting)
    }

    // MARK: - Selection Toolbar

    private var selectionToolbar: some View {
        HStack(spacing: 0) {
            Button {
                guard !selectedIDs.isEmpty else { return }
                let items = viewModel.recordings.filter { selectedIDs.contains($0.id) }
                viewModel.uploadRecordings(items)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 20))
                    Text("Upload")
                        .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedIDs.isEmpty || viewModel.isUploading)

            Button {
                guard !selectedIDs.isEmpty else { return }
                showShareSheet = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20))
                    Text("Share")
                        .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedIDs.isEmpty)

            Button(role: .destructive) {
                guard !selectedIDs.isEmpty else { return }
                showDeleteConfirm = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 20))
                    Text("Delete")
                        .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(selectedIDs.isEmpty ? .gray : .red)
            }
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func toggleSelection(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        }
    }
}

// MARK: - Recording Card

struct RecordingCard: View {
    let recording: Recording
    var isSelecting: Bool = false
    var onTap: () -> Void
    var onDelete: () -> Void
    var onShare: () -> Void
    var onUpload: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var showDeleteConfirm = false

    var body: some View {
        Button(action: { if !isSelecting { onTap() } }) {
            HStack(spacing: 14) {
                // Thumbnail / Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colorScheme == .dark
                              ? Color.white.opacity(0.08)
                              : Color.black.opacity(0.05))
                        .frame(width: 56, height: 56)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.tint)
                }

                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(recording.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 14) {
                        Label(recording.videoFileSize, systemImage: "video.fill")
                        Label(recording.csvFileSize, systemImage: "chart.bar.doc.horizontal")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if !isSelecting {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .shadow(
                color: colorScheme == .dark ? .clear : .black.opacity(0.04),
                radius: 8, y: 2
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isSelecting {
                if let onUpload = onUpload {
                    Button {
                        onUpload()
                    } label: {
                        Label("Upload to Cloud", systemImage: "icloud.and.arrow.up")
                    }
                }

                Button {
                    onShare()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Delete this recording?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the video and IMU data.")
        }
    }
}

// MARK: - UIActivityViewController wrapper

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Video Player

struct VideoPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
        }
    }
}
