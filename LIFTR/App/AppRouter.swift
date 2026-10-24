//
//  AppRouter.swift
//  LIFTR
//

import Foundation
import Observation

/// Which tab is showing, and screens other parts of the app (or a notification) can open.
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case home, coach, log, progress, circle
    }

    var tab = Tab.home
    var showingCravingHelp = false
    /// Set to have Coach switch to voice and start a call when it appears.
    var coachStartsVoice = false
    /// Set to have Coach switch to typing.
    var coachPrefersText = false

    func openCoach(voice: Bool) {
        showingCravingHelp = false
        if voice { coachStartsVoice = true } else { coachPrefersText = true }
        tab = .coach
    }
}
