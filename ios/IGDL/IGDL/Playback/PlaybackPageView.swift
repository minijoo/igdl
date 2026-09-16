import SwiftUI
import AVFoundation
import CoreMedia

private let postedDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter
}()

struct PlaybackPageView: View {
    let video: Video
    let player: AVPlayer?
    let isActive: Bool
    // Owned by PlaybackView, not local @State here — see PlaybackView's
    // categorizingVideo for why.
    let onCategorize: () -> Void

    @State private var isPaused = false
    @State private var isMuted = false
    // Set the instant a touch begins on the caption or scrubber, cleared
    // when it ends — always set well before the video area's own gesture
    // sees release for that same touch (touch-down on a child necessarily
    // precedes touch-up), so it reliably tells the video area's gesture
    // "this touch belongs to an overlay control, don't toggle pause / start
    // 2x for it" — needed because that gesture is .simultaneousGesture (see
    // videoArea), which by design doesn't respect the caption/scrubber's
    // own .highPriorityGesture at all; both just fire independently.
    @State private var isTouchingOverlay = false
    @State private var showingComments = false
    @State private var isCaptionExpanded = false
    @State private var comments: [Comment] = []

    // Scrubber state. currentTime/duration are updated from a periodic time
    // observer on `player`; while dragging, the displayed position follows
    // the finger (dragProgress) instead, so the observer doesn't fight the
    // user's gesture.
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var timeObserverToken: Any?
    @State private var observedPlayer: AVPlayer?

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return isDragging ? dragProgress : min(max(currentTime / duration, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                videoArea(
                    height: showingComments ? geometry.size.height * 0.45 : geometry.size.height,
                    // Only relevant full-screen — once comments are showing,
                    // the video area (and its scrubber) no longer reaches
                    // the true bottom edge, so there's nothing to clear.
                    bottomSafeArea: showingComments ? 0 : geometry.safeAreaInsets.bottom
                )

                if showingComments {
                    commentsArea
                }
            }
        }
        .background(Color.black)
        .onChange(of: isActive) { _, active in
            // Always resume from a clean state when a page (re)becomes
            // current — matches Reels/TikTok behavior where swiping back to
            // a video restarts it rather than remembering it was paused.
            if active {
                isPaused = false
                showingComments = false
                isCaptionExpanded = false
            }
        }
        .onChange(of: isMuted) { _, muted in
            player?.isMuted = muted
        }
        .onAppear {
            player?.isMuted = isMuted
        }
        .task(id: player.map(ObjectIdentifier.init)) {
            attachTimeObserver(to: player)
        }
        .onDisappear {
            detachTimeObserver()
        }
    }

    @ViewBuilder
    private func videoArea(height: CGFloat, bottomSafeArea: CGFloat) -> some View {
        ZStack {
            if let player {
                PlayerLayerView(player: player)
            } else {
                Color.black
            }

            // The video should stay as unobscured as possible — mute only
            // appears when paused, stacked just above the play icon, rather
            // than sitting permanently over the video as a corner badge.
            if isPaused {
                VStack(spacing: 20) {
                    muteButton
                    Image(systemName: "play.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                        .accessibilityIdentifier("pausedIcon")
                }
            }

            VStack(spacing: 0) {
                Spacer()
                bottomInfoBar
                scrubberBar(bottomSafeArea: bottomSafeArea)
            }
        }
        .frame(height: height)
        .clipped()
        .contentShape(Rectangle())
        // Plain .onTapGesture only — no long-press-to-2x. Every gesture
        // that continuously tracks a touch (DragGesture, and even
        // LongPressGesture combined with .updating) blocked PlaybackView's
        // ScrollView(.paging) pager when attached here, confirmed directly
        // by the user across multiple attempts: dragging the comments
        // drawer (which has no gesture on it) pages between videos
        // correctly; dragging the video never did, regardless of which
        // gesture type or priority modifier (.gesture, .onLongPressGesture,
        // .simultaneousGesture) was used, and independent of
        // PlayerLayerView's native UIView (ruled out via
        // isUserInteractionEnabled). The common thread across every broken
        // attempt was continuous tracking (.onChanged/.updating); a plain
        // .onTapGesture — a discrete gesture with no interim reporting at
        // all — is the only thing that hasn't broken paging. Long-press-to-
        // 2x is dropped for now rather than risk swipe navigation again;
        // revisiting it needs an approach that doesn't attach any
        // continuously-tracking gesture to this specific view (e.g. an
        // overlay positioned outside the ScrollView entirely, tracking the
        // active page from PlaybackView instead).
        .onTapGesture {
            guard !isTouchingOverlay else { return }
            togglePause()
        }
    }

    private var bottomInfoBar: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if !showingComments {
                // Icon-only, no label — sits directly above the comments
                // button in this same trailing icon stack.
                Button {
                    onCategorize()
                } label: {
                    Image(systemName: "tag")
                        .foregroundStyle(.white)
                }
                // Same isActive-scoping reasoning as captionText/scrubber
                // elsewhere in this file — the pre-rendered swipe-neighbor
                // page has one of these alive at the same time.
                .accessibilityIdentifier(isActive ? "categorizeButton" : "inactive-categorizeButton")

                Button {
                    showingComments = true
                    loadCommentsIfNeeded()
                } label: {
                    VStack {
                        Image(systemName: "bubble.right.fill")
                        Text("\(video.commentCount)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                }
                .accessibilityIdentifier("showComments")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(video.username) · \(postedDate)")
                    .font(.subheadline).bold()
                    .foregroundStyle(.white)
                    // Identifies which video's page is currently active, for
                    // UI tests to confirm swiping actually advances to a
                    // different video rather than just not crashing — same
                    // isActive-scoping reasoning as captionText/scrubber.
                    .accessibilityIdentifier(isActive ? "videoIdentity_\(video.shortCode)" : "inactive-videoIdentity_\(video.shortCode)")
                if let caption = video.captionText, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(isCaptionExpanded ? nil : 2)
                        .contentShape(Rectangle())
                        // Same reasoning as the scrubber's identifier below:
                        // only the active page's element is named
                        // "captionText", since the pre-rendered
                        // swipe-neighbor page has one alive too.
                        .accessibilityIdentifier(isActive ? "captionText" : "inactive-captionText")
                        // DragGesture(minimumDistance: 0), not .onTapGesture:
                        // .onChanged fires the instant this touch begins,
                        // setting isTouchingOverlay before the video area's
                        // ancestor .onLongPressGesture could possibly see
                        // this touch's release — that flag is what actually
                        // stops the tap from also toggling play/pause
                        // underneath (see videoArea's gesture for why
                        // .highPriorityGesture alone doesn't reliably win
                        // against .onLongPressGesture here).
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in isTouchingOverlay = true }
                                .onEnded { _ in
                                    isTouchingOverlay = false
                                    isCaptionExpanded.toggle()
                                }
                        )
                        .animation(.default, value: isCaptionExpanded)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
    }

    /// A subtle scrubber: a thin full-width track with a slim vertical bar
    /// (not a round knob) marking/dragging the current position. Sits in
    /// its own solid-black strip directly below the caption tray.
    ///
    /// The interactive track itself stays a fixed 32pt tall — bottomSafeArea
    /// is added as plain black space *below* it, not as padding inside the
    /// GeometryReader, so the drag math (which reads geo.size directly)
    /// doesn't need to account for it. This just lifts the touchable track
    /// clear of the home indicator's own swipe-up gesture zone, which it
    /// otherwise sat flush against and intercepted touches from.
    private func scrubberBar(bottomSafeArea: CGFloat) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let thumbX = geo.size.width * progress

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(height: 2)

                    Capsule()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: thumbX, height: 2)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white)
                        .frame(width: 3, height: 16)
                        .position(x: thumbX, y: geo.size.height / 2)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                // Only the active page's element is named "scrubber" — the
                // pre-rendered swipe-neighbor page (see PlaybackView) also has
                // one alive in the hierarchy at the same time, and unlike
                // showComments/hideComments elsewhere in these tests, there's no
                // distinguishing label to disambiguate by, so ambiguity has to
                // be avoided at the source instead.
                .accessibilityIdentifier(isActive ? "scrubber" : "inactive-scrubber")
                // Exposes real elapsed-time progress (not just the visual thumb
                // position) so a UI test can confirm long-press-to-2x actually
                // changes playback rate, rather than just toggling a badge.
                .accessibilityValue("\(currentTime)")
                // highPriorityGesture so this wins over the video area's
                // ancestor .onLongPressGesture for actually seeking; the
                // isTouchingOverlay flag (set here, same reasoning as the
                // caption's gesture above) is what stops that ancestor gesture
                // from also toggling play/pause once the drag ends.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isTouchingOverlay = true
                            isDragging = true
                            dragProgress = min(max(value.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { value in
                            let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                            seek(to: ratio)
                            isDragging = false
                            isTouchingOverlay = false
                        }
                )
            }
            .frame(height: 32)

            Color.black.frame(height: bottomSafeArea)
        }
        .background(Color.black)
    }

    private var muteButton: some View {
        Button {
            isMuted.toggle()
        } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.4), in: Circle())
        }
    }

    private var commentsArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Comments")
                    .font(.headline)
                Spacer()
                Button {
                    showingComments = false
                } label: {
                    Image(systemName: "chevron.down")
                }
                .accessibilityIdentifier("hideComments")
            }
            .padding()

            if comments.isEmpty {
                // No partial-failure state to distinguish anymore — the
                // archive is all-or-nothing, so a fetched video's comments
                // are either genuinely empty or weren't attempted.
                Text("No comments saved for this video.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                Spacer()
            } else {
                List(comments) { comment in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(comment.owner).font(.caption).bold()
                            Spacer()
                            Text("\(comment.likesCount) likes")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(comment.text).font(.caption)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var postedDate: String {
        postedDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(video.takenAt)))
    }

    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            player?.pause()
        } else {
            player?.play()
        }
    }

    private func loadCommentsIfNeeded() {
        guard comments.isEmpty else { return }
        comments = CommentsStore.load(shortCode: video.shortCode)
    }

    private func seek(to ratio: Double) {
        guard duration > 0, let player else { return }
        let target = CMTime(seconds: ratio * duration, preferredTimescale: 600)
        currentTime = ratio * duration
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func attachTimeObserver(to player: AVPlayer?) {
        detachTimeObserver()
        guard let player else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            if !isDragging, time.seconds.isFinite {
                currentTime = time.seconds
            }
            if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite {
                duration = itemDuration
            }
        }
        observedPlayer = player
    }

    private func detachTimeObserver() {
        if let token = timeObserverToken, let observedPlayer {
            observedPlayer.removeTimeObserver(token)
        }
        timeObserverToken = nil
        observedPlayer = nil
    }
}
