// WorkoutLiveActivityBundle.swift
// Entry point for the WorkoutLiveActivity widget extension.
//
// This bundle registers the Live Activity widget that displays workout
// state on the Lock Screen and Dynamic Island.

import SwiftUI
import WidgetKit

@main
struct WorkoutLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivityWidget()
    }
}
