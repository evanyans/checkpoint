//
//  ImageUtils.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import UIKit

/// Downscales an image and returns compressed JPEG data small enough to store
/// as base64 in a Firestore document.
func downscaledJPEG(_ image: UIImage, maxDimension: CGFloat = 640, quality: CGFloat = 0.5) -> Data? {
    let size = image.size
    let scale = min(1, maxDimension / max(size.width, size.height))
    guard scale < 1 else { return image.jpegData(compressionQuality: quality) }

    let newSize = CGSize(width: size.width * scale, height: size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    let scaled = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: newSize))
    }
    return scaled.jpegData(compressionQuality: quality)
}
