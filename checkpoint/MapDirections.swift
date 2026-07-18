//
//  MapDirections.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import SwiftUI
import MapKit
import CoreLocation

/// Opens Apple Maps with driving directions to the coordinate.
func openAppleMaps(to coordinate: CLLocationCoordinate2D, name: String = "Emergency location") {
    let placemark = MKPlacemark(coordinate: coordinate)
    let mapItem = MKMapItem(placemark: placemark)
    mapItem.name = name
    mapItem.openInMaps(launchOptions: [
        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
    ])
}

/// Opens Google Maps directions. Uses a universal link so it launches the
/// Google Maps app if installed, or falls back to the browser otherwise.
func openGoogleMaps(to coordinate: CLLocationCoordinate2D) {
    let destination = "\(coordinate.latitude),\(coordinate.longitude)"
    guard let url = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(destination)&travelmode=driving") else { return }
    UIApplication.shared.open(url)
}

extension View {
    /// Presents an action sheet to choose which maps app to open directions in.
    func directionsChooser(isPresented: Binding<Bool>, coordinate: CLLocationCoordinate2D?) -> some View {
        confirmationDialog("Get Directions", isPresented: isPresented, titleVisibility: .visible) {
            Button("Apple Maps") {
                if let coordinate { openAppleMaps(to: coordinate) }
            }
            Button("Google Maps") {
                if let coordinate { openGoogleMaps(to: coordinate) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
