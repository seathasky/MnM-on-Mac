//
//  LauncherStep.swift
//  MnM on Mac
//
//  Created by Matthew Centonze on 9/5/26.
//

enum LauncherStep {
    case setup, update, play

    init?(readiness: String) {
        switch readiness {
        case "needs_wine", "needs_libraries", "needs_prefix", "needs_rosetta": self = .setup
        case "needs_login", "needs_game", "missing_launcher": self = .update
        case "ready": self = .play
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .setup: return "Set Up Wine"
        case .update: return "Update"
        case .play: return "Play"
        }
    }
}
