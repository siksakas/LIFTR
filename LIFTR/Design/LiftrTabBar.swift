//
//  LiftrTabBar.swift
//  LIFTR
//

import SwiftUI

/// The floating tab bar with the Coach mic button in the middle.
struct LiftrTabBar: View {
    /// Room screens leave at the bottom so their content can scroll clear of the bar.
    static let clearance: CGFloat = 88

    @Binding var selection: AppRouter.Tab

    var body: some View {
        HStack(spacing: 0) {
            item(.home, title: "Home", symbol: "house")
            item(.log, title: "Log", symbol: "plus.circle")
            coachItem
            item(.progress, title: "Progress", symbol: "chart.line.uptrend.xyaxis")
            item(.circle, title: "Circle", symbol: "person.2")
        }
        .padding(.horizontal, 6)
        .frame(height: 68)
        .background(Palette.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.cardBorder, lineWidth: 1))
        .shadow(color: Palette.ink.opacity(0.16), radius: 14, y: 10)
        .padding(.horizontal, 14)
    }

    private func item(_ tab: AppRouter.Tab, title: String, symbol: String) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .frame(height: 22)
                Text(title)
                    .font(.figtree(11, isSelected ? .heavy : .bold, relativeTo: .caption2))
            }
            .foregroundStyle(isSelected ? Palette.ink : Palette.inkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
            .frame(height: 54, alignment: .bottom)
            .background(isSelected ? Palette.sand : .clear, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var coachItem: some View {
        let isSelected = selection == .coach
        return Button {
            selection = .coach
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.onGreen)
                .frame(width: 50, height: 50)
                .background(Palette.green, in: Circle())
                .background {
                    // A soft ring around the button while the Coach tab is open.
                    if isSelected { Circle().fill(Palette.greenPulse).padding(-4) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Coach")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
