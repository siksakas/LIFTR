//
//  CircleView.swift
//  LIFTR
//

import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Your circle: people cheering you on, and the voice notes and photos they sent,
/// saved to play during craving help.
struct CircleView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CircleMember.invitedAt) private var members: [CircleMember]
    @Query(sort: \Encouragement.createdAt, order: .reverse) private var saved: [Encouragement]

    @State private var player = VoiceNotePlayer()
    @State private var showingInvite = false
    @State private var selectedMember: CircleMember?
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your circle")
                        .font(.figtree(30, .heavy, relativeTo: .largeTitle))
                        .tracking(-0.3)
                        .foregroundStyle(Palette.ink)
                    Text("People cheering you on. Nothing is added until they say yes.")
                        .font(.figtree(15, relativeTo: .body))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

                CareCard()

                if !saved.isEmpty { savedCard }
                if !members.isEmpty { peopleCard }

                Button {
                    toast = nil
                    showingInvite = true
                } label: {
                    Label("Invite someone", systemImage: "person.badge.plus")
                        .font(.figtree(16, .heavy, relativeTo: .headline))
                        .foregroundStyle(Palette.onGreen)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Palette.green, in: Capsule())
                }
                .buttonStyle(.pressable)

                if members.count <= 3 { steps }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .background(Palette.background)
        .tabBarClearance()
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.figtree(14, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color(hex: 0xF6F3EA))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x2F3B30), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, LiftrTabBar.clearance + 8)
                    .transition(.opacity.combined(with: .offset(y: 10)))
                    .task {
                        try? await Task.sleep(for: .seconds(4.2))
                        withAnimation { self.toast = nil }
                    }
            }
        }
        .animation(.easeOut(duration: 0.3), value: toast)
        .sheet(isPresented: $showingInvite) {
            InviteSheet { name in
                withAnimation { toast = "Invite sent. Nothing is added until \(name) says yes." }
            }
        }
        .sheet(item: $selectedMember) { member in
            MemberSheet(member: member)
        }
        .onDisappear { player.stop() }
    }

    private var savedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Saved for tough moments")
                    .font(.figtree(13, .heavy, relativeTo: .footnote))
                Spacer()
                Text("Plays during SOS")
                    .font(.figtree(12, .bold, relativeTo: .caption))
            }
            .foregroundStyle(Palette.inkSecondary)
            .padding(.horizontal, 2)
            .padding(.bottom, 6)

            ForEach(Array(saved.prefix(4).enumerated()), id: \.element.id) { index, item in
                EncouragementRow(item: item, player: player)
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) {
                        if index < min(saved.count, 4) - 1 { Palette.divider.frame(height: 1) }
                    }
                    .contextMenu {
                        Button("Remove", systemImage: "trash", role: .destructive) { remove(item) }
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .liftrCard()
    }

    private var peopleCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                Button {
                    selectedMember = member
                } label: {
                    HStack(spacing: 12) {
                        InitialAvatar(name: member.name, color: member.avatarColor, size: 42)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(member.name)
                                .font(.figtree(15, .heavy, relativeTo: .headline))
                                .foregroundStyle(Palette.ink)
                            Text(member.summary)
                                .font(.figtree(13, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer(minLength: 0)
                        if member.hasJoined {
                            Pill(text: "Joined", foreground: Palette.greenMuted, background: Palette.greenSoft)
                        } else {
                            Pill(text: "Invited", foreground: Palette.tanInk, background: Palette.tan)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    if index < members.count - 1 { Palette.divider.frame(height: 1) }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .liftrCard()
    }

    private var steps: some View {
        HStack(alignment: .top, spacing: 8) {
            step(1, "You send an invite")
            step(2, "They record a note or pick a photo")
            step(3, "You save it here for SOS")
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("How it works: you send an invite, they record a note or pick a photo, you save it here for SOS.")
    }

    private func step(_ number: Int, _ text: String) -> some View {
        VStack(spacing: 4) {
            Text("\(number)")
                .font(.figtree(13, .heavy, relativeTo: .footnote))
                .foregroundStyle(Palette.ink)
                .frame(width: 26, height: 26)
                .background(Palette.sand, in: Circle())
            Text(text)
                .font(.figtree(12, .bold, relativeTo: .caption))
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func remove(_ item: Encouragement) {
        if player.isPlaying(item.fileURL) { player.stop() }
        try? FileManager.default.removeItem(at: item.fileURL)
        context.delete(item)
        try? context.save()
    }
}

/// A saved voice note or photo, with play controls for voice.
struct EncouragementRow: View {
    var item: Encouragement
    var player: VoiceNotePlayer

    var body: some View {
        let name = item.member?.name ?? "Someone"
        HStack(spacing: 12) {
            switch item.kind {
            case .voice:
                let isPlaying = player.isPlaying(item.fileURL)
                InitialAvatar(name: name, color: item.member?.avatarColor ?? Palette.tan, size: 48)
                VStack(alignment: .leading, spacing: 5) {
                    (Text(name).font(.figtree(15, .heavy, relativeTo: .headline))
                        + Text(" · voice note").font(.figtree(15, .semibold, relativeTo: .headline)).foregroundColor(Palette.inkSecondary))
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: 8) {
                        WaveformBars(count: 24, progress: isPlaying ? player.progress : 0, maxHeight: 20)
                        Text((item.duration ?? 0).minutesAndSeconds)
                            .font(.figtree(13, .bold, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
                PlayButton(isPlaying: isPlaying) { player.toggle(item.fileURL) }
                    .accessibilityLabel(isPlaying ? "Pause voice note from \(name)" : "Play voice note from \(name)")
            case .photo:
                EncouragementPhoto(item: item, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    (Text(name).font(.figtree(15, .heavy, relativeTo: .headline))
                        + Text(" · photo").font(.figtree(15, .semibold, relativeTo: .headline)).foregroundColor(Palette.inkSecondary))
                        .foregroundStyle(Palette.ink)
                    if let caption = item.caption {
                        Text("“\(caption)”")
                            .font(.tuk(14))
                            .foregroundStyle(Palette.tukInk)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 2)
    }
}

/// A saved photo, cropped square.
struct EncouragementPhoto: View {
    var item: Encouragement
    var size: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: item.fileURL.path(percentEncoded: false)) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Palette.sky
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.outline, lineWidth: 1.5))
        .accessibilityLabel(item.caption.map { "Photo: \($0)" } ?? "Photo")
    }
}

// MARK: - Invite

private struct InviteSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var onSent: (String) -> Void

    @State private var name = ""
    @State private var voiceNotes = true
    @State private var photos = true
    @State private var sharing = false
    /// Set once the share sheet reports the invite went out.
    @State private var sent = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var asksFor: String {
        let kinds = [voiceNotes ? "voice notes" : nil, photos ? "photos" : nil].compactMap { $0 }
        return kinds.isEmpty ? "a message" : kinds.joined(separator: " or ")
    }

    private var inviteText: String {
        "Hi \(trimmedName.isEmpty ? "there" : trimmedName), I’m cutting down on smoking with LIFTR. Would you send me \(asksFor) I can play when it’s hard? Only I will see or hear it, and I’ll only keep what you’re happy for me to keep."
    }

    private var canSend: Bool { !trimmedName.isEmpty && (voiceNotes || photos) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Invite a loved one")
                    .font(.figtree(22, .heavy, relativeTo: .title2))
                    .foregroundStyle(Palette.ink)
                Text("They get a message from you saying exactly what it's for, and choose yes or no. Nothing plays until you save what they send.")
                    .font(.figtree(14, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Their name")
                    .font(.figtree(13, .heavy, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink)
                TextField("", text: $name, prompt: Text("Dad"))
                    .font(.figtree(16, relativeTo: .body))
                    .textContentType(.name)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.chipBorder, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("They can send you")
                    .font(.figtree(13, .heavy, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 8) {
                    kindChip("Voice notes", isOn: $voiceNotes)
                    kindChip("Photos", isOn: $photos)
                }
            }

            Text(inviteText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tukBubble(radius: 20)

            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }
                    .font(.figtree(16, .heavy, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Palette.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.chipBorder, lineWidth: 1.5))
                Button("Send invite") { sharing = true }
                    .font(.figtree(16, .heavy, relativeTo: .headline))
                    .foregroundStyle(Palette.onGreen)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(canSend ? Palette.green : Color(hex: 0xA9B8A6), in: Capsule())
                    .disabled(!canSend)
                    .layoutPriority(1)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $sharing, onDismiss: finishIfSent) {
            ActivityView(items: [inviteText]) { completed in
                sent = completed
                sharing = false
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// Runs after the share sheet is gone, so this sheet can close cleanly too.
    private func finishIfSent() {
        guard sent else { return }
        context.insert(CircleMember(name: trimmedName, asksFor: asksFor))
        try? context.save()
        onSent(trimmedName)
        dismiss()
    }

    private func kindChip(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(isOn.wrappedValue ? "✓ \(label)" : label)
                .font(.figtree(14, .heavy, relativeTo: .subheadline))
                .foregroundStyle(isOn.wrappedValue ? Palette.greenInk : Palette.inkSecondary)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(isOn.wrappedValue ? Palette.greenSoft : Palette.card, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn.wrappedValue ? Palette.green : Palette.chipBorder, lineWidth: 1.5))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
}

/// The system share sheet. `onFinish` gets whether the user actually sent it.
struct ActivityView: UIViewControllerRepresentable {
    var items: [Any]
    var onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in onFinish(completed) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - One person

/// Save what someone sent: record a voice note with them, import an audio file, or pick a photo.
private struct MemberSheet: View {
    var member: CircleMember
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var player = VoiceNotePlayer()
    @State private var recorder = VoiceNoteRecorder()
    @State private var recordingURL: URL?
    @State private var importingAudio = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingPhoto: UIImage?
    @State private var caption = ""
    @State private var confirmingRemove = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        InitialAvatar(name: member.name, color: member.avatarColor, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name)
                                .font(.figtree(20, .heavy, relativeTo: .title3))
                            Text("Asked for \(member.asksFor) · \(member.summary.lowercased())")
                                .font(.figtree(13, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .foregroundStyle(Palette.ink)

                    if !member.items.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(member.items.sorted { $0.createdAt > $1.createdAt }) { item in
                                EncouragementRow(item: item, player: player)
                                    .padding(.vertical, 9)
                                    .contextMenu {
                                        Button("Remove", systemImage: "trash", role: .destructive) { remove(item) }
                                    }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .liftrCard()
                    }

                    Text("Add what \(member.name) sent")
                        .font(.figtree(16, .heavy, relativeTo: .headline))
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 4)

                    recordCard
                    if let pendingPhoto { captionCard(pendingPhoto) }

                    HStack(spacing: 10) {
                        Button {
                            importingAudio = true
                        } label: {
                            actionLabel("Import audio", systemImage: "waveform")
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            actionLabel("Add a photo", systemImage: "photo")
                        }
                    }
                    .buttonStyle(.pressable)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.figtree(14, .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Palette.tanInk)
                    }

                    Button("Remove \(member.name) from your circle", role: .destructive) { confirmingRemove = true }
                        .font(.figtree(14, .bold, relativeTo: .subheadline))
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.figtree(16, .heavy, relativeTo: .body))
                }
            }
        }
        .fileImporter(isPresented: $importingAudio, allowedContentTypes: [.audio]) { result in
            if case let .success(url) = result { importAudio(from: url) }
        }
        .onChange(of: photoItem) { loadPhoto() }
        .confirmationDialog("Remove \(member.name)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: removeMember)
        } message: {
            Text("Their voice notes and photos are deleted from this phone too.")
        }
        .onDisappear {
            player.stop()
            if recorder.isRecording { recorder.stop() }
        }
    }

    private var recordCard: some View {
        HStack(spacing: 14) {
            Button {
                Task { await toggleRecording() }
            } label: {
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.onGreen)
                    .frame(width: 56, height: 56)
                    .background(recorder.isRecording ? Color(hex: 0xB0553C) : Palette.green, in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Record a voice note")
            VStack(alignment: .leading, spacing: 3) {
                Text(recorder.isRecording ? "Recording… \(recorder.elapsed.minutesAndSeconds)" : "Record a voice note")
                    .font(.figtree(16, .heavy, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                Text(recorder.isRecording ? "Tap stop when they're done." : "Hand them your phone and let them say a few words.")
                    .font(.figtree(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .liftrCard()
    }

    private func captionCard(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                TextField("What did they say? (optional)", text: $caption, axis: .vertical)
                    .font(.tuk(14))
                    .lineLimit(1...3)
            }
            HStack {
                Button("Cancel") { pendingPhoto = nil; photoItem = nil; caption = "" }
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
                Button("Save photo") { savePhoto(image) }
                    .foregroundStyle(Palette.green)
            }
            .font(.figtree(15, .heavy, relativeTo: .body))
        }
        .padding(14)
        .liftrCard()
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.figtree(15, .heavy, relativeTo: .headline))
            .foregroundStyle(Palette.greenDark)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Palette.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.green, lineWidth: 1.5))
    }

    // MARK: - Saving

    private func toggleRecording() async {
        if recorder.isRecording, let url = recordingURL {
            let length = recorder.stop()
            recordingURL = nil
            add(.voice, fileName: url.lastPathComponent, duration: VoiceNotePlayer.duration(of: url) ?? length)
            return
        }
        player.stop()
        let url = Encouragement.folder.appending(path: "\(UUID().uuidString).m4a")
        if await recorder.start(to: url) {
            recordingURL = url
            errorMessage = nil
        } else {
            errorMessage = "Couldn't record. Check that LIFTR can use the microphone in Settings."
        }
    }

    private func importAudio(from source: URL) {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
        let destination = Encouragement.folder.appending(path: "\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            guard let duration = VoiceNotePlayer.duration(of: destination) else {
                try? FileManager.default.removeItem(at: destination)
                errorMessage = "That file couldn't be played. Try an .m4a or .mp3."
                return
            }
            add(.voice, fileName: destination.lastPathComponent, duration: duration)
        } catch {
            errorMessage = "Couldn't import that file: \(error.localizedDescription)"
        }
    }

    private func loadPhoto() {
        guard let photoItem else { return }
        Task {
            if let data = try? await photoItem.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                pendingPhoto = image
                errorMessage = nil
            } else {
                errorMessage = "Couldn't open that photo."
            }
        }
    }

    private func savePhoto(_ image: UIImage) {
        let fileName = "\(UUID().uuidString).jpg"
        guard let data = image.resizedToFit(1200).jpegData(compressionQuality: 0.85) else { return }
        do {
            try data.write(to: Encouragement.folder.appending(path: fileName))
            let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            add(.photo, fileName: fileName, caption: text.isEmpty ? nil : text)
            pendingPhoto = nil
            photoItem = nil
            caption = ""
        } catch {
            errorMessage = "Couldn't save that photo: \(error.localizedDescription)"
        }
    }

    private func add(_ kind: Encouragement.Kind, fileName: String, caption: String? = nil, duration: Double? = nil) {
        let item = Encouragement(kind: kind, fileName: fileName, caption: caption, duration: duration, member: member)
        context.insert(item)
        try? context.save()
    }

    private func remove(_ item: Encouragement) {
        if player.isPlaying(item.fileURL) { player.stop() }
        try? FileManager.default.removeItem(at: item.fileURL)
        context.delete(item)
        try? context.save()
    }

    private func removeMember() {
        player.stop()
        for item in member.items {
            try? FileManager.default.removeItem(at: item.fileURL)
        }
        context.delete(member)
        try? context.save()
        dismiss()
    }
}

private extension UIImage {
    /// Scales down so the longest side is at most `maxSide` points.
    func resizedToFit(_ maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

// MARK: - LIFTR Care

/// Where video visits with a clinician are booked. Both are empty until there's a real
/// booking service; until then the card says visits are coming soon.
enum LiftrCare {
    static let bookingURL: URL? = nil
    /// Shown under "Next opening", like "Today, 4:30 pm".
    static let nextOpening: String? = nil
}

/// "Talk to a professional": a way to book a video visit with a licensed clinician.
private struct CareCard: View {
    @Environment(\.openURL) private var openURL
    @State private var showingComingSoon = false

    private static let navy = Color(hex: 0x0E1224)
    private static let lavender = Color(hex: 0xC9B6F2)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LIFTR CARE")
                .font(.figtree(13, .bold, relativeTo: .caption))
                .tracking(1.6)
                .foregroundStyle(Self.lavender)
            Text("Talk to a professional.")
                .font(.figtree(34, .heavy, relativeTo: .largeTitle))
                .tracking(-0.8)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Text("Licensed clinicians who help people quit nicotine. Private and judgment-free.")
                .font(.figtree(16, relativeTo: .body))
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    bookButton
                    Spacer(minLength: 0)
                    nextOpening(alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: 12) {
                    bookButton
                    nextOpening(alignment: .leading)
                }
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(colors: [Self.navy, Color(hex: 0x1A2040)], startPoint: .bottomLeading, endPoint: .topTrailing)
                // The soft blue-to-lavender glow in the top corner.
                GeometryReader { proxy in
                    let size = proxy.size.width * 0.62
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Self.lavender, Color(hex: 0x6F86E6), Color(hex: 0x2F45B8).opacity(0.55)],
                                startPoint: .topTrailing,
                                endPoint: .bottomLeading
                            )
                        )
                        .frame(width: size, height: size)
                        .blur(radius: 22)
                        .position(x: proxy.size.width * 0.82, y: size * 0.42)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .alert("Video visits are coming soon", isPresented: $showingComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Booking with a LIFTR Care clinician isn't open yet. If you need help right now, your doctor or a quitline like 1-800-QUIT-NOW can help.")
        }
    }

    private var bookButton: some View {
        Button(action: book) {
            HStack(spacing: 10) {
                Text("Book a video visit")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .font(.figtree(16, .semibold, relativeTo: .headline))
            .foregroundStyle(Self.navy)
            .padding(.horizontal, 20)
            .frame(height: 50)
            .background(.white, in: Capsule())
            .fixedSize()
        }
        .buttonStyle(.pressable)
    }

    private func nextOpening(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text("Next opening")
                .font(.figtree(13, relativeTo: .footnote))
                .foregroundStyle(.white.opacity(0.65))
            Text(LiftrCare.nextOpening ?? "Coming soon")
                .font(.figtree(14, .bold, relativeTo: .subheadline))
                .foregroundStyle(.white)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private func book() {
        if let url = LiftrCare.bookingURL {
            openURL(url)
        } else {
            showingComingSoon = true
        }
    }
}
