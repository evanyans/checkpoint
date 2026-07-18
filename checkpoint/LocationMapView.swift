//
//  LocationMapView.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import SwiftUI
import MapKit

struct LocationMapView: View {
    let coordinate: CLLocationCoordinate2D

    @State private var cameraPosition: MapCameraPosition

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        _cameraPosition = State(initialValue: .region(
            MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
        ))
    }

    var body: some View {
        Map(position: $cameraPosition) {
            Marker("Emergency", coordinate: coordinate)
                .tint(.red)
        }
        .onChange(of: coordinate.latitude) { _, _ in
            cameraPosition = .region(
                MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
            )
        }
    }
}
