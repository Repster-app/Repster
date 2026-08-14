// AttributionServiceProtocol.swift
// Contract for Apple Search Ads install attribution.
// Feature: paid-vs-organic acquisition measurement (1.4)

import Foundation

/// Where an install came from, as far as Apple is willing to say.
enum AcquisitionChannel: String, Sendable, Equatable {
    /// Apple Search Ads — `attribution: true` in Apple's response.
    case appleSearchAds = "apple_search_ads"

    /// Everything Apple does not attribute to one of our own ads. This is *not*
    /// a synonym for "App Store search": it also swallows every off-store link
    /// we ever post, because AdServices only knows about Apple Search Ads.
    /// Campaign link tokens (`ct=` on an App Store URL) are the only way to
    /// split this bucket further, and they surface in App Store Connect rather
    /// than here.
    case organic
}

/// Apple distinguishes a first-time download from a reinstall by the same Apple
/// ID. Worth keeping apart: a redownload skips onboarding, so mixing the two
/// quietly drags the activation funnel around and counts reinstalls as new
/// customers in any cost-per-install maths.
enum AttributionConversionType: String, Sendable, Equatable {
    case download
    case redownload
}

/// The resolved facts about one install. Every field beyond `channel` is
/// optional because Apple withholds granular values in several documented
/// cases — organic installs carry nothing at all, and campaign-level fields can
/// be absent for low-volume campaigns or non-search campaign types.
struct AttributionRecord: Sendable, Equatable {
    let channel: AcquisitionChannel
    let conversionType: AttributionConversionType?
    let campaignId: Int?
    let adGroupId: Int?
    let keywordId: Int?
    let countryOrRegion: String?

    static let organic = AttributionRecord(
        channel: .organic,
        conversionType: nil,
        campaignId: nil,
        adGroupId: nil,
        keywordId: nil,
        countryOrRegion: nil
    )
}

/// Outcome of a single resolution attempt.
enum AttributionOutcome: Sendable, Equatable {
    /// Terminal success — persist and stop asking.
    case resolved(AttributionRecord)

    /// Apple has not published the record yet. Its API answers 404 for a window
    /// after install (usually seconds, occasionally much longer), so this is the
    /// expected first answer rather than an error. Retry, including on later
    /// launches.
    case notReady

    /// Terminal failure — this device or build will never produce a token
    /// (simulator, unsupported platform). Stop asking.
    case unavailable
}

protocol AttributionServiceProtocol: Sendable {
    /// Resolves once per install and then does nothing on every later launch.
    /// Safe to call unconditionally at startup.
    func resolveIfNeeded() async
}
