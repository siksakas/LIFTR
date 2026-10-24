//
//  VoiceSettingsSheet.swift
//  LIFTR
//

import SwiftUI

/// Opened from the gear on Coach: pick the voice Tuk talks in.
struct VoiceSettingsSheet: View {
    @Environment(CheckInPartner.self) private var partner
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TukVoice.savedVoiceIDKey) private var savedVoiceID = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(partner.status.isLive
                        ? "Tuk will switch voices on your next call."
                        : "Pick how Tuk sounds when you talk.")
                        .font(.figtree(15, relativeTo: .body))
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        ForEach(TukVoice.all) { voice in
                            row(voice)
                            if voice != TukVoice.all.last {
                                Divider().overlay(Palette.cardBorder).padding(.leading, 16)
                            }
                        }
                    }
                    .liftrCard()
                }
                .padding(16)
            }
            .background(Palette.background)
            .navigationTitle("Tuk's voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.figtree(16, .heavy, relativeTo: .body))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ voice: TukVoice) -> some View {
        let isSelected = (voice.voiceID ?? "") == savedVoiceID
        return Button {
            savedVoiceID = voice.voiceID ?? ""
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.name)
                        .font(.figtree(15, .heavy, relativeTo: .headline))
                        .foregroundStyle(Palette.ink)
                    Text(voice.detail)
                        .font(.figtree(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
