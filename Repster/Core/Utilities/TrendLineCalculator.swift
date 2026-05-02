// TrendLineCalculator.swift
// Pure utility for linear regression calculation.
// Used by Workouts and Exercises tabs for trend line overlays.
// Feature: 016-charts-tab-v2 WP05 (T103)

import Foundation

struct TrendLineCalculator {
    /// Computes simple linear regression on an array of y values
    /// where x is the array index (0, 1, 2, ...).
    /// Returns nil if fewer than 2 points.
    static func compute(values: [Double]) -> TrendLineData? {
        guard values.count >= 2 else { return nil }

        let n = Double(values.count)
        let indices = values.indices.map { Double($0) }

        let xMean = indices.reduce(0, +) / n
        let yMean = values.reduce(0, +) / n

        var numerator: Double = 0
        var denominator: Double = 0

        for i in values.indices {
            let x = Double(i)
            numerator += (x - xMean) * (values[i] - yMean)
            denominator += (x - xMean) * (x - xMean)
        }

        guard denominator != 0 else { return nil }

        let slope = numerator / denominator
        let intercept = yMean - slope * xMean

        return TrendLineData(
            slope: slope,
            intercept: intercept,
            startPoint: (x: 0, y: intercept),
            endPoint: (x: Double(values.count - 1), y: slope * Double(values.count - 1) + intercept),
            meanValue: yMean
        )
    }
}
