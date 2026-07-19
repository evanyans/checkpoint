//
//  LocationManager.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject {
    @Published var lastLocation: CLLocation?
    /// Human-readable street address for the current location (reverse-geocoded),
    /// e.g. "123 Main St, San Francisco, CA". Far more useful on a call than lat/long.
    @Published var readableAddress: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var isGeocoding = false
    private var lastGeocodedLocation: CLLocation?
    private var lastGeocodedAt: Date?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// Reverse-geocode into a readable address. Throttled: CLGeocoder rate-limits, so
    /// skip if we resolved recently and haven't moved far.
    private func reverseGeocodeIfNeeded(_ location: CLLocation) {
        if isGeocoding { return }
        if let last = lastGeocodedLocation, let at = lastGeocodedAt,
           location.distance(from: last) < 40, Date().timeIntervalSince(at) < 20 {
            return
        }
        isGeocoding = true
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else { return }
            self.isGeocoding = false
            guard let placemark = placemarks?.first else { return }
            self.lastGeocodedLocation = location
            self.lastGeocodedAt = Date()
            let address = Self.format(placemark)
            DispatchQueue.main.async {
                if !address.isEmpty { self.readableAddress = address }
            }
        }
    }

    /// Assemble a compact address from whatever components are available.
    private static func format(_ p: CLPlacemark) -> String {
        var parts: [String] = []
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        if !street.isEmpty {
            parts.append(street)
        } else if let name = p.name {
            parts.append(name)                       // POI / generic name when no street number
        }
        if street.isEmpty, let neighborhood = p.subLocality { parts.append(neighborhood) }
        if let city = p.locality { parts.append(city) }
        if let admin = p.administrativeArea { parts.append(admin) }
        if let postal = p.postalCode { parts.append(postal) }
        return parts.joined(separator: ", ")
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.lastLocation = location
        }
        reverseGeocodeIfNeeded(location)
    }
}
