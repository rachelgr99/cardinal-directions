import CoreLocation
import Foundation

/// Decoder for the Google encoded-polyline shapes the ETA Spot feed uses for
/// route geometry. The feed inserts `??` between segments, which decode to
/// zero-deltas and are simply skipped.
enum Polyline {
    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        var index = encoded.startIndex
        var lat = 0
        var lng = 0

        func nextValue() -> Int? {
            var result = 0
            var shift = 0
            while index < encoded.endIndex {
                let byte = Int(encoded[index].asciiValue ?? 0) - 63
                index = encoded.index(after: index)
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20 {
                    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
                }
            }
            return nil
        }

        while index < encoded.endIndex {
            guard let dLat = nextValue(), let dLng = nextValue() else { break }
            lat += dLat
            lng += dLng
            let coordinate = CLLocationCoordinate2D(latitude: Double(lat) * 1e-5, longitude: Double(lng) * 1e-5)
            if let last = coordinates.last, last.latitude == coordinate.latitude, last.longitude == coordinate.longitude {
                continue
            }
            coordinates.append(coordinate)
        }
        return coordinates
    }
}

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
