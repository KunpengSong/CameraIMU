import AVKit
import SwiftUI

struct RecordingsListView: View {
    @ObservedObject var viewModel: RecordingViewModel
    @State private var selectedRecording: Recording?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            ZStack {
                // Adaptive background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if viewModel.recordings.isEmpty {
                    emptyState
                } else {
                    recordingsList
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.large)
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
            .sheet(item: $selectedRecording) { recording in
                VideoPlayerView(url: recording.videoURL)
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
            LazyVStack(spacing: 12) {
                ForEach(viewModel.recordings) { recording in
                    RecordingCard(recording: recording) {
                        selectedRecording = recording
                    } onDelete: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.deleteRecording(recording)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Recording Card

struct RecordingCard: View {
    let recording: Recording
    var onTap: () -> Void
    var onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showDeleteConfirm = false

    var body: some View {
        Button(action: onTap) {
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

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
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
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }

            ShareLink(
                item: recording.csvURL,
                subject: Text("IMU Data"),
                message: Text("IMU recording data")
            ) {
                Label("Share CSV", systemImage: "square.and.arrow.up")
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
