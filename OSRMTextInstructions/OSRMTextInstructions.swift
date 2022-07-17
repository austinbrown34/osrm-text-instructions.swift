import Foundation
import CoreGraphics
import CoreLocation

import Turf
import Polyline
import func Polyline.decodePolyline

import struct Polyline.LocationCoordinate2D
import typealias Polyline.LocationCoordinate2D

import func Polyline.encodeCoordinates
import UIKit
import _Concurrency





#if canImport(CoreGraphics)
/**
 An image scale factor.
 */
public typealias Scale = CGFloat
#else
/**
 An image scale factor.
 */
public typealias Scale = Double
#endif


#if canImport(CoreLocation)
/**
 The velocity (measured in meters per second) at which the device is moving.
 
 This is a compatibility shim to keep the library’s public interface consistent between Apple and non-Apple platforms that lack Core Location. On Apple platforms, you can use `CLLocationSpeed` anywhere you see this type.
 */
public typealias LocationSpeed = CLLocationSpeed

/**
 The accuracy of a geographical coordinate.
 
 This is a compatibility shim to keep the library’s public interface consistent between Apple and non-Apple platforms that lack Core Location. On Apple platforms, you can use `CLLocationAccuracy` anywhere you see this type.
 */
public typealias LocationAccuracy = CLLocationAccuracy
#else
/**
 The velocity (measured in meters per second) at which the device is moving.
 */
public typealias LocationSpeed = Double

/**
 The accuracy of a geographical coordinate.
 */
public typealias LocationAccuracy = Double
#endif

public extension CodingUserInfoKey {
    static let options = CodingUserInfoKey(rawValue: "com.mapbox.directions.coding.routeOptions")!
    static let httpResponse = CodingUserInfoKey(rawValue: "com.mapbox.directions.coding.httpResponse")!
    static let credentials = CodingUserInfoKey(rawValue: "com.mapbox.directions.coding.credentials")!
    static let tracepoints = CodingUserInfoKey(rawValue: "com.mapbox.directions.coding.tracepoints")!
    
    static let responseIdentifier = CodingUserInfoKey(rawValue: "com.mapbox.directions.coding.responseIdentifier")!
    static let routeIndex = CodingUserInfoKey(rawValue: "com.mapbox.directions.coding.routeIndex")!
    static let startLegIndex = CodingUserInfoKey(rawValue: "com.mapbox.directions.coding.startLegIndex")!
}

extension LocationCoordinate2D {
    internal var requestDescription: String {
        return "\(longitude.rounded(to: 1e6)),\(latitude.rounded(to: 1e6))"
    }
}

extension BoundingBox: CustomStringConvertible {
    public var description: String {
        return "\(southWest.longitude),\(southWest.latitude);\(northEast.longitude),\(northEast.latitude)"
    }
}

extension LineString {
    init(polyLineString: PolyLineString) throws {
        switch polyLineString {
        case let .lineString(lineString):
            self = lineString
        case let .polyline(encodedPolyline, precision: precision):
            self = try LineString(encodedPolyline: encodedPolyline, precision: precision)
        }
    }
    
    init(encodedPolyline: String, precision: Double) throws {
        guard var coordinates = decodePolyline(encodedPolyline, precision: precision) as [LocationCoordinate2D]? else {
            throw GeometryError.cannotDecodePolyline(precision: precision)
        }
        // If the polyline has zero length with both endpoints at the same coordinate, Polyline drops one of the coordinates.
        // https://github.com/raphaelmor/Polyline/issues/59
        // Duplicate the coordinate to ensure a valid GeoJSON geometry.
        if coordinates.count == 1 {
            coordinates.append(coordinates[0])
        }
        #if canImport(CoreLocation)
        self.init(coordinates)
        #else
        self.init(coordinates.map { Turf.LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
        #endif
    }
}

public enum GeometryError: LocalizedError {
    case cannotDecodePolyline(precision: Double)
    
    public var failureReason: String? {
        switch self {
        case let .cannotDecodePolyline(precision):
            return "Unable to decode the string as a polyline with precision \(precision)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .cannotDecodePolyline:
            return "Choose the precision that the string was encoded with."
        }
    }
}

public struct AdministrativeRegion: Codable, Equatable, ForeignMemberContainer {
    public var foreignMembers: JSONObject = [:]

    private enum CodingKeys: String, CodingKey {
        case countryCodeAlpha3 = "iso_3166_1_alpha3"
        case countryCode = "iso_3166_1"
    }

    /// ISO 3166-1 alpha-3 country code
    public var countryCodeAlpha3: String?
    /// ISO 3166-1 country code
    public var countryCode: String

    public init(countryCode: String, countryCodeAlpha3: String) {
        self.countryCode = countryCode
        self.countryCodeAlpha3 = countryCodeAlpha3
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        countryCode = try container.decode(String.self, forKey: .countryCode)
        countryCodeAlpha3 = try container.decodeIfPresent(String.self, forKey: .countryCodeAlpha3)
        
        try decodeForeignMembers(notKeyedBy: CodingKeys.self, with: decoder)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(countryCode, forKey: .countryCode)
        try container.encodeIfPresent(countryCodeAlpha3, forKey: .countryCodeAlpha3)
        
        try encodeForeignMembers(notKeyedBy: CodingKeys.self, to: encoder)
    }
}


enum SpeedLimitDescriptor: Equatable {
    enum UnitDescriptor: String, Codable {
        case milesPerHour = "mph"
        case kilometersPerHour = "km/h"
        
        init?(unit: UnitSpeed) {
            switch unit {
            case .milesPerHour:
                self = .milesPerHour
            case .kilometersPerHour:
                self = .kilometersPerHour
            default:
                return nil
            }
        }
        
        var describedUnit: UnitSpeed {
            switch self {
            case .milesPerHour:
                return .milesPerHour
            case .kilometersPerHour:
                return .kilometersPerHour
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case none
        case speed
        case unknown
        case unit
    }
    
    case none
    case some(speed: Measurement<UnitSpeed>)
    case unknown
    
    init(speed: Measurement<UnitSpeed>?) {
        guard let speed = speed else {
            self = .unknown
            return
        }
        
        if speed.value.isInfinite {
            self = .none
        } else {
            self = .some(speed: speed)
        }
    }
}

extension SpeedLimitDescriptor: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if (try container.decodeIfPresent(Bool.self, forKey: .none)) ?? false {
            self = .none
        } else if (try container.decodeIfPresent(Bool.self, forKey: .unknown)) ?? false {
            self = .unknown
        } else {
            let unitDescriptor = try container.decode(UnitDescriptor.self, forKey: .unit)
            let unit = unitDescriptor.describedUnit
            let value = try container.decode(Double.self, forKey: .speed)
            self = .some(speed: .init(value: value, unit: unit))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .none:
            try container.encode(true, forKey: .none)
        case .some(var speed):
            let unitDescriptor = UnitDescriptor(unit: speed.unit) ?? {
                speed = speed.converted(to: .kilometersPerHour)
                return .kilometersPerHour
            }()
            try container.encode(unitDescriptor, forKey: .unit)
            try container.encode(speed.value, forKey: .speed)
        case .unknown:
            try container.encode(true, forKey: .unknown)
        }
    }
}

extension Measurement where UnitType == UnitSpeed {
    init?(speedLimitDescriptor: SpeedLimitDescriptor) {
        switch speedLimitDescriptor {
        case .none:
            self = .init(value: .infinity, unit: .kilometersPerHour)
        case .some(let speed):
            self = speed
        case .unknown:
            return nil
        }
    }
}


public struct AttributeOptions: OptionSet, CustomStringConvertible {
    public var rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /**
     Distance (in meters) along the segment.
     
     When this attribute is specified, the `RouteLeg.segmentDistances` property contains one value for each segment in the leg’s full geometry.
     */
    public static let distance = AttributeOptions(rawValue: 1 << 1)
    
    /**
     Expected travel time (in seconds) along the segment.
     
     When this attribute is specified, the `RouteLeg.expectedSegmentTravelTimes` property contains one value for each segment in the leg’s full geometry.
     */
    public static let expectedTravelTime = AttributeOptions(rawValue: 1 << 2)

    /**
     Current average speed (in meters per second) along the segment.
     
     When this attribute is specified, the `RouteLeg.segmentSpeeds` property contains one value for each segment in the leg’s full geometry.
     */
    public static let speed = AttributeOptions(rawValue: 1 << 3)
    
    /**
     Traffic congestion level along the segment.
     
     When this attribute is specified, the `RouteLeg.congestionLevels` property contains one value for each segment in the leg’s full geometry.
     
     This attribute requires `ProfileIdentifier.automobileAvoidingTraffic`. Any other profile identifier produces `CongestionLevel.unknown` for each segment along the route.
     */
    public static let congestionLevel = AttributeOptions(rawValue: 1 << 4)
    
    /**
     The maximum speed limit along the segment.
     
     When this attribute is specified, the `RouteLeg.segmentMaximumSpeedLimits` property contains one value for each segment in the leg’s full geometry.
     */
    public static let maximumSpeedLimit = AttributeOptions(rawValue: 1 << 5)

    /**
     Traffic congestion level in numeric form.
     When this attribute is specified, the `RouteLeg.numericCongestionLevels` property contains one value for each segment in the leg’s full geometry.
     This attribute requires `ProfileIdentifier.automobileAvoidingTraffic`. Any other profile identifier produces `nil` for each segment along the route.
     */
    public static let numericCongestionLevel = AttributeOptions(rawValue: 1 << 6)
    
    /**
     Creates an AttributeOptions from the given description strings.
     */
    public init?(descriptions: [String]) {
        var attributeOptions: AttributeOptions = []
        for description in descriptions {
            switch description {
            case "distance":
                attributeOptions.update(with: .distance)
            case "duration":
                attributeOptions.update(with: .expectedTravelTime)
            case "speed":
                attributeOptions.update(with: .speed)
            case "congestion":
                attributeOptions.update(with: .congestionLevel)
            case "maxspeed":
                attributeOptions.update(with: .maximumSpeedLimit)
            case "congestion_numeric":
                attributeOptions.update(with: .numericCongestionLevel)
            case "":
                continue
            default:
                return nil
            }
        }
        self.init(rawValue: attributeOptions.rawValue)
    }
    
    public var description: String {
        var descriptions: [String] = []
        if contains(.distance) {
            descriptions.append("distance")
        }
        if contains(.expectedTravelTime) {
            descriptions.append("duration")
        }
        if contains(.speed) {
            descriptions.append("speed")
        }
        if contains(.congestionLevel) {
            descriptions.append("congestion")
        }
        if contains(.maximumSpeedLimit) {
            descriptions.append("maxspeed")
        }
        if contains(.numericCongestionLevel) {
            descriptions.append("congestion_numeric")
        }
        return descriptions.joined(separator: ",")
    }
}

extension AttributeOptions: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description.components(separatedBy: ",").filter { !$0.isEmpty })
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let descriptions = try container.decode([String].self)
        self = AttributeOptions(descriptions: descriptions)!
    }
}

extension LineString {
    /**
     Returns a string representation of the line string in [Polyline Algorithm Format](https://developers.google.com/maps/documentation/utilities/polylinealgorithm).
     */
    func polylineEncodedString(precision: Double = 1e5) -> String {
        #if canImport(CoreLocation)
        let coordinates = self.coordinates
        #else
        let coordinates = self.coordinates.map { Polyline.LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        #endif
        return encodeCoordinates(coordinates, precision: precision)
    }
}

enum PolyLineString {
    case lineString(_ lineString: LineString)
    case polyline(_ encodedPolyline: String, precision: Double)
    
    init(lineString: LineString, shapeFormat: RouteShapeFormat) {
        switch shapeFormat {
        case .geoJSON:
            self = .lineString(lineString)
        case .polyline, .polyline6:
            let precision = shapeFormat == .polyline6 ? 1e6 : 1e5
            let encodedPolyline = lineString.polylineEncodedString(precision: precision)
            self = .polyline(encodedPolyline, precision: precision)
        }
    }
}

extension PolyLineString: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let options = decoder.userInfo[.options] as? DirectionsOptions
        switch options?.shapeFormat ?? .default {
        case .geoJSON:
            self = .lineString(try container.decode(LineString.self))
        case .polyline, .polyline6:
            let precision = options?.shapeFormat == .polyline6 ? 1e6 : 1e5
            let encodedPolyline = try container.decode(String.self)
            self = .polyline(encodedPolyline, precision: precision)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .lineString(lineString):
            try container.encode(lineString)
        case let .polyline(encodedPolyline, precision: _):
            try container.encode(encodedPolyline)
        }
    }
}

struct LocationCoordinate2DCodable: Codable {
    var latitude: Turf.LocationDegrees
    var longitude: Turf.LocationDegrees
    var decodedCoordinates: Turf.LocationCoordinate2D {
        return Turf.LocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(longitude)
        try container.encode(latitude)
    }
    
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        longitude = try container.decode(Turf.LocationDegrees.self)
        latitude = try container.decode(Turf.LocationDegrees.self)
    }
    
    init(_ coordinate: Turf.LocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }
}

/// The Mapbox access token specified in the main application bundle’s Info.plist.
let defaultAccessToken: String? =
    Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ??
    Bundle.main.object(forInfoDictionaryKey: "MGLMapboxAccessToken") as? String ??
    UserDefaults.standard.string(forKey: "MBXAccessToken")
let defaultApiEndPointURLString = Bundle.main.object(forInfoDictionaryKey: "MGLMapboxAPIBaseURL") as? String



public struct Credentials: Equatable {
    
    /**
    The mapbox access token. You can find this in your Mapbox account dashboard.
     */
    public let accessToken: String?
    
    /**
     The host to reach. defaults to `api.mapbox.com`.
     */
    public let host: URL
    
    /**
     The SKU Token associated with the request. Used for billing.
     */
    public var skuToken: String? {
        #if !os(Linux)
        guard let mbx: AnyClass = NSClassFromString("MBXAccounts"),
              mbx.responds(to: Selector(("serviceSkuToken"))),
              let serviceSkuToken = mbx.value(forKeyPath: "serviceSkuToken") as? String
        else { return nil }

        if mbx.responds(to: Selector(("serviceAccessToken"))) {
            guard let serviceAccessToken = mbx.value(forKeyPath: "serviceAccessToken") as? String,
                  serviceAccessToken == accessToken
            else { return nil }

            return serviceSkuToken
        }
        else {
            return serviceSkuToken
        }
        #else
        return nil
        #endif
    }
    
    /**
     Intialize a new credential.
     
     - parameter accessToken: Optional. An access token to provide. If this value is nil, the SDK will attempt to find a token from your app's `info.plist`.
     - parameter host: Optional. A parameter to pass a custom host. If `nil` is provided, the SDK will attempt to find a host from your app's `info.plist`, and barring that will default to  `https://api.mapbox.com`.
     */
    public init(accessToken token: String? = nil, host: URL? = nil) {
        let accessToken = token ?? defaultAccessToken
        
        precondition(accessToken != nil && !accessToken!.isEmpty, "A Mapbox access token is required. Go to <https://account.mapbox.com/access-tokens/>. In Info.plist, set the MBXAccessToken key to your access token, or use the Directions(accessToken:host:) initializer.")
        self.accessToken = accessToken
        if let host = host {
            self.host = host
        } else if let defaultHostString = defaultApiEndPointURLString, let defaultHost = URL(string: defaultHostString) {
            self.host = defaultHost
        } else {
            self.host = URL(string: "https://api.mapbox.com")!
        }
    }
    
    /**
     :nodoc:
     Attempts to get `host` and `accessToken` from provided URL to create `Credentials` instance.
     
     If it is impossible to extract parameter(s) - default values will be used.
     */
    public init(requestURL url: URL) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let accessToken = components?
            .queryItems?
            .first { $0.name == "access_token" }?
            .value
        components?.path = "/"
        components?.queryItems = nil
        self.init(accessToken: accessToken, host: components?.url)
    }
}

@available(*, deprecated, renamed: "Credentials")
public typealias DirectionsCredentials = Credentials


public struct ProfileIdentifier: Codable, Hashable, RawRepresentable {
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public var rawValue: String
    
    /**
    The returned directions are appropriate for driving or riding a car, truck, or motorcycle.
    
    This profile prioritizes fast routes by preferring high-speed roads like highways. A driving route may use a ferry where necessary.
    */
    public static let automobile: ProfileIdentifier = .init(rawValue: "mapbox/driving")
    
    /**
    The returned directions are appropriate for driving or riding a car, truck, or motorcycle.
    
    This profile avoids traffic congestion based on current traffic data. A driving route may use a ferry where necessary.
    
    Traffic data is available in [a number of countries and territories worldwide](https://docs.mapbox.com/help/how-mapbox-works/directions/#traffic-data). Where traffic data is unavailable, this profile prefers high-speed roads like highways, similar to `ProfileIdentifier.Automobile`.
     
     - note: This profile is not supported by `Isochrones` API.
    */
    public static let automobileAvoidingTraffic: ProfileIdentifier = .init(rawValue: "mapbox/driving-traffic")
    
    /**
    The returned directions are appropriate for riding a bicycle.
    
    This profile prioritizes short, safe routes by avoiding highways and preferring cycling infrastructure, such as bike lanes on surface streets. A cycling route may, where necessary, use other modes of transportation, such as ferries or trains, or require dismounting the bicycle for a distance.
    */
    public static let cycling: ProfileIdentifier = .init(rawValue: "mapbox/cycling")
    
    /**
    The returned directions are appropriate for walking or hiking.
    
    This profile prioritizes short routes, making use of sidewalks and trails where available. A walking route may use other modes of transportation, such as ferries or trains, where necessary.
    */
    public static let walking: ProfileIdentifier = .init(rawValue: "mapbox/walking")
}


@available(*, deprecated, renamed: "ProfileIdentifier")
public typealias MBDirectionsProfileIdentifier = ProfileIdentifier

/**
 Options determining the primary mode of transportation for the routes.
 */
@available(*, deprecated, renamed: "ProfileIdentifier")
public typealias DirectionsProfileIdentifier = ProfileIdentifier

protocol CustomQuickLookConvertible {
    /**
     Returns a [Quick Look–compatible](https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/CustomClassDisplay_in_QuickLook/CH02-std_objects_support/CH02-std_objects_support.html#//apple_ref/doc/uid/TP40014001-CH3-SW19) representation for display in the Xcode debugger.
     */
    func debugQuickLookObject() -> Any?
}

/**
 Returns a URL to an image representation of the given coordinates via the [Mapbox Static Images API](https://docs.mapbox.com/api/maps/#static-images).
 */
func debugQuickLookURL(illustrating shape: LineString, profileIdentifier: ProfileIdentifier = .automobile, accessToken: String? = defaultAccessToken) -> URL? {
    guard let accessToken = accessToken else {
        return nil
    }
    
    let styleIdentifier: String
    let identifierOfLayerAboveOverlays: String
    switch profileIdentifier {
    case .automobileAvoidingTraffic:
        styleIdentifier = "mapbox/navigation-preview-day-v4"
        identifierOfLayerAboveOverlays = "waterway-label"
    case .cycling, .walking:
        styleIdentifier = "mapbox/outdoors-v11"
        identifierOfLayerAboveOverlays = "contour-label"
    default:
        styleIdentifier = "mapbox/streets-v11"
        identifierOfLayerAboveOverlays = "building-number-label"
    }
    let styleIdentifierComponent = "/\(styleIdentifier)/static"
    
    var allowedCharacterSet = CharacterSet.urlPathAllowed
    allowedCharacterSet.remove(charactersIn: "/)")
    let encodedPolyline = shape.polylineEncodedString(precision: 1e5).addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)!
    let overlaysComponent = "/path-10+3802DA-0.6(\(encodedPolyline))"
    
    let path = "/styles/v1\(styleIdentifierComponent)\(overlaysComponent)/auto/680x360@2x"
    
    var components = URLComponents()
    components.queryItems = [
        URLQueryItem(name: "before_layer", value: identifierOfLayerAboveOverlays),
        URLQueryItem(name: "access_token", value: accessToken),
    ]
    
    return URL(string: "\(defaultApiEndPointURLString ?? "https://api.mapbox.com")\(path)?\(components.percentEncodedQuery!)")
}

extension Double {
    func rounded(to precision: Double) -> Double {
        return (self * precision).rounded() / precision
    }
}






extension Array {
    #if !swift(>=4.1)
    func compactMap<ElementOfResult>(_ transform: (Element) throws -> ElementOfResult?) rethrows -> [ElementOfResult] {
        return try flatMap(transform)
    }
    #endif
}

extension Collection {
    /**
     Returns an index set containing the indices that satisfy the given predicate.
     */
    func indices(where predicate: (Element) throws -> Bool) rethrows -> IndexSet {
        return IndexSet(try enumerated().filter { try predicate($0.element) }.map { $0.offset })
    }
}

public class Waypoint: Codable, ForeignMemberContainerClass {
    public var foreignMembers: JSONObject = [:]
    
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case coordinate = "location"
        case coordinateAccuracy
        case targetCoordinate
        case heading
        case headingAccuracy
        case separatesLegs
        case name
        case allowsArrivingOnOppositeSide
        case snappedDistance = "distance"
    }
    
    // MARK: Creating a Waypoint
    
    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        coordinate = try container.decode(LocationCoordinate2DCodable.self, forKey: .coordinate).decodedCoordinates
        
        coordinateAccuracy = try container.decodeIfPresent(LocationAccuracy.self, forKey: .coordinateAccuracy)
        
        targetCoordinate = try container.decodeIfPresent(LocationCoordinate2DCodable.self, forKey: .targetCoordinate)?.decodedCoordinates
        
        heading = try container.decodeIfPresent(LocationDirection.self, forKey: .heading)
        
        headingAccuracy = try container.decodeIfPresent(LocationDirection.self, forKey: .headingAccuracy)
        
        if let separates = try container.decodeIfPresent(Bool.self, forKey: .separatesLegs) {
            separatesLegs = separates
        }
        
        if let allows = try container.decodeIfPresent(Bool.self, forKey: .allowsArrivingOnOppositeSide) {
            allowsArrivingOnOppositeSide = allows
        }
        
        if let name = try container.decodeIfPresent(String.self, forKey: .name),
            !name.isEmpty {
            self.name = name
        } else {
            name = nil
        }
        
        snappedDistance = try container.decodeIfPresent(LocationDistance.self, forKey: .snappedDistance)
        
        try decodeForeignMembers(notKeyedBy: CodingKeys.self, with: decoder)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(LocationCoordinate2DCodable(coordinate), forKey: .coordinate)
        try container.encodeIfPresent(coordinateAccuracy, forKey: .coordinateAccuracy)
        let targetCoordinateCodable = targetCoordinate != nil ? LocationCoordinate2DCodable(targetCoordinate!) : nil
        try container.encodeIfPresent(targetCoordinateCodable, forKey: .targetCoordinate)
        try container.encodeIfPresent(heading, forKey: .heading)
        try container.encodeIfPresent(headingAccuracy, forKey: .headingAccuracy)
        try container.encodeIfPresent(separatesLegs, forKey: .separatesLegs)
        try container.encodeIfPresent(allowsArrivingOnOppositeSide, forKey: .allowsArrivingOnOppositeSide)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(snappedDistance, forKey: .snappedDistance)
        
        try encodeForeignMembers(to: encoder)
    }
    
    /**
     Initializes a new waypoint object with the given geographic coordinate and an optional accuracy and name.
     
     - parameter coordinate: The geographic coordinate of the waypoint.
     - parameter coordinateAccuracy: The maximum distance away from the waypoint that the route may come and still be considered viable. This argument is measured in meters. A negative value means the route may be an indefinite number of meters away from the route and still be considered viable.
        
        It is recommended that the value of this argument be greater than the `horizontalAccuracy` property of a `CLLocation` object obtained from a `CLLocationManager` object. There is a high likelihood that the user may be located some distance away from a navigable road, for instance if the user is currently on a driveway or inside a building.
     - parameter name: The name of the waypoint. This argument does not affect the route but may help you to distinguish one waypoint from another.
     */
    public init(coordinate: LocationCoordinate2D, coordinateAccuracy: LocationAccuracy? = nil, name: String? = nil) {
        self.coordinate = coordinate
        self.coordinateAccuracy = coordinateAccuracy
        self.name = name
    }
    
    #if canImport(CoreLocation)
    #if os(tvOS) || os(watchOS)
    /**
     Initializes a new waypoint object with the given `CLLocation` object and an optional heading value and name.
     
     - note: This initializer is intended for `CLLocation` objects created using the `CLLocation(latitude:longitude:)` initializer. If you intend to use a `CLLocation` object obtained from a `CLLocationManager` object, consider increasing the `horizontalAccuracy` or set it to a negative value to avoid overfitting, since the `Waypoint` class’s `coordinateAccuracy` property represents the maximum allowed deviation from the waypoint. There is a high likelihood that the user may be located some distance away from a navigable road, for instance if the user is currently on a driveway or inside a building.
     
     - parameter location: A `CLLocation` object representing the waypoint’s location. This initializer respects the `CLLocation` class’s `coordinate` and `horizontalAccuracy` properties, converting them into the `coordinate` and `coordinateAccuracy` properties, respectively.
     - parameter heading: A `LocationDirection` value representing the direction from which the route must approach the waypoint in order to be considered viable. This value is stored in the `headingAccuracy` property.
     - parameter name: The name of the waypoint. This argument does not affect the route but may help you to distinguish one waypoint from another.
     */
    public init(location: CLLocation, heading: LocationDirection? = nil, name: String? = nil) {
        coordinate = location.coordinate
        coordinateAccuracy = location.horizontalAccuracy
        if let heading = heading , heading >= 0 {
            self.heading = heading
        }
        self.name = name
    }
    #else
    /**
     Initializes a new waypoint object with the given `CLLocation` object and an optional `CLHeading` object and name.
     
     - note: This initializer is intended for `CLLocation` objects created using the `CLLocation(latitude:longitude:)` initializer. If you intend to use a `CLLocation` object obtained from a `CLLocationManager` object, consider increasing the `horizontalAccuracy` or set it to a negative value to avoid overfitting, since the `Waypoint` class’s `coordinateAccuracy` property represents the maximum allowed deviation from the waypoint. There is a high likelihood that the user may be located some distance away from a navigable road, for instance if the user is currently on a driveway of inside a building.
     
     - parameter location: A `CLLocation` object representing the waypoint’s location. This initializer respects the `CLLocation` class’s `coordinate` and `horizontalAccuracy` properties, converting them into the `coordinate` and `coordinateAccuracy` properties, respectively.
     - parameter heading: A `CLHeading` object representing the direction from which the route must approach the waypoint in order to be considered viable. This initializer respects the `CLHeading` class’s `trueHeading` property or `magneticHeading` property, converting it into the `headingAccuracy` property.
     - parameter name: The name of the waypoint. This argument does not affect the route but may help you to distinguish one waypoint from another.
     */
    public init(location: CLLocation, heading: CLHeading? = nil, name: String? = nil) {
        coordinate = location.coordinate
        coordinateAccuracy = location.horizontalAccuracy
        if let heading = heading {
            self.heading = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        }
        self.name = name
    }
    #endif
    #endif
    
    // MARK: Positioning the Waypoint
    
    /**
     The geographic coordinate of the waypoint.
     */
    public let coordinate: LocationCoordinate2D
    
    /**
     The radius of uncertainty for the waypoint, measured in meters.
     
     For a route to be considered viable, it must enter this waypoint’s circle of uncertainty. The `coordinate` property identifies the center of the circle, while this property indicates the circle’s radius. If the value of this property is negative, a route is considered viable regardless of whether it enters this waypoint’s circle of uncertainty, subject to an undefined maximum distance.
     
     By default, the value of this property is `nil`.
     */
    public var coordinateAccuracy: LocationAccuracy?
    
    /**
     The geographic coordinate of the waypoint’s target.
     The waypoint’s target affects arrival instructions without affecting the route’s shape. For example, a delivery or ride hailing application may specify a waypoint target that represents a drop-off location. The target determines whether the arrival visual and spoken instructions indicate that the destination is “on the left” or “on the right”.
     By default, this property is set to `nil`, meaning the waypoint has no target. This property is ignored on the first waypoint of a `RouteOptions` object, on any waypoint of a `MatchOptions` object, or on any waypoint of a `RouteOptions` object if `DirectionsOptions.includesSteps` is set to `false`.
     This property corresponds to the [`waypoint_targets`](https://docs.mapbox.com/api/navigation/#retrieve-directions) query parameter in the Mapbox Directions and Map Matching APIs.
     */
    public var targetCoordinate: LocationCoordinate2D?
    
    /**
     A Boolean value indicating whether the waypoint may be snapped to a closed road in the resulting `RouteResponse`.
     
     If `true`, the waypoint may be snapped to a road segment that is closed due to a live traffic closure. This property is `false` by default. This property corresponds to the [`snapping_include_closures`](https://docs.mapbox.com/api/navigation/directions/#optional-parameters-for-the-mapboxdriving-traffic-profile) query parameter in the Mapbox Directions API.
     */
    public var allowsSnappingToClosedRoad: Bool = false
    
    /**
     The straight-line distance from the coordinate specified in the query to the location it was snapped to in the resulting `RouteResponse`.
          
     By default, this property is set to `nil`, meaning the waypoint has no snapped distance.
     */
    public var snappedDistance: LocationDistance?
    
    // MARK: Getting the Direction of Approach
    
    /**
     The direction from which a route must approach this waypoint in order to be considered viable.
     
     This property is measured in degrees clockwise from true north. A value of 0 degrees means due north, 90 degrees means due east, 180 degrees means due south, and so on. If the value of this property is negative, a route is considered viable regardless of the direction from which it approaches this waypoint.
     
     If this waypoint is the first waypoint (the source waypoint), the route must start out by heading in the direction specified by this property. You should always set the `headingAccuracy` property in conjunction with this property. If the `headingAccuracy` property is set to `nil`, this property is ignored.
     
     For driving directions, this property can be useful for avoiding a route that begins by going in the direction opposite the current direction of travel. For example, if you know the user is moving eastwardly and the first waypoint is the user’s current location, specifying a heading of 90 degrees and a heading accuracy of 90 degrees for the first waypoint avoids a route that begins with a “head west” instruction.
     
     You should be certain that the user is in motion before specifying a heading and heading accuracy; otherwise, you may be unnecessarily filtering out the best route. For example, suppose the user is sitting in a car parked in a driveway, facing due north, with the garage in front and the street to the rear. In that case, specifying a heading of 0 degrees and a heading accuracy of 90 degrees may result in a route that begins on the back alley or, worse, no route at all. For this reason, it is recommended that you only specify a heading and heading accuracy when automatically recalculating directions due to the user deviating from the route.
     
     By default, the value of this property is `nil`, meaning that a route is considered viable regardless of the direction of approach.
     */
    public var heading: LocationDirection? = nil
    
    /**
     The maximum amount, in degrees, by which a route’s approach to a waypoint may differ from `heading` in either direction in order to be considered viable.
     
     A value of 0 degrees means that the approach must match the specified `heading` exactly – an unlikely scenario. A value of 180 degrees or more means that the approach may be as much as 180 degrees in either direction from the specified `heading`, effectively allowing a candidate route to approach the waypoint from any direction.
     
     If you set the `heading` property, you should set this property to a value such as 90 degrees, to avoid filtering out routes whose approaches differ only slightly from the specified `heading`. Otherwise, if the `heading` property is set to a negative value, this property is ignored.
     
     By default, the value of this property is `nil`, meaning that a route is considered viable regardless of the direction of approach.
     */
    public var headingAccuracy: LocationDirection? = nil
    
    internal var headingDescription: String {
        guard let heading = heading, heading >= 0,
            let accuracy = headingAccuracy, accuracy >= 0 else {
            return ""
        }
        
        return "\(heading.truncatingRemainder(dividingBy: 360)),\(min(accuracy, 180))"
    }
    
    /**
     A Boolean value indicating whether arriving on opposite side is allowed.
     This property has no effect if `DirectionsOptions.includesSteps` is set to `false`.
     This property corresponds to the [`approaches`](https://www.mapbox.com/api-documentation/navigation/#retrieve-directions) query parameter in the Mapbox Directions and Map Matching APIs.
     */
    open var allowsArrivingOnOppositeSide = true
    
    // MARK: Identifying the Waypoint
    
    /**
     The name of the waypoint.
     
     This property does not affect the route, but the name is included in the arrival instruction, to help the user distinguish between multiple destinations. The name can also help you distinguish one waypoint from another in the array of waypoints passed into the completion handler of the `Directions.calculate(_:completionHandler:)` method.
     */
    public var name: String?
    
    // MARK: Separating the Routes Into Legs
    
    /**
     A Boolean value indicating whether the waypoint is significant enough to appear in the resulting routes as a waypoint separating two legs, along with corresponding guidance instructions.
     
     By default, this property is set to `true`, which means that each resulting route will include a leg that ends by arriving at the waypoint as `RouteLeg.destination` and a subsequent leg that begins by departing from the waypoint as `RouteLeg.source`. Otherwise, if this property is set to `false`, a single leg passes through the waypoint without specifically mentioning it. Regardless of the value of this property, each resulting route passes through the location specified by the `coordinate` property, accounting for approach-related properties such as `heading`.
     
     With the Mapbox Directions API, set this property to `false` if you want the waypoint’s location to influence the path that the route follows without attaching any meaning to the waypoint object itself. With the Mapbox Map Matching API, use this property when the `DirectionsOptions.includesSteps` property is `true` or when `coordinates` represents a trace with a high sample rate.
     This property has no effect if `DirectionsOptions.includesSteps` is set to `false`, or if `MatchOptions.waypointIndices` is non-nil.
     This property corresponds to the [`approaches`](https://docs.mapbox.com/api/navigation/#retrieve-directions) query parameter in the Mapbox Directions and Map Matching APIs.
     */
    public var separatesLegs: Bool = true
}

extension Waypoint: Equatable {
    public static func == (lhs: Waypoint, rhs: Waypoint) -> Bool {
        return lhs.coordinate == rhs.coordinate && lhs.name == rhs.name && lhs.coordinateAccuracy == rhs.coordinateAccuracy
    }
}

extension Waypoint: CustomStringConvertible {
    public var description: String {
        return Mirror(reflecting: self).children.compactMap({
            if let label = $0.label {
                return "\(label): \($0.value)"
            }
            
            return ""
        }).joined(separator: "\n")
    }
}

#if canImport(CoreLocation)
extension Waypoint: CustomQuickLookConvertible {
    func debugQuickLookObject() -> Any? {
        return CLLocation(coordinate: targetCoordinate ?? coordinate,
                          altitude: 0,
                          horizontalAccuracy: coordinateAccuracy ?? -1,
                          verticalAccuracy: -1,
                          course: heading ?? -1,
                          speed: -1, timestamp: Date())
    }
}
#endif

let MaximumURLLength = 1024 * 8

/**
 A `RouteShapeFormat` indicates the format of a route or match shape in the raw HTTP response.
 */
public enum RouteShapeFormat: String, Codable {
    /**
     The route’s shape is delivered in [GeoJSON](http://geojson.org/) format.
     This standard format is human-readable and can be parsed straightforwardly, but it is far more verbose than `polyline`.
     */
    case geoJSON = "geojson"
    /**
     The route’s shape is delivered in [encoded polyline algorithm](https://developers.google.com/maps/documentation/utilities/polylinealgorithm) format with 1×10<sup>−5</sup> precision.
     This machine-readable format is considerably more compact than `geoJSON` but less precise than `polyline6`.
     */
    case polyline
    /**
     The route’s shape is delivered in [encoded polyline algorithm](https://developers.google.com/maps/documentation/utilities/polylinealgorithm) format with 1×10<sup>−6</sup> precision.
     This format is an order of magnitude more precise than `polyline`.
     */
    case polyline6
    
    static let `default` = RouteShapeFormat.polyline
}

/**
 A `RouteShapeResolution` indicates the level of detail in a route’s shape, or whether the shape is present at all.
 */
public enum RouteShapeResolution: String, Codable {
    /**
     The route’s shape is omitted.
     Specify this resolution if you do not intend to show the route line to the user or analyze the route line in any way.
     */
    case none = "false"
    /**
     The route’s shape is simplified.
     This resolution considerably reduces the size of the response. The resulting shape is suitable for display at a low zoom level, but it lacks the detail necessary for focusing on individual segments of the route.
     */
    case low = "simplified"
    /**
     The route’s shape is as detailed as possible.
     The resulting shape is equivalent to concatenating the shapes of all the route’s consitituent steps. You can focus on individual segments of this route while faithfully representing the path of the route. If you only intend to show a route overview and do not need to analyze the route line in any way, consider specifying `low` instead to considerably reduce the size of the response.
     */
    case full
}

/**
 A system of units of measuring distances and other quantities.
 */
public enum MeasurementSystem: String, Codable {
    /**
     U.S. customary and British imperial units.
     Distances are measured in miles and feet.
     */
    case imperial

    /**
     The metric system.
     Distances are measured in kilometers and meters.
     */
    case metric
}

@available(*, deprecated, renamed: "DirectionsPriority")
public typealias MBDirectionsPriority = DirectionsPriority

/**
 A number that influences whether a route should prefer or avoid roadways or pathways of a given type.
 */
public struct DirectionsPriority: Hashable, RawRepresentable, Codable {
    public init(rawValue: Double) {
        self.rawValue = rawValue
    }
    
    public var rawValue: Double
    
    /**
     The priority level with which a route avoids a particular type of roadway or pathway.
     */
    static let low = DirectionsPriority(rawValue: -1.0)
    
    /**
     The priority level with which a route neither avoids nor prefers a particular type of roadway or pathway.
     */
    static let medium = DirectionsPriority(rawValue: 0.0)
    
    /**
     The priority level with which a route prefers a particular type of roadway or pathway.
     */
    static let high = DirectionsPriority(rawValue: 1.0)
}

/**
 Options for calculating results from the Mapbox Directions service.
 You do not create instances of this class directly. Instead, create instances of `MatchOptions` or `RouteOptions`.
 */
open class DirectionsOptions: Codable {
    // MARK: Creating a Directions Options Object
    
    /**
     Initializes an options object for routes between the given waypoints and an optional profile identifier.
     Do not call `DirectionsOptions(waypoints:profileIdentifier:)` directly; instead call the corresponding initializer of `RouteOptions` or `MatchOptions`.
     - parameter waypoints: An array of `Waypoint` objects representing locations that the route should visit in chronological order. The array should contain at least two waypoints (the source and destination) and at most 25 waypoints. (Some profiles, such as `ProfileIdentifier.automobileAvoidingTraffic`, [may have lower limits](https://docs.mapbox.com/api/navigation/#directions).)
     - parameter profileIdentifier: A string specifying the primary mode of transportation for the routes. `ProfileIdentifier.automobile` is used by default.
     - parameter queryItems: URL query items to be parsed and applied as configuration to the resulting options.
     */
    required public init(waypoints: [Waypoint], profileIdentifier: ProfileIdentifier? = nil, queryItems: [URLQueryItem]? = nil) {
        self.waypoints = waypoints
        self.profileIdentifier = profileIdentifier ?? .automobile
        
        guard let queryItems = queryItems else {
            return
        }
        
        let mappedQueryItems = Dictionary<String, String>(queryItems.compactMap {
            guard let value = $0.value else { return nil }
            return ($0.name, value)
        },
                   uniquingKeysWith: { (_, latestValue) in
            return latestValue
        })
        
        if let mappedValue = mappedQueryItems[CodingKeys.shapeFormat.stringValue],
           let shapeFormat = RouteShapeFormat(rawValue: mappedValue) {
            self.shapeFormat = shapeFormat
        }
        if let mappedValue = mappedQueryItems[CodingKeys.routeShapeResolution.stringValue],
           let routeShapeResolution = RouteShapeResolution(rawValue: mappedValue) {
            self.routeShapeResolution = routeShapeResolution
        }
        if mappedQueryItems[CodingKeys.includesSteps.stringValue] == "true" {
            self.includesSteps = true
        }
        if let mappedValue = mappedQueryItems[CodingKeys.locale.stringValue] {
            self.locale = Locale(identifier: mappedValue)
        }
        if mappedQueryItems[CodingKeys.includesSpokenInstructions.stringValue] == "true" {
            self.includesSpokenInstructions = true
        }
        if let mappedValue = mappedQueryItems[CodingKeys.distanceMeasurementSystem.stringValue],
           let measurementSystem = MeasurementSystem(rawValue: mappedValue) {
            self.distanceMeasurementSystem = measurementSystem
        }
        if mappedQueryItems[CodingKeys.includesVisualInstructions.stringValue] == "true" {
            self.includesVisualInstructions = true
        }
        if let mappedValue = mappedQueryItems[CodingKeys.attributeOptions.stringValue],
           let attributeOptions = AttributeOptions(descriptions: mappedValue.components(separatedBy: ",")) {
            self.attributeOptions = attributeOptions
        }
        if let mappedValue = mappedQueryItems["waypoints"] {
            let indicies = mappedValue.components(separatedBy: ";").compactMap { Int($0) }
            if !indicies.isEmpty {
                waypoints.enumerated().forEach {
                    $0.element.separatesLegs = indicies.contains($0.offset)
                }
            }
        }
        
        let waypointsData = [mappedQueryItems["approaches"]?.components(separatedBy: ";"),
                             mappedQueryItems["bearings"]?.components(separatedBy: ";"),
                             mappedQueryItems["radiuses"]?.components(separatedBy: ";"),
                             mappedQueryItems["waypoint_names"]?.components(separatedBy: ";"),
                             mappedQueryItems["snapping_include_closures"]?.components(separatedBy: ";")
        ] as [[String]?]
        
        let getElement: ((_ array: [String]?, _ index: Int) -> String?) = { array, index in
            if array?.count ?? -1 > index {
                return array?[index]
            }
            return nil
        }
        
        waypoints.enumerated().forEach {
            if let approach = getElement(waypointsData[0], $0.offset) {
                $0.element.allowsArrivingOnOppositeSide = approach == "unrestricted" ? true : false
            }
            
            if let descriptions = getElement(waypointsData[1], $0.offset)?.components(separatedBy: ",") {
                $0.element.heading = LocationDirection(descriptions.first!)
                $0.element.headingAccuracy = LocationDirection(descriptions.last!)
            }
            
            if let accuracy = getElement(waypointsData[2], $0.offset) {
                $0.element.coordinateAccuracy = LocationAccuracy(accuracy)
            }
            
            if let snaps = getElement(waypointsData[4], $0.offset) {
                $0.element.allowsSnappingToClosedRoad = snaps == "true"
            }
        }
        
        waypoints.filter { $0.separatesLegs }.enumerated().forEach {
            if let name = getElement(waypointsData[3], $0.offset) {
                $0.element.name = name
            }
        }
    }
    
    /**
     Creates new options object by deserializing given `url`
     
     Initialization fails if it is unable to extract `waypoints` list and `profileIdentifier`. If other properties are failed to decode - it will just skip them.
     
     - parameter url: An URL, used to make a route request.
     */
    public convenience init?(url: URL) {
        guard url.pathComponents.count >= 3 else {
            return nil
        }
        
        let waypointsString = url.lastPathComponent.replacingOccurrences(of: ".json", with: "")
        let waypoints: [Waypoint] = waypointsString.components(separatedBy: ";").compactMap {
            let coordinates = $0.components(separatedBy: ",")
            guard coordinates.count == 2,
                  let latitudeString = coordinates.last,
                  let longitudeString = coordinates.first,
                  let latitude = LocationDegrees(latitudeString),
                  let longitude = LocationDegrees(longitudeString) else {
                      return nil
            }
            return Waypoint(coordinate: .init(latitude: latitude,
                                              longitude: longitude))
        }
            
        guard waypoints.count >= 2 else {
            return nil
        }
        
        let profileIdentifier = ProfileIdentifier(rawValue: url.pathComponents.dropLast().suffix(2).joined(separator: "/"))
        
        self.init(waypoints: waypoints,
                  profileIdentifier: profileIdentifier,
                  queryItems: URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems)
    }
    
    
    private enum CodingKeys: String, CodingKey {
        case waypoints
        case profileIdentifier = "profile"
        case includesSteps = "steps"
        case shapeFormat = "geometries"
        case routeShapeResolution = "overview"
        case attributeOptions = "annotations"
        case locale = "language"
        case includesSpokenInstructions = "voice_instructions"
        case distanceMeasurementSystem = "voice_units"
        case includesVisualInstructions = "banner_instructions"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(waypoints, forKey: .waypoints)
        try container.encode(profileIdentifier, forKey: .profileIdentifier)
        try container.encode(includesSteps, forKey: .includesSteps)
        try container.encode(shapeFormat, forKey: .shapeFormat)
        try container.encode(routeShapeResolution, forKey: .routeShapeResolution)
        try container.encode(attributeOptions, forKey: .attributeOptions)
        try container.encode(locale.identifier, forKey: .locale)
        try container.encode(includesSpokenInstructions, forKey: .includesSpokenInstructions)
        try container.encode(distanceMeasurementSystem, forKey: .distanceMeasurementSystem)
        try container.encode(includesVisualInstructions, forKey: .includesVisualInstructions)
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        waypoints = try container.decode([Waypoint].self, forKey: .waypoints)
        profileIdentifier = try container.decode(ProfileIdentifier.self, forKey: .profileIdentifier)
        includesSteps = try container.decode(Bool.self, forKey: .includesSteps)
        shapeFormat = try container.decode(RouteShapeFormat.self, forKey: .shapeFormat)
        routeShapeResolution = try container.decode(RouteShapeResolution.self, forKey: .routeShapeResolution)
        attributeOptions = try container.decode(AttributeOptions.self, forKey: .attributeOptions)
        let identifier = try container.decode(String.self, forKey: .locale)
        locale = Locale(identifier: identifier)
        includesSpokenInstructions = try container.decode(Bool.self, forKey: .includesSpokenInstructions)
        distanceMeasurementSystem = try container.decode(MeasurementSystem.self, forKey: .distanceMeasurementSystem)
        includesVisualInstructions = try container.decode(Bool.self, forKey: .includesVisualInstructions)
    }
    
    // MARK: Specifying the Path of the Route
    
    /**
     An array of `Waypoint` objects representing locations that the route should visit in chronological order.
     A waypoint object indicates a location to visit, as well as an optional heading from which to approach the location.
     The array should contain at least two waypoints (the source and destination) and at most 25 waypoints.
     */
    open var waypoints: [Waypoint]
    
    /**
     The waypoints that separate legs.
     */
    var legSeparators: [Waypoint] {
        var waypoints = self.waypoints
        let source = waypoints.removeFirst()
        let destination = waypoints.removeLast()
        return [source] + waypoints.filter { $0.separatesLegs } + [destination]
    }
    
    // MARK: Specifying the Mode of Transportation
    
    /**
     A string specifying the primary mode of transportation for the routes.
     The default value of this property is `ProfileIdentifier.automobile`, which specifies driving directions.
     */
    open var profileIdentifier: ProfileIdentifier

    // MARK: Specifying the Response Format
    /**
     A Boolean value indicating whether `RouteStep` objects should be included in the response.
     If the value of this property is `true`, the returned route contains turn-by-turn instructions. Each returned `Route` object contains one or more `RouteLeg` object that in turn contains one or more `RouteStep` objects. On the other hand, if the value of this property is `false`, the `RouteLeg` objects contain no `RouteStep` objects.
     If you only want to know the distance or estimated travel time to a destination, set this property to `false` to minimize the size of the response and the time it takes to calculate the response. If you need to display turn-by-turn instructions, set this property to `true`.
     The default value of this property is `false`.
     */
    open var includesSteps = false

    /**
     Format of the data from which the shapes of the returned route and its steps are derived.
     This property has no effect on the returned shape objects, although the choice of format can significantly affect the size of the underlying HTTP response.
     The default value of this property is `polyline`.
     */
    open var shapeFormat = RouteShapeFormat.polyline

    /**
     Resolution of the shape of the returned route.
     This property has no effect on the shape of the returned route’s steps.
     The default value of this property is `low`, specifying a low-resolution route shape.
     */
    open var routeShapeResolution = RouteShapeResolution.low

    /**
     AttributeOptions for the route. Any combination of `AttributeOptions` can be specified.
     By default, no attribute options are specified. It is recommended that `routeShapeResolution` be set to `.full`.
     */
    open var attributeOptions: AttributeOptions = []

    /**
     The locale in which the route’s instructions are written.
     If you use the MapboxDirections framework with the Mapbox Directions API or Map Matching API, this property affects the sentence contained within the `RouteStep.instructions` property, but it does not affect any road names contained in that property or other properties such as `RouteStep.name`.
     The Directions API can provide instructions in [a number of languages](https://docs.mapbox.com/api/navigation/#instructions-languages). Set this property to `Bundle.main.preferredLocalizations.first` or `Locale.autoupdatingCurrent` to match the application’s language or the system language, respectively.
     By default, this property is set to the current system locale.
     */
    open var locale = Locale.current {
        didSet {
            self.distanceMeasurementSystem = locale.usesMetricSystem ? .metric : .imperial
        }
    }

    /**
     A Boolean value indicating whether each route step includes an array of `SpokenInstructions`.
     If this option is set to true, the `RouteStep.instructionsSpokenAlongStep` property is set to an array of `SpokenInstructions`.
     */
    open var includesSpokenInstructions = false

    /**
     The measurement system used in spoken instructions included in route steps.
     If the `includesSpokenInstructions` property is set to `true`, this property determines the units used for measuring the distance remaining until an upcoming maneuver. If the `includesSpokenInstructions` property is set to `false`, this property has no effect.
     You should choose a measurement system appropriate for the current region. You can also allow the user to indicate their preferred measurement system via a setting.
     */
    open var distanceMeasurementSystem: MeasurementSystem = Locale.current.usesMetricSystem ? .metric : .imperial

    /**
     If true, each `RouteStep` will contain the property `visualInstructionsAlongStep`.
     `visualInstructionsAlongStep` contains an array of `VisualInstruction` objects used for visually conveying information about a given `RouteStep`.
     */
    open var includesVisualInstructions = false
    
    /**
     The time immediately before a `Directions` object fetched this result.
     
     If you manually start fetching a task returned by `Directions.url(forCalculating:)`, this property is set to `nil`; use the `URLSessionTaskTransactionMetrics.fetchStartDate` property instead. This property may also be set to `nil` if you create this result from a JSON object or encoded object.
     
     This property does not persist after encoding and decoding.
     */
    open var fetchStartDate: Date?
    

    
    // MARK: Getting the Request URL
    
    /**
     The path of the request URL, specifying service name, version and profile.
     
     The query items are included in the URL of a GET request or the body of a POST request.
     */
    var abridgedPath: String {
        assertionFailure("abridgedPath should be overriden by subclass")
        return ""
    }
    
    /**
     The path of the request URL, not including the hostname or any parameters.
     */
    var path: String {
        guard let coordinates = coordinates else {
            assertionFailure("No query")
            return ""
        }
        
        if waypoints.count < 2 {
            return "\(abridgedPath)"
        }
        
        return "\(abridgedPath)/\(coordinates)"
    }
    
    /**
     An array of URL query items (parameters) to include in an HTTP request.
     
     The query items are included in the URL of a GET request or the body of a POST request.
     */
    open var urlQueryItems: [URLQueryItem] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "geometries", value: shapeFormat.rawValue),
            URLQueryItem(name: "overview", value: routeShapeResolution.rawValue),
            
            URLQueryItem(name: "steps", value: String(includesSteps)),
            URLQueryItem(name: "language", value: locale.identifier)
        ]

        let mustArriveOnDrivingSide = !waypoints.filter { !$0.allowsArrivingOnOppositeSide }.isEmpty
        if mustArriveOnDrivingSide {
            let approaches = waypoints.map { $0.allowsArrivingOnOppositeSide ? "unrestricted" : "curb" }
            queryItems.append(URLQueryItem(name: "approaches", value: approaches.joined(separator: ";")))
        }

        if includesSpokenInstructions {
            queryItems.append(URLQueryItem(name: "voice_instructions", value: String(includesSpokenInstructions)))
            queryItems.append(URLQueryItem(name: "voice_units", value: distanceMeasurementSystem.rawValue))
        }

        if includesVisualInstructions {
            queryItems.append(URLQueryItem(name: "banner_instructions", value: String(includesVisualInstructions)))
        }

        // Include headings and heading accuracies if any waypoint has a nonnegative heading.
        if let bearings = self.bearings {
            queryItems.append(URLQueryItem(name: "bearings", value: bearings))
        }

        // Include location accuracies if any waypoint has a nonnegative coordinate accuracy.
        if let radiuses = self.radiuses {
            queryItems.append(URLQueryItem(name: "radiuses", value: radiuses))
        }

        if let annotations = self.annotations {
            queryItems.append((URLQueryItem(name: "annotations", value: annotations)))
        }

        if let waypointIndices = self.waypointIndices {
            queryItems.append(URLQueryItem(name: "waypoints", value: waypointIndices))
        }

        if let names = self.waypointNames {
            queryItems.append(URLQueryItem(name: "waypoint_names", value: names))
        }
        
        if let snapping = self.closureSnapping {
            queryItems.append(URLQueryItem(name: "snapping_include_closures", value: snapping))
        }
        
        return queryItems
    }
    
    
    var bearings: String? {
        guard waypoints.contains(where: { $0.heading ?? -1 >= 0 }) else {
            return nil
        }
        return waypoints.map({ $0.headingDescription }).joined(separator: ";")
    }
    
    var radiuses: String? {
        guard waypoints.contains(where: { $0.coordinateAccuracy ?? -1 >= 0 }) else {
            return nil
        }
        
        let accuracies = self.waypoints.map { (waypoint) -> String in
            guard let accuracy = waypoint.coordinateAccuracy, accuracy >= 0 else {
                return "unlimited"
            }
            return String(accuracy)
        }
        return accuracies.joined(separator: ";")
    }
    
    private var approaches: String? {
        if waypoints.filter( { !$0.allowsArrivingOnOppositeSide }).isEmpty {
            return nil
        }
        return waypoints.map { $0.allowsArrivingOnOppositeSide ? "unrestricted" : "curb" }.joined(separator: ";")
    }
    
    private var annotations: String? {
        if attributeOptions.isEmpty {
            return nil
        }
        return attributeOptions.description
    }
    
    private var waypointIndices: String? {
        var waypointIndices = waypoints.indices { $0.separatesLegs }
        waypointIndices.insert(waypoints.startIndex)
        waypointIndices.insert(waypoints.endIndex - 1)
        
        guard waypointIndices.count < waypoints.count else {
            return nil
        }
        return waypointIndices.map(String.init(describing:)).joined(separator: ";")
    }
    
    private var waypointNames: String? {
        if waypoints.compactMap({ $0.name }).isEmpty {
            return nil
        }
        return legSeparators.map({ $0.name ?? "" }).joined(separator: ";")
    }
    
    internal var coordinates: String? {
        return waypoints.map { $0.coordinate.requestDescription }.joined(separator: ";")
    }
    
    internal var closureSnapping: String? {
        guard waypoints.contains(where: \.allowsSnappingToClosedRoad) else {
            return nil
        }
        return waypoints.map { $0.allowsSnappingToClosedRoad ? "true": ""}.joined(separator: ";")
    }

    internal var httpBody: String {
        guard let coordinates = self.coordinates else { return "" }
        var components = URLComponents()
        components.queryItems = urlQueryItems + [
            URLQueryItem(name: "coordinates", value: coordinates),
        ]
        return components.percentEncodedQuery ?? ""
    }
    
}

extension DirectionsOptions: Equatable {
    public static func == (lhs: DirectionsOptions, rhs: DirectionsOptions) -> Bool {
        return lhs.waypoints == rhs.waypoints &&
            lhs.profileIdentifier == rhs.profileIdentifier &&
            lhs.includesSteps == rhs.includesSteps &&
            lhs.shapeFormat == rhs.shapeFormat &&
            lhs.routeShapeResolution == rhs.routeShapeResolution &&
            lhs.attributeOptions == rhs.attributeOptions &&
            lhs.locale.identifier == rhs.locale.identifier &&
            lhs.includesSpokenInstructions == rhs.includesSpokenInstructions &&
            lhs.distanceMeasurementSystem == rhs.distanceMeasurementSystem &&
            lhs.includesVisualInstructions == rhs.includesVisualInstructions
    }
}


public extension VisualInstruction {
    /**
     A unit of information displayed to the user as part of a `VisualInstruction`.
     */
    enum Component {
        /**
         The component separates two other destination components.
         
         If the two adjacent components are both displayed as images, you can hide this delimiter component.
         */
        case delimiter(text: TextRepresentation)
        
        /**
         The component bears the name of a place or street.
         */
        case text(text: TextRepresentation)
        
        /**
         The component is an image, such as a [route marker](https://en.wikipedia.org/wiki/Highway_shield), with a fallback text representation.
         
         - parameter image: The component’s preferred image representation.
         - parameter alternativeText: The component’s alternative text representation. Use this representation if the image representation is unavailable or unusable, but consider formatting the text in a special way to distinguish it from an ordinary `.text` component.
         */
        case image(image: ImageRepresentation, alternativeText: TextRepresentation)

        /**
         The component is an image of a zoomed junction, with a fallback text representation.
         */
        case guidanceView(image: GuidanceViewImageRepresentation, alternativeText: TextRepresentation)
        
        /**
         The component contains the localized word for “Exit”.
         
         This component may appear before or after an `.exitCode` component, depending on the language. You can hide this component if the adjacent `.exitCode` component has an obvious exit-number appearance, for example with an accompanying [motorway exit icon](https://commons.wikimedia.org/wiki/File:Sinnbild_Autobahnausfahrt.svg).
         */
        case exit(text: TextRepresentation)
        
        /**
         The component contains an exit number.
         
         You can hide the adjacent `.exit` component in favor of giving this component an obvious exit-number appearance, for example by pairing it with a [motorway exit icon](https://commons.wikimedia.org/wiki/File:Sinnbild_Autobahnausfahrt.svg).
         */
        case exitCode(text: TextRepresentation)
        
        /**
         A component that represents a turn lane or through lane at the approach to an intersection.
         
         - parameter indications: The direction or directions of travel that the lane is reserved for.
         - parameter isUsable: Whether the user can use this lane to continue along the current route.
         - parameter preferredDirection: Which of the `indications` is applicable to the current route when there is more than one
         */
        case lane(indications: LaneIndication, isUsable: Bool, preferredDirection: ManeuverDirection?)
    }
}

public extension VisualInstruction.Component {
    /**
     A textual representation of a visual instruction component.
     */
    struct TextRepresentation: Equatable {
        /**
         Initializes a text representation bearing the given abbreviatable text.
         */
        public init(text: String, abbreviation: String?, abbreviationPriority: Int?) {
            self.text = text
            self.abbreviation = abbreviation
            self.abbreviationPriority = abbreviationPriority
        }
        
        /**
         The plain text representation of this component.
         */
        public let text: String
        
        /**
         An abbreviated representation of the `text` property.
         */
        public let abbreviation: String?
        
        /**
         The priority for which the component should be abbreviated.
         
         A component with a lower abbreviation priority value should be abbreviated before a component with a higher abbreviation priority value.
         */
        public let abbreviationPriority: Int?
    }

    /**
     An image representation of a visual instruction component.
     */
    struct ImageRepresentation: Equatable {
        /**
         File formats of visual instruction component images.
         */
        public enum Format: String {
            /// Portable Network Graphics (PNG)
            case png
            /// Scalable Vector Graphics (SVG)
            case svg
        }
        
        /**
         Initializes an image representation bearing the image at the given base URL.
         */
        public init(imageBaseURL: URL?, shield: ShieldRepresentation? = nil) {
            self.imageBaseURL = imageBaseURL
            self.shield = shield
        }
        
        /**
         The URL whose path is the prefix of all the possible URLs returned by `imageURL(scale:format:)`.
         */
        public let imageBaseURL: URL?
        
        /**
         Optionally, a structured image representation for displaying a [highway shield](https://en.wikipedia.org/wiki/Highway_shield).
         */
        public let shield: ShieldRepresentation?
        
        /**
         Returns a remote URL to the image file that represents the component.
         
         - parameter scale: The image’s scale factor. If this argument is unspecified, the current screen’s native scale factor is used. Only the values 1, 2, and 3 are currently supported.
         - parameter format: The file format of the image. If this argument is unspecified, PNG is used.
         - returns: A remote URL to the image.
         */
        public func imageURL(scale: Scale? = nil, format: Format = .png) -> URL? {
            guard let imageBaseURL = imageBaseURL,
                var imageURLComponents = URLComponents(url: imageBaseURL, resolvingAgainstBaseURL: false) else {
                return nil
            }
            imageURLComponents.path += "@\(Int(scale ?? ImageRepresentation.currentScale))x.\(format)"
            return imageURLComponents.url
        }
        
        /**
         Returns the current screen’s native scale factor.
         */
        static var currentScale: Scale {
            let scale: Scale
            #if os(iOS) || os(tvOS)
            scale = UIScreen.main.scale
            #elseif os(macOS)
            scale = NSScreen.main?.backingScaleFactor ?? 1
            #elseif os(watchOS)
            scale = WKInterfaceDevice.current().screenScale
            #elseif os(Linux)
            scale = 1
            #endif
            return scale
        }
    }
    
    /**
     A mapbox shield representation of a visual instruction component.
     */
    struct ShieldRepresentation: Equatable, Codable {
        /**
         Initializes a mapbox shield with the given name, text color, and display ref.
         */
        public init(baseURL: URL, name: String, textColor: String, text: String) {
            self.baseURL = baseURL
            self.name = name
            self.textColor = textColor
            self.text = text
        }
        
        /**
         Base URL to query the styles endpoint.
         */
        public let baseURL: URL

        /**
         String indicating the name of the route shield.
         */
        public let name: String
        
        /**
         String indicating the color of the text to be rendered on the route shield.
         */
        public let textColor: String
        
        /**
         String indicating the route reference code that will be displayed on the shield.
         */
        public let text: String
        
        private enum CodingKeys: String, CodingKey {
            case baseURL = "base_url"
            case name
            case textColor = "text_color"
            case text = "display_ref"
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            baseURL = try container.decode(URL.self, forKey: .baseURL)
            name = try container.decode(String.self, forKey: .name)
            textColor = try container.decode(String.self, forKey: .textColor)
            text = try container.decode(String.self, forKey: .text)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(baseURL, forKey: .baseURL)
            try container.encode(name, forKey: .name)
            try container.encode(textColor, forKey: .textColor)
            try container.encode(text, forKey: .text)
        }
    }
}

/// A guidance view image representation of a visual instruction component.
public struct GuidanceViewImageRepresentation: Equatable {
    /**
     Initializes an image representation bearing the image at the given URL.
     */
    public init(imageURL: URL?) {
        self.imageURL = imageURL
    }

    /**
     Returns a remote URL to the image file that represents the component.
     */
    public let imageURL: URL?
    
}

extension VisualInstruction.Component: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind = "type"
        case text
        case abbreviatedText = "abbr"
        case abbreviatedTextPriority = "abbr_priority"
        case imageBaseURL
        case imageURL
        case shield = "mapbox_shield"
        case directions
        case isActive = "active"
        case activeDirection = "active_direction"
    }
    
    enum Kind: String, Codable {
        case delimiter
        case text
        case image = "icon"
        case guidanceView = "guidance-view"
        case exit
        case exitCode = "exit-number"
        case lane
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? container.decode(Kind.self, forKey: .kind)) ?? .text
        
        if kind == .lane {
            let indications = try container.decode(LaneIndication.self, forKey: .directions)
            let isUsable = try container.decode(Bool.self, forKey: .isActive)
            let preferredDirection = try container.decodeIfPresent(ManeuverDirection.self, forKey: .activeDirection)
            self = .lane(indications: indications, isUsable: isUsable, preferredDirection: preferredDirection)
            return
        }
        
        let text = try container.decode(String.self, forKey: .text)
        let abbreviation = try container.decodeIfPresent(String.self, forKey: .abbreviatedText)
        let abbreviationPriority = try container.decodeIfPresent(Int.self, forKey: .abbreviatedTextPriority)
        let textRepresentation = TextRepresentation(text: text, abbreviation: abbreviation, abbreviationPriority: abbreviationPriority)
        
        switch kind {
        case .delimiter:
            self = .delimiter(text: textRepresentation)
        case .text:
            self = .text(text: textRepresentation)
        case .image:
            var imageBaseURL: URL?
            if let imageBaseURLString = try container.decodeIfPresent(String.self, forKey: .imageBaseURL) {
                imageBaseURL = URL(string: imageBaseURLString)
            }
            let shieldRepresentation = try container.decodeIfPresent(ShieldRepresentation.self, forKey: .shield)
            let imageRepresentation = ImageRepresentation(imageBaseURL: imageBaseURL, shield: shieldRepresentation)
            self = .image(image: imageRepresentation, alternativeText: textRepresentation)
        case .exit:
            self = .exit(text: textRepresentation)
        case .exitCode:
            self = .exitCode(text: textRepresentation)
        case .lane:
            preconditionFailure("Lane component should have been initialized before decoding text")
        case .guidanceView:
            var imageURL: URL?
            if let imageURLString = try container.decodeIfPresent(String.self, forKey: .imageURL) {
                imageURL = URL(string: imageURLString)
            }
            let guidanceViewImageRepresentation = GuidanceViewImageRepresentation(imageURL: imageURL)
            self = .guidanceView(image: guidanceViewImageRepresentation, alternativeText: textRepresentation)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        let textRepresentation: TextRepresentation?
        switch self {
        case .delimiter(let text):
            try container.encode(Kind.delimiter, forKey: .kind)
            textRepresentation = text
        case .text(let text):
            try container.encode(Kind.text, forKey: .kind)
            textRepresentation = text
        case .image(let image, let alternativeText):
            try container.encode(Kind.image, forKey: .kind)
            textRepresentation = alternativeText
            try container.encodeIfPresent(image.imageBaseURL?.absoluteString, forKey: .imageBaseURL)
            try container.encodeIfPresent(image.shield, forKey: .shield)
        case .exit(let text):
            try container.encode(Kind.exit, forKey: .kind)
            textRepresentation = text
        case .exitCode(let text):
            try container.encode(Kind.exitCode, forKey: .kind)
            textRepresentation = text
        case .lane(let indications, let isUsable, let preferredDirection):
            try container.encode(Kind.lane, forKey: .kind)
            textRepresentation = .init(text: "", abbreviation: nil, abbreviationPriority: nil)
            try container.encode(indications, forKey: .directions)
            try container.encode(isUsable, forKey: .isActive)
            try container.encodeIfPresent(preferredDirection, forKey: .activeDirection)
        case .guidanceView(let image, let alternativeText):
            try container.encode(Kind.guidanceView, forKey: .kind)
            textRepresentation = alternativeText
            try container.encodeIfPresent(image.imageURL?.absoluteString, forKey: .imageURL)
        }
        
        if let textRepresentation = textRepresentation {
            try container.encodeIfPresent(textRepresentation.text, forKey: .text)
            try container.encodeIfPresent(textRepresentation.abbreviation, forKey: .abbreviatedText)
            try container.encodeIfPresent(textRepresentation.abbreviationPriority, forKey: .abbreviatedTextPriority)
        }
    }
}

extension VisualInstruction.Component: Equatable {
    public static func ==(lhs: VisualInstruction.Component, rhs: VisualInstruction.Component) -> Bool {
        switch (lhs, rhs) {
        case (let .delimiter(lhsText), let .delimiter(rhsText)),
             (let .text(lhsText), let .text(rhsText)),
             (let .exit(lhsText), let .exit(rhsText)),
             (let .exitCode(lhsText), let .exitCode(rhsText)):
            return lhsText == rhsText
        case (let .image(lhsURL, lhsAlternativeText),
              let .image(rhsURL, rhsAlternativeText)):
            return lhsURL == rhsURL
                && lhsAlternativeText == rhsAlternativeText
        case (let .guidanceView(lhsURL, lhsAlternativeText),
              let .guidanceView(rhsURL, rhsAlternativeText)):
            return lhsURL == rhsURL
                && lhsAlternativeText == rhsAlternativeText
        case (let .lane(lhsIndications, lhsIsUsable, lhsPreferredDirection),
              let .lane(rhsIndications, rhsIsUsable, rhsPreferredDirection)):
            return lhsIndications == rhsIndications
                && lhsIsUsable == rhsIsUsable
                && lhsPreferredDirection == rhsPreferredDirection
        case (.delimiter, _),
             (.text, _),
             (.image, _),
             (.exit, _),
             (.exitCode, _),
             (.guidanceView, _),
             (.lane, _):
            return false
        }
    }
}


open class VisualInstruction: Codable, ForeignMemberContainerClass {
    public var foreignMembers: JSONObject = [:]
    
    // MARK: Creating a Visual Instruction
    
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case text
        case maneuverType = "type"
        case maneuverDirection = "modifier"
        case components
        case finalHeading = "degrees"
    }

    /**
     Initializes a new visual instruction banner object that displays the given information.
     */
    public init(text: String?, maneuverType: ManeuverType?, maneuverDirection: ManeuverDirection?, components: [Component], degrees: LocationDegrees? = nil) {
        self.text = text
        self.maneuverType = maneuverType
        self.maneuverDirection = maneuverDirection
        self.components = components
        self.finalHeading = degrees
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(maneuverType, forKey: .maneuverType)
        try container.encodeIfPresent(maneuverDirection, forKey: .maneuverDirection)
        try container.encode(components, forKey: .components)
        try container.encodeIfPresent(finalHeading, forKey: .finalHeading)
        
        try encodeForeignMembers(to: encoder)
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        maneuverType = try container.decodeIfPresent(ManeuverType.self, forKey: .maneuverType)
        maneuverDirection = try container.decodeIfPresent(ManeuverDirection.self, forKey: .maneuverDirection)
        components = try container.decode([Component].self, forKey: .components)
        finalHeading = try container.decodeIfPresent(LocationDegrees.self, forKey: .finalHeading)
        
        try decodeForeignMembers(notKeyedBy: CodingKeys.self, with: decoder)
    }
    
    // MARK: Displaying the Instruction Text
    
    /**
     A plain text representation of the instruction.
     
     This property is set to `nil` when the `text` property in the Mapbox Directions API response is an empty string.
     */
    public let text: String?

    /**
     A structured representation of the instruction.
     */
    public let components: [Component]
    
    // MARK: Displaying a Maneuver Image
    /**
     The type of maneuver required for beginning the step described by the visual instruction.
     */
    public var maneuverType: ManeuverType?

    /**
     Additional directional information to clarify the maneuver type.
     */
    public var maneuverDirection: ManeuverDirection?

    /**
     The heading at which the user exits a roundabout (traffic circle or rotary).
     This property is measured in degrees clockwise relative to the user’s initial heading. A value of 180° means continuing through the roundabout without changing course, whereas a value of 0° means traversing the entire roundabout back to the entry point.
     This property is only relevant if the `maneuverType` is any of the following values: `ManeuverType.takeRoundabout`, `ManeuverType.takeRotary`, `ManeuverType.turnAtRoundabout`, `ManeuverType.exitRoundabout`, or `ManeuverType.exitRotary`.
     */
    public var finalHeading: LocationDegrees?
}

extension VisualInstruction: Equatable {
    public static func == (lhs: VisualInstruction, rhs: VisualInstruction) -> Bool {
        return lhs.text == rhs.text &&
            lhs.maneuverType == rhs.maneuverType &&
            lhs.maneuverDirection == rhs.maneuverDirection &&
            lhs.components == rhs.components &&
            lhs.finalHeading == rhs.finalHeading
    }
}



internal extension CodingUserInfoKey {
    static let drivingSide = CodingUserInfoKey(rawValue: "drivingSide")!
}

/**
 A visual instruction banner contains all the information necessary for creating a visual cue about a given `RouteStep`.
 */
open class VisualInstructionBanner: Codable, ForeignMemberContainerClass {
    public var foreignMembers: JSONObject = [:]
    
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case distanceAlongStep = "distanceAlongGeometry"
        case primaryInstruction = "primary"
        case secondaryInstruction = "secondary"
        case tertiaryInstruction = "sub"
        case quaternaryInstruction = "view"
        case drivingSide
    }
    
    // MARK: Creating a Visual Instruction Banner
    
    /**
     Initializes a visual instruction banner with the given instructions.
     */
    public init(distanceAlongStep: LocationDistance, primary: VisualInstruction, secondary: VisualInstruction?, tertiary: VisualInstruction?, quaternary: VisualInstruction?, drivingSide: DrivingSide) {
        self.distanceAlongStep = distanceAlongStep
        primaryInstruction = primary
        secondaryInstruction = secondary
        tertiaryInstruction = tertiary
        quaternaryInstruction = quaternary
        self.drivingSide = drivingSide
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(distanceAlongStep, forKey: .distanceAlongStep)
        try container.encode(primaryInstruction, forKey: .primaryInstruction)
        try container.encodeIfPresent(secondaryInstruction, forKey: .secondaryInstruction)
        try container.encodeIfPresent(tertiaryInstruction, forKey: .tertiaryInstruction)
        try container.encodeIfPresent(quaternaryInstruction, forKey: .quaternaryInstruction)
        try container.encode(drivingSide, forKey: .drivingSide)
        
        try encodeForeignMembers(to: encoder)
    }
    
    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        distanceAlongStep = try container.decode(LocationDistance.self, forKey: .distanceAlongStep)
        primaryInstruction = try container.decode(VisualInstruction.self, forKey: .primaryInstruction)
        secondaryInstruction = try container.decodeIfPresent(VisualInstruction.self, forKey: .secondaryInstruction)
        tertiaryInstruction = try container.decodeIfPresent(VisualInstruction.self, forKey: .tertiaryInstruction)
        quaternaryInstruction = try container.decodeIfPresent(VisualInstruction.self, forKey: .quaternaryInstruction)
        if let directlyEncoded = try container.decodeIfPresent(DrivingSide.self, forKey: .drivingSide) {
            drivingSide = directlyEncoded
        } else {
            drivingSide = .default
        }
        
        try decodeForeignMembers(notKeyedBy: CodingKeys.self, with: decoder)
    }
    
    // MARK: Timing When to Display the Banner
    
    /**
     The distance at which the visual instruction should be shown, measured in meters from the beginning of the step.
     */
    public let distanceAlongStep: LocationDistance
    
    // MARK: Getting the Instructions to Display
    
    /**
     The most important information to convey to the user about the `RouteStep`.
     */
    public let primaryInstruction: VisualInstruction

    /**
     Less important details about the `RouteStep`.
     */
    public let secondaryInstruction: VisualInstruction?

    /**
     A visual instruction that is presented simultaneously to provide information about an additional maneuver that occurs in rapid succession.
     This instruction could either contain the visual layout information or the lane information about the upcoming maneuver.
     */
    public let tertiaryInstruction: VisualInstruction?
    
    /**
     A visual instruction that is presented to provide information about the incoming junction.
     This instruction displays a zoomed image of incoming junction.
     */
    public let quaternaryInstruction: VisualInstruction?
    
    // MARK: Respecting Regional Driving Rules
    
    /**
     Which side of a bidirectional road the driver should drive on, also known as the rule of the road.
     */
    public var drivingSide: DrivingSide
}

extension VisualInstructionBanner: Equatable {
    public static func == (lhs: VisualInstructionBanner, rhs: VisualInstructionBanner) -> Bool {
        return lhs.distanceAlongStep == rhs.distanceAlongStep &&
            lhs.primaryInstruction == rhs.primaryInstruction &&
            lhs.secondaryInstruction == rhs.secondaryInstruction &&
            lhs.tertiaryInstruction == rhs.tertiaryInstruction &&
            lhs.quaternaryInstruction == rhs .quaternaryInstruction &&
            lhs.drivingSide == rhs.drivingSide
    }
}



open class SpokenInstruction: Codable, ForeignMemberContainerClass {
    public var foreignMembers: JSONObject = [:]
    
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case distanceAlongStep = "distanceAlongGeometry"
        case text = "announcement"
        case ssmlText = "ssmlAnnouncement"
    }
    
    // MARK: Creating a Spoken Instruction
    
    /**
     Initialize a spoken instruction.
     - parameter distanceAlongStep: A distance along the associated `RouteStep` at which to read the instruction aloud.
     - parameter text: A plain-text representation of the speech-optimized instruction.
     - parameter ssmlText: A formatted representation of the speech-optimized instruction.
     */
    public init(distanceAlongStep: LocationDistance, text: String, ssmlText: String) {
        self.distanceAlongStep = distanceAlongStep
        self.text = text
        self.ssmlText = ssmlText
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        distanceAlongStep = try container.decode(LocationDistance.self, forKey: .distanceAlongStep)
        text = try container.decode(String.self, forKey: .text)
        ssmlText = try container.decode(String.self, forKey: .ssmlText)
        
        try decodeForeignMembers(notKeyedBy: CodingKeys.self, with: decoder)
    }
    
    open func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(distanceAlongStep, forKey: .distanceAlongStep)
        try container.encode(text, forKey: .text)
        try container.encode(ssmlText, forKey: .ssmlText)
        
        try encodeForeignMembers(to: encoder)
    }
    
    // MARK: Timing When to Say the Instruction
    
    /**
     A distance along the associated `RouteStep` at which to read the instruction aloud.
     The distance is measured in meters from the beginning of the associated step.
     */
    public let distanceAlongStep: LocationDistance
    
    // MARK: Getting the Instruction to Say
    
    /**
     A plain-text representation of the speech-optimized instruction.
     This representation is appropriate for speech synthesizers that lack support for the [Speech Synthesis Markup Language](https://en.wikipedia.org/wiki/Speech_Synthesis_Markup_Language) (SSML), such as `AVSpeechSynthesizer`. For speech synthesizers that support SSML, use the `ssmlText` property instead.
     */
    public let text: String

    /**
     A formatted representation of the speech-optimized instruction.
     
     This representation is appropriate for speech synthesizers that support the [Speech Synthesis Markup Language](https://en.wikipedia.org/wiki/Speech_Synthesis_Markup_Language) (SSML), such as [Amazon Polly](https://aws.amazon.com/polly/). Numbers and names are marked up to ensure correct pronunciation. For speech synthesizers that lack SSML support, use the `text` property instead.
     */
    public let ssmlText: String
}

extension SpokenInstruction: Equatable {
    public static func == (lhs: SpokenInstruction, rhs: SpokenInstruction) -> Bool {
        return lhs.distanceAlongStep == rhs.distanceAlongStep &&
            lhs.text == rhs.text &&
            lhs.ssmlText == rhs.ssmlText
    }
}


public enum DrivingSide: String, Codable {
    /**
     Indicates driving occurs on the `left` side.
     */
    case left

    /**
     Indicates driving occurs on the `right` side.
     */
    case right
    
    static let `default` = DrivingSide.right
}

public enum TransportType: String, Codable {
    // Possible transport types when the `profileIdentifier` is `ProfileIdentifier.automobile` or `ProfileIdentifier.automobileAvoidingTraffic`

    /**
     The route requires the user to drive or ride a car, truck, or motorcycle.

     This is the usual transport type when the `profileIdentifier` is `ProfileIdentifier.automobile` or `ProfileIdentifier.automobileAvoidingTraffic`.
     */
    case automobile = "driving" // automobile

    /**
     The route requires the user to board a ferry.

     The user should verify that the ferry is in operation. For driving and cycling directions, the user should also verify that their vehicle is permitted onboard the ferry.
     */
    case ferry // automobile, walking, cycling

    /**
     The route requires the user to cross a movable bridge.

     The user may need to wait for the movable bridge to become passable before continuing.
     */
    case movableBridge = "movable bridge" // automobile, cycling

    /**
     The route becomes impassable at this point.

     You should not encounter this transport type under normal circumstances.
     */
    case inaccessible = "unaccessible" // automobile, walking, cycling

    // Possible transport types when the `profileIdentifier` is `ProfileIdentifier.walking`

    /**
     The route requires the user to walk.

     This is the usual transport type when the `profileIdentifier` is `ProfileIdentifier.walking`. For cycling directions, this value indicates that the user is expected to dismount.
     */
    case walking // walking, cycling

    // Possible transport types when the `profileIdentifier` is `ProfileIdentifier.cycling`

    /**
     The route requires the user to ride a bicycle.

     This is the usual transport type when the `profileIdentifier` is `ProfileIdentifier.cycling`.
     */
    case cycling // cycling

    /**
     The route requires the user to board a train.

     The user should consult the train’s timetable. For cycling directions, the user should also verify that bicycles are permitted onboard the train.
     */
    case train // cycling

    // Custom implementation of decoding is needed to circumvent issue reported in
    // https://github.com/mapbox/mapbox-directions-swift/issues/413
    public init(from decoder: Decoder) throws {
        let valueContainer = try decoder.singleValueContainer()
        let rawValue = try valueContainer.decode(String.self)

        if rawValue == "pushing bike" {
            self = .walking

            return
        }

        guard let value = TransportType(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: valueContainer,
                debugDescription: "Cannot initialize TransportType from invalid String value \(rawValue)"
            )
        }
        
        self = value
    }
}

/**
 A `ManeuverType` specifies the type of maneuver required to complete the route step. You can pair a maneuver type with a `ManeuverDirection` to choose an appropriate visual or voice prompt to present the user.

 To avoid a complex series of if-else-if statements or switch statements, use pattern matching with a single switch statement on a tuple that consists of the maneuver type and maneuver direction.
 */
public enum ManeuverType: String, Codable {
    /**
     The step requires the user to depart from a waypoint.

     If the waypoint is some distance away from the nearest road, the maneuver direction indicates the direction the user must turn upon reaching the road.
     */
    case depart

    /**
     The step requires the user to turn.

     The maneuver direction indicates the direction in which the user must turn relative to the current direction of travel. The exit index indicates the number of intersections, large or small, from the previous maneuver up to and including the intersection at which the user must turn.
     */
    case turn

    /**
     The step requires the user to continue after a turn.
     */
    case `continue`

    /**
     The step requires the user to continue on the current road as it changes names.

     The step’s name contains the road’s new name. To get the road’s old name, use the previous step’s name.
     */
    case passNameChange = "new name"

    /**
     The step requires the user to merge onto another road.

     The maneuver direction indicates the side from which the other road approaches the intersection relative to the user.
     */
    case merge

    /**
     The step requires the user to take a entrance ramp (slip road) onto a highway.
     */
    case takeOnRamp = "on ramp"

    /**
     The step requires the user to take an exit ramp (slip road) off a highway.

     The maneuver direction indicates the side of the highway from which the user must exit. The exit index indicates the number of highway exits from the previous maneuver up to and including the exit that the user must take.
     */
    case takeOffRamp = "off ramp"

    /**
     The step requires the user to choose a fork at a Y-shaped fork in the road.

     The maneuver direction indicates which fork to take.
     */
    case reachFork = "fork"

    /**
     The step requires the user to turn at either a T-shaped three-way intersection or a sharp bend in the road where the road also changes names.

     This maneuver type is called out separately so that the user may be able to proceed more confidently, without fear of having overshot the turn. If this distinction is unimportant to you, you may treat the maneuver as an ordinary `turn`.
     */
    case reachEnd = "end of road"

    /**
     The step requires the user to get into a specific lane in order to continue along the current road.

     The maneuver direction is set to `straightAhead`. Each of the first intersection’s usable approach lanes also has an indication of `straightAhead`. A maneuver in a different direction would instead have a maneuver type of `turn`.

     This maneuver type is called out separately so that the application can present the user with lane guidance based on the first element in the `intersections` property. If lane guidance is unimportant to you, you may treat the maneuver as an ordinary `continue` or ignore it.
     */
    case useLane = "use lane"

    /**
     The step requires the user to enter and traverse a roundabout (traffic circle or rotary).

     The step has no name, but the exit name is the name of the road to take to exit the roundabout. The exit index indicates the number of roundabout exits up to and including the exit to take.

     If `RouteOptions.includesExitRoundaboutManeuver` is set to `true`, this step is followed by an `.exitRoundabout` maneuver. Otherwise, this step represents the entire roundabout maneuver, from the entrance to the exit.
     */
    case takeRoundabout = "roundabout"

    /**
     The step requires the user to enter and traverse a large, named roundabout (traffic circle or rotary).

     The step’s name is the name of the roundabout. The exit name is the name of the road to take to exit the roundabout. The exit index indicates the number of rotary exits up to and including the exit that the user must take.

     If `RouteOptions.includesExitRoundaboutManeuver` is set to `true`, this step is followed by an `.exitRotary` maneuver. Otherwise, this step represents the entire roundabout maneuver, from the entrance to the exit.
     */
    case takeRotary = "rotary"

    /**
     The step requires the user to enter and exit a roundabout (traffic circle or rotary) that is compact enough to constitute a single intersection.

     The step’s name is the name of the road to take after exiting the roundabout. This maneuver type is called out separately because the user may perceive the roundabout as an ordinary intersection with an island in the middle. If this distinction is unimportant to you, you may treat the maneuver as either an ordinary `turn` or as a `takeRoundabout`.
     */
    case turnAtRoundabout = "roundabout turn"

    /**
     The step requires the user to exit a roundabout (traffic circle or rotary).

     This maneuver type follows a `.takeRoundabout` maneuver. It is only used when `RouteOptions.includesExitRoundaboutManeuver` is set to true.
     */
    case exitRoundabout = "exit roundabout"

    /**
     The step requires the user to exit a large, named roundabout (traffic circle or rotary).

     This maneuver type follows a `.takeRotary` maneuver. It is only used when `RouteOptions.includesExitRoundaboutManeuver` is set to true.
     */
    case exitRotary = "exit rotary"

    /**
     The step requires the user to respond to a change in travel conditions.

     This maneuver type may occur for example when driving directions require the user to board a ferry, or when cycling directions require the user to dismount. The step’s transport type and instructions contains important contextual details that should be presented to the user at the maneuver location.

     Similar changes can occur simultaneously with other maneuvers, such as when the road changes its name at the site of a movable bridge. In such cases, `heedWarning` is suppressed in favor of another maneuver type.
     */
    case heedWarning = "notification"

    /**
     The step requires the user to arrive at a waypoint.

     The distance and expected travel time for this step are set to zero, indicating that the route or route leg is complete. The maneuver direction indicates the side of the road on which the waypoint can be found (or whether it is straight ahead).
     */
    case arrive
    
    // Unrecognized maneuver types are interpreted as turns.
    // http://project-osrm.org/docs/v5.5.1/api/#stepmaneuver-object
    static let `default` = ManeuverType.turn
}

/**
 A `ManeuverDirection` clarifies a `ManeuverType` with directional information. The exact meaning of the maneuver direction for a given step depends on the step’s maneuver type; see the `ManeuverType` documentation for details.
 */
public enum ManeuverDirection: String, Codable {
    /**
     The maneuver requires a sharp turn to the right.
     */
    case sharpRight = "sharp right"

    /**
     The maneuver requires a turn to the right, a merge to the right, or an exit on the right, or the destination is on the right.
     */
    case right

    /**
     The maneuver requires a slight turn to the right.
     */
    case slightRight = "slight right"

    /**
     The maneuver requires no notable change in direction, or the destination is straight ahead.
     */
    case straightAhead = "straight"

    /**
     The maneuver requires a slight turn to the left.
     */
    case slightLeft = "slight left"

    /**
     The maneuver requires a turn to the left, a merge to the left, or an exit on the left, or the destination is on the right.
     */
    case left

    /**
     The maneuver requires a sharp turn to the left.
     */
    case sharpLeft = "sharp left"

    /**
     The maneuver requires a U-turn when possible.

     Use the difference between the step’s initial and final headings to distinguish between a U-turn to the left (typical in countries that drive on the right) and a U-turn on the right (typical in countries that drive on the left). If the difference in headings is greater than 180 degrees, the maneuver requires a U-turn to the left. If the difference in headings is less than 180 degrees, the maneuver requires a U-turn to the right.
     */
    case uTurn = "uturn"
}

/**
 A road sign design standard.
 
 A sign standard can affect how a user interface should display information related to the road. For example, a speed limit from the `RouteLeg.segmentMaximumSpeedLimits` property may appear in a different-looking view depending on the `RouteStep.speedLimitSign` property.
 */
public enum SignStandard: String, Codable {
    /**
     The [Manual on Uniform Traffic Control Devices](https://en.wikipedia.org/wiki/Manual_on_Uniform_Traffic_Control_Devices).
     
     This standard has been adopted by the United States and Canada, and several other countries have adopted parts of the standard as well.
     */
    case mutcd
    
    /**
     The [Vienna Convention on Road Signs and Signals](https://en.wikipedia.org/wiki/Vienna_Convention_on_Road_Signs_and_Signals).
     
     This standard is prevalent in Europe and parts of Asia and Latin America. Countries in southern Africa and Central America have adopted similar regional standards.
     */
    case viennaConvention = "vienna"
}

extension String {
    internal func tagValues(separatedBy separator: String) -> [String] {
        return components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

extension Array where Element == String {
    internal func tagValues(joinedBy separator: String) -> String {
        return joined(separator: "\(separator) ")
    }
}

/**
 Encapsulates all the information about a road.
 */
struct Road {
    let names: [String]?
    let codes: [String]?
    let exitCodes: [String]?
    let destinations: [String]?
    let destinationCodes: [String]?
    let rotaryNames: [String]?
    
    init(names: [String]?, codes: [String]?, exitCodes: [String]?, destinations: [String]?, destinationCodes: [String]?, rotaryNames: [String]?) {
        self.names = names
        self.codes = codes
        self.exitCodes = exitCodes
        self.destinations = destinations
        self.destinationCodes = destinationCodes
        self.rotaryNames = rotaryNames
    }
    
    init(name: String, ref: String?, exits: String?, destination: String?, rotaryName: String?) {
        if !name.isEmpty, let ref = ref {
            // Directions API v5 profiles powered by Valhalla no longer include the ref in the name. However, the `mapbox/cycling` profile, which is powered by OSRM, still includes the ref.
            let parenthetical = "(\(ref))"
            if name == ref {
                self.names = nil
            } else {
                self.names = name.replacingOccurrences(of: parenthetical, with: "").tagValues(separatedBy: ";")
            }
        } else {
            self.names = name.isEmpty ? nil : name.tagValues(separatedBy: ";")
        }

        // Mapbox Directions API v5 combines the destination’s ref and name.
        if let destination = destination, destination.contains(": ") {
            let destinationComponents = destination.components(separatedBy: ": ")
            self.destinationCodes = destinationComponents.first?.tagValues(separatedBy: ",")
            self.destinations = destinationComponents.dropFirst().joined(separator: ": ").tagValues(separatedBy: ",")
        } else {
            self.destinationCodes = nil
            self.destinations = destination?.tagValues(separatedBy: ",")
        }

        self.exitCodes = exits?.tagValues(separatedBy: ";")
        self.codes = ref?.tagValues(separatedBy: ";")
        self.rotaryNames = rotaryName?.tagValues(separatedBy: ";")
    }
}

extension Road: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name
        case ref
        case exits
        case destinations
        case rotaryName = "rotary_name"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Decoder apparently treats an empty string as a null value.
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        let ref = try container.decodeIfPresent(String.self, forKey: .ref)
        let exits = try container.decodeIfPresent(String.self, forKey: .exits)
        let destinations = try container.decodeIfPresent(String.self, forKey: .destinations)
        let rotaryName = try container.decodeIfPresent(String.self, forKey: .rotaryName)
        self.init(name: name, ref: ref, exits: exits, destination: destinations, rotaryName: rotaryName)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        let ref = codes?.tagValues(joinedBy: ";")
        if var name = names?.tagValues(joinedBy: ";") {
            if let ref = ref {
                name = "\(name) (\(ref))"
            }
            try container.encodeIfPresent(name, forKey: .name)
        } else {
            try container.encode(ref ?? "", forKey: .name)
        }
        
        if var destinations = destinations?.tagValues(joinedBy: ",") {
            if let destinationCodes = destinationCodes?.tagValues(joinedBy: ",") {
                destinations = "\(destinationCodes): \(destinations)"
            }
            try container.encode(destinations, forKey: .destinations)
        }
        
        try container.encodeIfPresent(exitCodes?.tagValues(joinedBy: ";"), forKey: .exits)
        try container.encodeIfPresent(ref, forKey: .ref)
        try container.encodeIfPresent(rotaryNames?.tagValues(joinedBy: ";"), forKey: .rotaryName)
    }
}

/**
 A `RouteStep` object represents a single distinct maneuver along a route and the approach to the next maneuver. The route step object corresponds to a single instruction the user must follow to complete a portion of the route. For example, a step might require the user to turn then follow a road.
 
 You do not create instances of this class directly. Instead, you receive route step objects as part of route objects when you request directions using the `Directions.calculate(_:completionHandler:)` method, setting the `includesSteps` option to `true` in the `RouteOptions` object that you pass into that method.
 */
open class RouteStep: Codable, ForeignMemberContainerClass {
    public var foreignMembers: JSONObject = [:]
    public var maneuverForeignMembers: JSONObject = [:]
    
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case shape = "geometry"
        case distance
        case drivingSide = "driving_side"
        case expectedTravelTime = "duration"
        case typicalTravelTime = "duration_typical"
        case instructions
        case instructionsDisplayedAlongStep = "bannerInstructions"
        case instructionsSpokenAlongStep = "voiceInstructions"
        case intersections
        case maneuver
        case pronunciation
        case rotaryPronunciation = "rotary_pronunciation"
        case speedLimitSignStandard = "speedLimitSign"
        case speedLimitUnit
        case transportType = "mode"
    }
    
    private struct Maneuver: Codable, ForeignMemberContainer {
        var foreignMembers: JSONObject = [:]
        
        private enum CodingKeys: String, CodingKey {
            case instruction
            case location
            case type
            case exitIndex = "exit"
            case direction = "modifier"
            case initialHeading = "bearing_before"
            case finalHeading = "bearing_after"
        }
        
        let instructions: String
        let maneuverType: ManeuverType
        let maneuverDirection: ManeuverDirection?
        let maneuverLocation: Turf.LocationCoordinate2D
        let initialHeading: Turf.LocationDirection?
        let finalHeading: Turf.LocationDirection?
        let exitIndex: Int?
        
        init(instructions: String,
             maneuverType: ManeuverType,
             maneuverDirection: ManeuverDirection?,
             maneuverLocation: Turf.LocationCoordinate2D,
             initialHeading: Turf.LocationDirection?,
             finalHeading: Turf.LocationDirection?,
             exitIndex: Int?) {
            self.instructions = instructions
            self.maneuverType = maneuverType
            self.maneuverLocation = maneuverLocation
            self.maneuverDirection = maneuverDirection
            self.initialHeading = initialHeading
            self.finalHeading = finalHeading
            self.exitIndex = exitIndex
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            maneuverLocation = try container.decode(LocationCoordinate2DCodable.self, forKey: .location).decodedCoordinates
            maneuverType = (try? container.decode(ManeuverType.self, forKey: .type)) ?? .default
            maneuverDirection = try container.decodeIfPresent(ManeuverDirection.self, forKey: .direction)
            exitIndex = try container.decodeIfPresent(Int.self, forKey: .exitIndex)

            initialHeading = try container.decodeIfPresent(Turf.LocationDirection.self, forKey: .initialHeading)
            finalHeading = try container.decodeIfPresent(Turf.LocationDirection.self, forKey: .finalHeading)
            
            if let instruction = try? container.decode(String.self, forKey: .instruction) {
                instructions = instruction
            } else {
                instructions = "\(maneuverType) \(maneuverDirection?.rawValue ?? "")"
            }
            
            try decodeForeignMembers(notKeyedBy: CodingKeys.self, with: decoder)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(instructions, forKey: .instruction)
            try container.encode(maneuverType, forKey: .type)
            try container.encodeIfPresent(exitIndex, forKey: .exitIndex)

            try container.encodeIfPresent(maneuverDirection, forKey: .direction)
            try container.encode(LocationCoordinate2DCodable(maneuverLocation), forKey: .location)
            try container.encodeIfPresent(initialHeading, forKey: .initialHeading)
            try container.encodeIfPresent(finalHeading, forKey: .finalHeading)
            
            try encodeForeignMembers(notKeyedBy: CodingKeys.self, to: encoder)
        }
    }
    
    // MARK: Creating a Step
    
    /**
     Initializes a step.
     
     - parameter transportType: The mode of transportation used for the step.
     - parameter maneuverLocation: The location of the maneuver at the beginning of this step.
     - parameter maneuverType: The type of maneuver required for beginning this step.
     - parameter maneuverDirection: Additional directional information to clarify the maneuver type.
     - parameter instructions: A string with instructions explaining how to perform the step’s maneuver.
     - parameter initialHeading: The user’s heading immediately before performing the maneuver.
     - parameter finalHeading: The user’s heading immediately after performing the maneuver.
     - parameter drivingSide: Indicates what side of a bidirectional road the driver must be driving on. Also referred to as the rule of the road.
     - parameter exitCodes: Any [exit numbers](https://en.wikipedia.org/wiki/Exit_number) assigned to the highway exit at the maneuver.
     - parameter exitNames: The names of the roundabout exit.
     - parameter phoneticExitNames: A phonetic or phonemic transcription indicating how to pronounce the names in the `exitNames` property.
     - parameter distance: The step’s distance, measured in meters.
     - parameter expectedTravelTime: The step's expected travel time, measured in seconds.
     - parameter typicalTravelTime: The step's typical travel time, measured in seconds.
     - parameter names: The names of the road or path leading from this step’s maneuver to the next step’s maneuver.
     - parameter phoneticNames: A phonetic or phonemic transcription indicating how to pronounce the names in the `names` property.
     - parameter codes: Any route reference codes assigned to the road or path leading from this step’s maneuver to the next step’s maneuver.
     - parameter destinationCodes: Any route reference codes that appear on guide signage for the road leading from this step’s maneuver to the next step’s maneuver.
     - parameter destinations: Destinations, such as [control cities](https://en.wikipedia.org/wiki/Control_city), that appear on guide signage for the road leading from this step’s maneuver to the next step’s maneuver.
     - parameter intersections: An array of intersections along the step.
     - parameter speedLimitSignStandard: The sign design standard used for speed limit signs along the step.
     - parameter speedLimitUnit: The unit of speed limits on speed limit signs along the step.
     - parameter instructionsSpokenAlongStep: Instructions about the next step’s maneuver, optimized for speech synthesis.
     - parameter instructionsDisplayedAlongStep: Instructions about the next step’s maneuver, optimized for display in real time.
     */
    public init(transportType: TransportType, maneuverLocation: Turf.LocationCoordinate2D, maneuverType: ManeuverType, maneuverDirection: ManeuverDirection? = nil, instructions: String, initialHeading: Turf.LocationDirection? = nil, finalHeading: Turf.LocationDirection? = nil, drivingSide: DrivingSide, exitCodes: [String]? = nil, exitNames: [String]? = nil, phoneticExitNames: [String]? = nil, distance: Turf.LocationDistance, expectedTravelTime: TimeInterval, typicalTravelTime: TimeInterval? = nil, names: [String]? = nil, phoneticNames: [String]? = nil, codes: [String]? = nil, destinationCodes: [String]? = nil, destinations: [String]? = nil, intersections: [Intersection]? = nil, speedLimitSignStandard: SignStandard? = nil, speedLimitUnit: UnitSpeed? = nil, instructionsSpokenAlongStep: [SpokenInstruction]? = nil, instructionsDisplayedAlongStep: [VisualInstructionBanner]? = nil, administrativeAreaContainerByIntersection: [Int?]? = nil, segmentIndicesByIntersection: [Int?]? = nil) {
        self.transportType = transportType
        self.maneuverLocation = maneuverLocation
        self.maneuverType = maneuverType
        self.maneuverDirection = maneuverDirection
        self.instructions = instructions
        self.initialHeading = initialHeading
        self.finalHeading = finalHeading
        self.drivingSide = drivingSide
        self.exitCodes = exitCodes
        self.exitNames = exitNames
        self.phoneticExitNames = phoneticExitNames
        self.distance = distance
        self.expectedTravelTime = expectedTravelTime
        self.typicalTravelTime = typicalTravelTime
        self.names = names
        self.phoneticNames = phoneticNames
        self.codes = codes
        self.destinationCodes = destinationCodes
        self.destinations = destinations
        self.intersections = intersections
        self.speedLimitSignStandard = speedLimitSignStandard
        self.speedLimitUnit = speedLimitUnit
        self.instructionsSpokenAlongStep = instructionsSpokenAlongStep
        self.instructionsDisplayedAlongStep = instructionsDisplayedAlongStep
        self.administrativeAreaContainerByIntersection = administrativeAreaContainerByIntersection
        self.segmentIndicesByIntersection = segmentIndicesByIntersection
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(instructionsSpokenAlongStep, forKey: .instructionsSpokenAlongStep)
        try container.encodeIfPresent(instructionsDisplayedAlongStep, forKey: .instructionsDisplayedAlongStep)
        try container.encode(distance, forKey: .distance)
        try container.encode(expectedTravelTime, forKey: .expectedTravelTime)
        try container.encodeIfPresent(typicalTravelTime, forKey: .typicalTravelTime)
        try container.encode(transportType, forKey: .transportType)
        
        let isRound = maneuverType == .takeRotary || maneuverType == .takeRoundabout
        let road = Road(names: isRound ? exitNames : names,
                        codes: codes,
                        exitCodes: exitCodes,
                        destinations: destinations,
                        destinationCodes: destinationCodes,
                        rotaryNames: isRound ? names : nil)
        try road.encode(to: encoder)
        if isRound {
            try container.encodeIfPresent(phoneticNames?.tagValues(joinedBy: ";"), forKey: .rotaryPronunciation)
            try container.encodeIfPresent(phoneticExitNames?.tagValues(joinedBy: ";"), forKey: .pronunciation)
        } else {
            try container.encodeIfPresent(phoneticNames?.tagValues(joinedBy: ";"), forKey: .pronunciation)
        }
        
        if let intersectionsToEncode = intersections {
            var intersectionsContainer = container.nestedUnkeyedContainer(forKey: .intersections)
            try Intersection.encode(intersections: intersectionsToEncode,
                                    to: &intersectionsContainer,
                                    administrativeRegionIndices: administrativeAreaContainerByIntersection,
                                    segmentIndicesByIntersection: segmentIndicesByIntersection)
        }
        
        try container.encode(drivingSide, forKey: .drivingSide)
        if let shape = shape {
            let options = encoder.userInfo[.options] as? DirectionsOptions
            let shapeFormat = options?.shapeFormat ?? .default
            let polyLineString = PolyLineString(lineString: shape, shapeFormat: shapeFormat)
            try container.encode(polyLineString, forKey: .shape)
        }
        
        var maneuver = Maneuver(instructions: instructions,
                                maneuverType: maneuverType,
                                maneuverDirection: maneuverDirection,
                                maneuverLocation: maneuverLocation,
                                initialHeading: initialHeading,
                                finalHeading: finalHeading,
                                exitIndex: exitIndex)
        maneuver.foreignMembers = maneuverForeignMembers
        try container.encode(maneuver, forKey: .maneuver)
        
        try container.encodeIfPresent(speedLimitSignStandard, forKey: .speedLimitSignStandard)
        if let speedLimitUnit = speedLimitUnit,
            let unit = SpeedLimitDescriptor.UnitDescriptor(unit: speedLimitUnit) {
            try container.encode(unit, forKey: .speedLimitUnit)
        }
        
        try encodeForeignMembers(to: encoder)
    }
    
    static func decode(from decoder: Decoder, administrativeRegions: [AdministrativeRegion]) throws -> [RouteStep] {
        var container = try decoder.unkeyedContainer()
        
        var steps = Array<RouteStep>()
        while !container.isAtEnd {
            let step = try RouteStep(from: container.superDecoder(), administrativeRegions: administrativeRegions)
            
            steps.append(step)
        }
        
        return steps
    }
    
    
    /// Used to Decode `Intersection.admin_index`
    private struct AdministrativeAreaIndex: Codable {
        
        private enum CodingKeys: String, CodingKey {
            case administrativeRegionIndex = "admin_index"
        }
        
        var administrativeRegionIndex: Int?
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            administrativeRegionIndex = try container.decodeIfPresent(Int.self, forKey: .administrativeRegionIndex)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(administrativeRegionIndex, forKey: .administrativeRegionIndex)
        }
    }
    
    /// Used to Decode `Intersection.geometry_index`
    private struct IntersectionShapeIndex: Codable {
        
        private enum CodingKeys: String, CodingKey {
            case geometryIndex = "geometry_index"
        }
        
        let geometryIndex: Int?
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            geometryIndex = try container.decodeIfPresent(Int.self, forKey: .geometryIndex)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(geometryIndex, forKey: .geometryIndex)
        }
    }

    
    public required convenience init(from decoder: Decoder) throws {
        try self.init(from: decoder, administrativeRegions: nil)
    }
    
    init(from decoder: Decoder, administrativeRegions: [AdministrativeRegion]?) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let maneuver = try container.decode(Maneuver.self, forKey: .maneuver)
        
        maneuverLocation = maneuver.maneuverLocation
        maneuverType = maneuver.maneuverType
        maneuverDirection = maneuver.maneuverDirection
        exitIndex = maneuver.exitIndex
        initialHeading = maneuver.initialHeading
        finalHeading = maneuver.finalHeading
        instructions = maneuver.instructions
        maneuverForeignMembers = maneuver.foreignMembers
        
        if let polyLineString = try container.decodeIfPresent(PolyLineString.self, forKey: .shape) {
            shape = try LineString(polyLineString: polyLineString)
        } else {
            shape = nil
        }
        
        drivingSide = try container.decode(DrivingSide.self, forKey: .drivingSide)
  
        instructionsSpokenAlongStep = try container.decodeIfPresent([SpokenInstruction].self, forKey: .instructionsSpokenAlongStep)
        
        if let visuals = try container.decodeIfPresent([VisualInstructionBanner].self, forKey: .instructionsDisplayedAlongStep) {
            for instruction in visuals {
                instruction.drivingSide = drivingSide
            }
            instructionsDisplayedAlongStep = visuals
        } else {
            instructionsDisplayedAlongStep = nil
        }
        
        distance = try container.decode(Turf.LocationDirection.self, forKey: .distance)
        expectedTravelTime = try container.decode(TimeInterval.self, forKey: .expectedTravelTime)
        typicalTravelTime = try container.decodeIfPresent(TimeInterval.self, forKey: .typicalTravelTime)
        
        transportType = try container.decode(TransportType.self, forKey: .transportType)
        administrativeAreaContainerByIntersection = try container.decodeIfPresent([AdministrativeAreaIndex].self,
                                                                                  forKey: .intersections)?.map { $0.administrativeRegionIndex }
        var rawIntersections = try container.decodeIfPresent([Intersection].self, forKey: .intersections)
        
        // Updating `Intersection.regionCode` since we removed it's `admin_index` for convenience
        if let administrativeRegions = administrativeRegions,
           rawIntersections != nil,
           let rawAdminIndicies = administrativeAreaContainerByIntersection {
            for index in 0..<rawIntersections!.count {
                if let regionIndex = rawAdminIndicies[index],
                   administrativeRegions.count > regionIndex {
                    rawIntersections![index].updateRegionCode(administrativeRegions[regionIndex].countryCode)
                }
            }
        }
        
        intersections = rawIntersections
        
        segmentIndicesByIntersection = try container.decodeIfPresent([IntersectionShapeIndex].self,
                                                                     forKey: .intersections)?.map { $0.geometryIndex }
        
        let road = try Road(from: decoder)
        codes = road.codes
        exitCodes = road.exitCodes
        destinations = road.destinations
        destinationCodes = road.destinationCodes
        
        speedLimitSignStandard = try container.decodeIfPresent(SignStandard.self, forKey: .speedLimitSignStandard)
        speedLimitUnit = (try container.decodeIfPresent(SpeedLimitDescriptor.UnitDescriptor.self, forKey: .speedLimitUnit))?.describedUnit
        
        let type = maneuverType
        if type == .takeRotary || type == .takeRoundabout {
            names = road.rotaryNames
            phoneticNames = try container.decodeIfPresent(String.self, forKey: .rotaryPronunciation)?.tagValues(separatedBy: ";")
            exitNames = road.names
            phoneticExitNames = try container.decodeIfPresent(String.self, forKey: .pronunciation)?.tagValues(separatedBy: ";")
        } else {
            names = road.names
            phoneticNames = try container.decodeIfPresent(String.self, forKey: .pronunciation)?.tagValues(separatedBy: ";")
            exitNames = nil
            phoneticExitNames = nil
        }
        
        try decodeForeignMembers(notKeyedBy: CodingKeys.self, with: decoder)
        try decodeForeignMembers(notKeyedBy: Road.CodingKeys.self, with: decoder)
    }
    
    // MARK: Getting the Shape of the Step
    
    /**
     The path of the route step from the location of the maneuver to the location of the next step’s maneuver.
     
     The value of this property may be `nil`, for example when the maneuver type is `arrive`.
     
     Using the [Mapbox Maps SDK for iOS](https://www.mapbox.com/ios-sdk/) or [Mapbox Maps SDK for macOS](https://github.com/mapbox/mapbox-gl-native/tree/master/platform/macos/), you can create an `MGLPolyline` object using the `LineString.coordinates` property to display a portion of a route on an `MGLMapView`.
     */
    public var shape: LineString?
    
    // MARK: Getting the Mode of Transportation
    
    /**
     The mode of transportation used for the step.
     
     This step may use a different mode of transportation than the overall route.
     */
    public let transportType: TransportType
    
    // MARK: Getting Details About the Maneuver
    
    /**
     The location of the maneuver at the beginning of this step.
     */
    public let maneuverLocation: Turf.LocationCoordinate2D
    
    /**
     The type of maneuver required for beginning this step.
     */
    public let maneuverType: ManeuverType
    
    /**
     Additional directional information to clarify the maneuver type.
     */
    public let maneuverDirection: ManeuverDirection?
    
    /**
     A string with instructions explaining how to perform the step’s maneuver.
     
     You can display this string or read it aloud to the user. The string does not include the distance to or from the maneuver. For instructions optimized for real-time delivery during turn-by-turn navigation, set the `RouteOptions.includesSpokenInstructions` option and use the `instructionsSpokenAlongStep` property. If you need customized instructions, you can construct them yourself from the step’s other properties or use [OSRM Text Instructions](https://github.com/Project-OSRM/osrm-text-instructions.swift/).
     
     - note: If you use the MapboxDirections framework with the Mapbox Directions API, this property is formatted and localized for display to the user. If you use OSRM directly, this property contains a basic string that only includes the maneuver type and direction. Use [OSRM Text Instructions](https://github.com/Project-OSRM/osrm-text-instructions.swift/) to construct a complete, localized instruction string for display.
     */
    public let instructions: String
    
    /**
     The user’s heading immediately before performing the maneuver.
     */
    public let initialHeading: Turf.LocationDirection?
    
    /**
     The user’s heading immediately after performing the maneuver.
     
     The value of this property may differ from the user’s heading after traveling along the road past the maneuver.
     */
    public let finalHeading: Turf.LocationDirection?
    
    /**
     Indicates what side of a bidirectional road the driver must be driving on. Also referred to as the rule of the road.
     */
    public let drivingSide: DrivingSide
    
    /**
     The number of exits from the previous maneuver up to and including this step’s maneuver.
     
     If the maneuver takes place on a surface street, this property counts intersections. The number of intersections does not necessarily correspond to the number of blocks. If the maneuver takes place on a grade-separated highway (freeway or motorway), this property counts highway exits but not highway entrances. If the maneuver is a roundabout maneuver, the exit index is the number of exits from the approach to the recommended outlet. For the signposted exit numbers associated with a highway exit, use the `exitCodes` property.
     
     In some cases, the number of exits leading to a maneuver may be more useful to the user than the distance to the maneuver.
     */
    open var exitIndex: Int?
    
    /**
     Any [exit numbers](https://en.wikipedia.org/wiki/Exit_number) assigned to the highway exit at the maneuver.
     
     This property is only set when the `maneuverType` is `ManeuverType.takeOffRamp`. For the number of exits from the previous maneuver, regardless of the highway’s exit numbering scheme, use the `exitIndex` property. For the route reference codes associated with the connecting road, use the `destinationCodes` property. For the names associated with a roundabout exit, use the `exitNames` property.
     
     An exit number is an alphanumeric identifier posted at or ahead of a highway off-ramp. Exit numbers may increase or decrease sequentially along a road, or they may correspond to distances from either end of the road. An alphabetic suffix may appear when multiple exits are located in the same interchange. If multiple exits are [combined into a single exit](https://en.wikipedia.org/wiki/Local-express_lanes#Example_of_cloverleaf_interchanges), the step may have multiple exit codes.
     */
    public let exitCodes: [String]?
    
    /**
     The names of the roundabout exit.
     
     This property is only set for roundabout (traffic circle or rotary) maneuvers. For the signposted names associated with a highway exit, use the `destinations` property. For the signposted exit numbers, use the `exitCodes` property.
     
     If you display a name to the user, you may need to abbreviate common words like “East” or “Boulevard” to ensure that it fits in the allotted space.
     */
    public let exitNames: [String]?
    
    /**
     A phonetic or phonemic transcription indicating how to pronounce the names in the `exitNames` property.
     
     This property is only set for roundabout (traffic circle or rotary) maneuvers.
     
     The transcription is written in the [International Phonetic Alphabet](https://en.wikipedia.org/wiki/International_Phonetic_Alphabet).
     */
    public let phoneticExitNames: [String]?
    
    // MARK: Getting Details About the Approach to the Next Maneuver
    
    /**
     The step’s distance, measured in meters.
     
     The value of this property accounts for the distance that the user must travel to go from this step’s maneuver location to the next step’s maneuver location. It is not the sum of the direct distances between the route’s waypoints, nor should you assume that the user would travel along this distance at a fixed speed.
     */
    public let distance: Turf.LocationDistance
    
    /**
     The step’s expected travel time, measured in seconds.
     
     The value of this property reflects the time it takes to go from this step’s maneuver location to the next step’s maneuver location. If the route was calculated using the `ProfileIdentifier.automobileAvoidingTraffic` profile, this property reflects current traffic conditions at the time of the request, not necessarily the traffic conditions at the time the user would begin this step. For other profiles, this property reflects travel time under ideal conditions and does not account for traffic congestion. If the step makes use of a ferry or train, the actual travel time may additionally be subject to the schedules of those services.
     
     Do not assume that the user would travel along the step at a fixed speed. For the expected travel time on each individual segment along the leg, specify the `AttributeOptions.expectedTravelTime` option and use the `RouteLeg.expectedSegmentTravelTimes` property.
     */
    open var expectedTravelTime: TimeInterval
    
    /**
     The step’s typical travel time, measured in seconds.
     
     The value of this property reflects the typical time it takes to go from this step’s maneuver location to the next step’s maneuver location. This property is available when using the `ProfileIdentifier.automobileAvoidingTraffic` profile. This property reflects typical traffic conditions at the time of the request, not necessarily the typical traffic conditions at the time the user would begin this step. If the step makes use of a ferry, the typical travel time may additionally be subject to the schedule of this service.
     
     Do not assume that the user would travel along the step at a fixed speed.
     */
    open var typicalTravelTime: TimeInterval?
    
    /**
     The names of the road or path leading from this step’s maneuver to the next step’s maneuver.
     
     If the maneuver is a turning maneuver, the step’s names are the name of the road or path onto which the user turns. If you display a name to the user, you may need to abbreviate common words like “East” or “Boulevard” to ensure that it fits in the allotted space.
     
     If the maneuver is a roundabout maneuver, the outlet to take is named in the `exitNames` property; the `names` property is only set for large roundabouts that have their own names.
     */
    public let names: [String]?
    
    /**
     A phonetic or phonemic transcription indicating how to pronounce the names in the `names` property.
     
     The transcription is written in the [International Phonetic Alphabet](https://en.wikipedia.org/wiki/International_Phonetic_Alphabet).
     
     If the maneuver traverses a large, named roundabout, the `exitPronunciationHints` property contains a hint about how to pronounce the names of the outlet to take.
     */
    public let phoneticNames: [String]?
    
    /**
     Any route reference codes assigned to the road or path leading from this step’s maneuver to the next step’s maneuver.
     
     A route reference code commonly consists of an alphabetic network code, a space or hyphen, and a route number. You should not assume that the network code is globally unique: for example, a network code of “NH” may indicate a “National Highway” or “New Hampshire”. Moreover, a route number may not even uniquely identify a route within a given network.
     
     If a highway ramp is part of a numbered route, its reference code is contained in this property. On the other hand, guide signage for a highway ramp usually indicates route reference codes of the adjoining road; use the `destinationCodes` property for those route reference codes.
     */
    public let codes: [String]?
    
    /**
     Any route reference codes that appear on guide signage for the road leading from this step’s maneuver to the next step’s maneuver.
     
     This property is typically available in steps leading to or from a freeway or expressway. This property contains route reference codes associated with a road later in the route. If a highway ramp is itself part of a numbered route, its reference code is contained in the `codes` property. For the signposted exit numbers associated with a highway exit, use the `exitCodes` property.
     
     A route reference code commonly consists of an alphabetic network code, a space or hyphen, and a route number. You should not assume that the network code is globally unique: for example, a network code of “NH” may indicate a “National Highway” or “New Hampshire”. Moreover, a route number may not even uniquely identify a route within a given network. A destination code for a divided road is often suffixed with the cardinal direction of travel, for example “I 80 East”.
     */
    public let destinationCodes: [String]?
    
    /**
     Destinations, such as [control cities](https://en.wikipedia.org/wiki/Control_city), that appear on guide signage for the road leading from this step’s maneuver to the next step’s maneuver.
     
     This property is typically available in steps leading to or from a freeway or expressway.
     */
    public let destinations: [String]?
    
    /**
     An array of intersections along the step.
     
     Each item in the array corresponds to a cross street, starting with the intersection at the maneuver location indicated by the coordinates property and continuing with each cross street along the step.
    */
    public let intersections: [Intersection]?
    
    /**
     Each intersection’s administrative region index.
          
     This property is set to `nil` if the `intersections` property is `nil`. An individual array element may be `nil` if the corresponding `Intersection` instance has no administrative region assigned.
     
    - seealso: `Intersection.regionCode`, `RouteStep.regionCode(atStepIndex:, intersectionIndex:)`
    */
    public let administrativeAreaContainerByIntersection: [Int?]?

    /**
     Segments indices for each `Intersection` along the step.
     
     The indices are arranged in the same order as the items of `intersections`. This property is `nil` if `intersections` is `nil`. An individual item may be `nil` if the corresponding JSON-formatted intersection object has no `geometry_index` property.
     */
    public let segmentIndicesByIntersection: [Int?]?
    
    /**
     The sign design standard used for speed limit signs along the step.
     
     This standard affects how corresponding speed limits in the `RouteLeg.segmentMaximumSpeedLimits` property should be displayed.
     */
    public let speedLimitSignStandard: SignStandard?
    
    /**
     The unit of speed limits on speed limit signs along the step.
     
     This standard affects how corresponding speed limits in the `RouteLeg.segmentMaximumSpeedLimits` property should be displayed.
     */
    public let speedLimitUnit: UnitSpeed?
    
    // MARK: Getting Details About the Next Maneuver
    
    /**
     Instructions about the next step’s maneuver, optimized for speech synthesis.
    
     As the user traverses this step, you can give them advance notice of the upcoming maneuver by reading aloud each item in this array in order as the user reaches the specified distances along this step. The text of the spoken instructions refers to the details in the next step, but the distances are measured from the beginning of this step.
     
     This property is non-`nil` if the `RouteOptions.includesSpokenInstructions` option is set to `true`. For instructions designed for display, use the `instructions` property.
     */
    public let instructionsSpokenAlongStep: [SpokenInstruction]?
    
     /**
     Instructions about the next step’s maneuver, optimized for display in real time.
     
     As the user traverses this step, you can give them advance notice of the upcoming maneuver by displaying each item in this array in order as the user reaches the specified distances along this step. The text and images of the visual instructions refer to the details in the next step, but the distances are measured from the beginning of this step.
     
     This property is non-`nil` if the `RouteOptions.includesVisualInstructions` option is set to `true`. For instructions designed for speech synthesis, use the `instructionsSpokenAlongStep` property. For instructions designed for display in a static list, use the `instructions` property.
     */
    public let instructionsDisplayedAlongStep: [VisualInstructionBanner]?
}

extension RouteStep: Equatable {
    public static func == (lhs: RouteStep, rhs: RouteStep) -> Bool {
        // Compare all the properties, from cheapest to most expensive to compare.
        return lhs.initialHeading == rhs.initialHeading &&
            lhs.finalHeading == rhs.finalHeading &&
            lhs.instructions == rhs.instructions &&
            lhs.exitIndex == rhs.exitIndex &&
            lhs.distance == rhs.distance &&
            lhs.expectedTravelTime == rhs.expectedTravelTime &&
            lhs.typicalTravelTime == rhs.typicalTravelTime &&
            
            lhs.maneuverType == rhs.maneuverType &&
            lhs.maneuverDirection == rhs.maneuverDirection &&
            lhs.drivingSide == rhs.drivingSide &&
            lhs.transportType == rhs.transportType &&
            
            lhs.maneuverLocation == rhs.maneuverLocation &&
            
            lhs.exitCodes == rhs.exitCodes &&
            lhs.exitNames == rhs.exitNames &&
            lhs.phoneticExitNames == rhs.phoneticExitNames &&
            lhs.names == rhs.names &&
            lhs.phoneticNames == rhs.phoneticNames &&
            lhs.codes == rhs.codes &&
            lhs.destinationCodes == rhs.destinationCodes &&
            lhs.destinations == rhs.destinations &&
            
            lhs.speedLimitSignStandard == rhs.speedLimitSignStandard &&
            lhs.speedLimitUnit == rhs.speedLimitUnit &&
            
            lhs.intersections == rhs.intersections &&
            lhs.instructionsSpokenAlongStep == rhs.instructionsSpokenAlongStep &&
            lhs.instructionsDisplayedAlongStep == rhs.instructionsDisplayedAlongStep &&
            
            lhs.shape == rhs.shape
    }
}

extension RouteStep: CustomStringConvertible {
    public var description: String {
        return instructions
    }
}

extension RouteStep: CustomQuickLookConvertible {
    func debugQuickLookObject() -> Any? {
        guard let shape = shape else {
            return nil
        }
        return debugQuickLookURL(illustrating: shape)
    }
}

struct Lane: Equatable, ForeignMemberContainer {
    var foreignMembers: JSONObject = [:]
    
    /**
     The lane indications specifying the maneuvers that may be executed from the lane.
     */
    let indications: LaneIndication
    
    /**
     Whether the lane can be taken to complete the maneuver (`true`) or not (`false`)
     */
    var isValid: Bool
    
    /**
     Whether the lane is a preferred lane (`true`) or not (`false`)
     A preferred lane is a lane that is recommended if there are multiple lanes available
     */
    var isActive: Bool?
    
    /**
     Which of the `indications` is applicable to the current route, when there is more than one
     */
    var validIndication: ManeuverDirection?
    
    init(indications: LaneIndication, valid: Bool = false, active: Bool? = false, preferred: ManeuverDirection? = nil) {
        self.indications = indications
        self.isValid = valid
        self.isActive = active
        self.validIndication = preferred
    }
}

extension Lane: Codable {
    private enum CodingKeys: String, CodingKey {
        case indications
        case valid
        case active
        case preferred = "valid_indication"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(indications, forKey: .indications)
        try container.encode(isValid, forKey: .valid)
        try container.encodeIfPresent(isActive, forKey: .active)
        try container.encodeIfPresent(validIndication, forKey: .preferred)
        
        try encodeForeignMembers(notKeyedBy: CodingKeys.self, to: encoder)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        indications = try container.decode(LaneIndication.self, forKey: .indications)
        isValid = try container.decode(Bool.self, forKey: .valid)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .active)
        validIndication = try container.decodeIfPresent(ManeuverDirection.self, forKey: .preferred)
        
        try decodeForeignMembers(notKeyedBy: CodingKeys.self, with: decoder)
    }
}

extension HTTPURLResponse {
    var rateLimit: UInt? {
        guard let limit = allHeaderFields["X-Rate-Limit-Limit"] as? String else {
            return nil
        }
        return UInt(limit)
    }
    
    var rateLimitInterval: TimeInterval? {
        guard let interval = allHeaderFields["X-Rate-Limit-Interval"] as? String else {
            return nil
        }
        return TimeInterval(interval)
    }
    
    var rateLimitResetTime: Date? {
        guard let resetTime = allHeaderFields["X-Rate-Limit-Reset"] as? String else {
            return nil
        }
        guard let resetTimeNumber = Double(resetTime) else {
            return nil
        }
        return Date(timeIntervalSince1970: resetTimeNumber)
    }
}


public enum DirectionsError: LocalizedError {
    
    public init(code: String?, message: String?, response: URLResponse?, underlyingError error: Error?) {
        if let response = response as? HTTPURLResponse {
            switch (response.statusCode, code ?? "") {
            case (200, "NoRoute"):
                self = .unableToRoute
            case (200, "NoSegment"):
                self = .unableToLocate
            case (200, "NoMatch"):
                self = .noMatches
            case (422, "TooManyCoordinates"):
                self = .tooManyCoordinates
            case (404, "ProfileNotFound"):
                self = .profileNotFound
                
            case (413, _):
                self = .requestTooLarge
            case (422, "InvalidInput"):
                self = .invalidInput(message: message)
            case (429, _):
                self = .rateLimited(rateLimitInterval: response.rateLimitInterval, rateLimit: response.rateLimit, resetTime: response.rateLimitResetTime)
            default:
                self = .unknown(response: response, underlying: error, code: code, message: message)
            }
        } else {
            self = .unknown(response: response, underlying: error, code: code, message: message)
        }
    }

    /**
     There is no network connection available to perform the network request.
     */
    case network(_: URLError)
    
    /**
     The server returned an empty response.
     */
    case noData
    
    /**
    The API recieved input that it didn't understand.
     */
    case invalidInput(message: String?)
    
    /**
     The server returned a response that isn’t correctly formatted.
     */
    case invalidResponse(_: URLResponse?)
    
    /**
     No route could be found between the specified locations.
     
     Make sure it is possible to travel between the locations with the mode of transportation implied by the profileIdentifier option. For example, it is impossible to travel by car from one continent to another without either a land bridge or a ferry connection.
     */
    case unableToRoute
    
    /**
     The specified coordinates could not be matched to the road network.
     
     Try again making sure that your tracepoints lie in close proximity to a road or path.
     */
    case noMatches
    
    /**
     The request specifies too many coordinates.
     
     Try again with fewer coordinates.
     */
    case tooManyCoordinates
    
    /**
     A specified location could not be associated with a roadway or pathway.
     
     Make sure the locations are close enough to a roadway or pathway. Try setting the `Waypoint.coordinateAccuracy` property of all the waypoints to `nil`.
     */
    case unableToLocate
    
    /**
     Unrecognized profile identifier.
     
     Make sure the `DirectionsOptions.profileIdentifier` option is set to one of the predefined values, such as `ProfileIdentifier.automobile`.
     */
    case profileNotFound
    
    /**
     The request is too large.
     
     Try specifying fewer waypoints or giving the waypoints shorter names.
     */
    case requestTooLarge
    
    /**
     Too many requests have been made with the same access token within a certain period of time.
     
     Wait before retrying.
     */
    case rateLimited(rateLimitInterval: TimeInterval?, rateLimit: UInt?, resetTime: Date?)
    
    /**
     Unknown error case. Look at associated values for more details.
     */
    
    case unknown(response: URLResponse?, underlying: Error?, code: String?, message: String?)
    
    public var failureReason: String? {
        switch self {
        case .network(_):
            return "The client does not have a network connection to the server."
        case .noData:
            return "The server returned an empty response."
        case let .invalidInput(message):
            return message
        case .invalidResponse(_):
            return "The server returned a response that isn’t correctly formatted."
        case .unableToRoute:
            return "No route could be found between the specified locations."
        case .noMatches:
            return "The specified coordinates could not be matched to the road network."
        case .tooManyCoordinates:
            return "The request specifies too many coordinates."
        case .unableToLocate:
            return "A specified location could not be associated with a roadway or pathway."
        case .profileNotFound:
            return "Unrecognized profile identifier."
        case .requestTooLarge:
            return "The request is too large."
        case let .rateLimited(rateLimitInterval: interval, rateLimit: limit, _):
            guard let interval = interval, let limit = limit else {
                return "Too many requests."
            }
            #if os(Linux)
            let formattedInterval = "\(interval) seconds"
            #else
            let intervalFormatter = DateComponentsFormatter()
            intervalFormatter.unitsStyle = .full
            let formattedInterval = intervalFormatter.string(from: interval) ?? "\(interval) seconds"
            #endif
            let formattedCount = NumberFormatter.localizedString(from: NSNumber(value: limit), number: .decimal)
            return "More than \(formattedCount) requests have been made with this access token within a period of \(formattedInterval)."
        case let .unknown(_, underlying: error, _, message):
            return message
                ?? (error as NSError?)?.userInfo[NSLocalizedFailureReasonErrorKey] as? String
                ?? HTTPURLResponse.localizedString(forStatusCode: (error as NSError?)?.code ?? -1)
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .network(_), .noData, .invalidInput, .invalidResponse:
            return nil
        case .unableToRoute:
            return "Make sure it is possible to travel between the locations with the mode of transportation implied by the profileIdentifier option. For example, it is impossible to travel by car from one continent to another without either a land bridge or a ferry connection."
        case .noMatches:
            return "Try again making sure that your tracepoints lie in close proximity to a road or path."
        case .tooManyCoordinates:
            return "Try again with 100 coordinates or fewer."
        case .unableToLocate:
            return "Make sure the locations are close enough to a roadway or pathway. Try setting the coordinateAccuracy property of all the waypoints to nil."
        case .profileNotFound:
            return "Make sure the profileIdentifier option is set to one of the provided constants, such as ProfileIdentifier.automobile."
        case .requestTooLarge:
            return "Try specifying fewer waypoints or giving the waypoints shorter names."
        case let .rateLimited(rateLimitInterval: _, rateLimit: _, resetTime: rolloverTime):
            guard let rolloverTime = rolloverTime else {
                return nil
            }
            let formattedDate: String = DateFormatter.localizedString(from: rolloverTime, dateStyle: .long, timeStyle: .long)
            return "Wait until \(formattedDate) before retrying."
        case let .unknown(_, underlying: error, _, _):
            return (error as NSError?)?.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String
        }
    }
}

extension DirectionsError: Equatable {
    public static func == (lhs: DirectionsError, rhs: DirectionsError) -> Bool {
        switch (lhs, rhs) {
        case (.noData, .noData),
             (.unableToRoute, .unableToRoute),
             (.noMatches, .noMatches),
             (.tooManyCoordinates, .tooManyCoordinates),
             (.unableToLocate, .unableToLocate),
             (.profileNotFound, .profileNotFound),
             (.requestTooLarge, .requestTooLarge):
            return true
        case let (.network(lhsError), .network(rhsError)):
            return lhsError == rhsError
        case let (.invalidResponse(lhsResponse), .invalidResponse(rhsResponse)):
            return lhsResponse == rhsResponse
        case let (.invalidInput(lhsMessage), .invalidInput(rhsMessage)):
            return lhsMessage == rhsMessage
        case (.rateLimited(let lhsRateLimitInterval, let lhsRateLimit, let lhsResetTime),
              .rateLimited(let rhsRateLimitInterval, let rhsRateLimit, let rhsResetTime)):
            return lhsRateLimitInterval == rhsRateLimitInterval
                && lhsRateLimit == rhsRateLimit
                && lhsResetTime == rhsResetTime
        case (.unknown(let lhsResponse, let lhsUnderlying, let lhsCode, let lhsMessage),
              .unknown(let rhsResponse, let rhsUnderlying, let rhsCode, let rhsMessage)):
            return lhsResponse == rhsResponse
                && type(of: lhsUnderlying) == type(of: rhsUnderlying)
                && lhsUnderlying?.localizedDescription == rhsUnderlying?.localizedDescription
                && lhsCode == rhsCode
                && lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

/**
 An error that occurs when encoding or decoding a type defined by the MapboxDirections framework.
 */
public enum DirectionsCodingError: Error {
    /**
     Decoding this type requires the `Decoder.userInfo` dictionary to contain the `CodingUserInfoKey.options` key.
     */
    case missingOptions
    
    
    /**
     Decoding this type requires the `Decoder.userInfo` dictionary to contain the `CodingUserInfoKey.credentials` key.
     */
    case missingCredentials
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension ForeignMemberContainer {
    /**
     Decodes any foreign members using the given decoder.
     */
    mutating func decodeForeignMembers<WellKnownCodingKeys>(notKeyedBy _: WellKnownCodingKeys.Type, with decoder: Decoder) throws where WellKnownCodingKeys: CodingKey {
        let foreignMemberContainer = try decoder.container(keyedBy: AnyCodingKey.self)
        for key in foreignMemberContainer.allKeys {
            if WellKnownCodingKeys(stringValue: key.stringValue) == nil {
                foreignMembers[key.stringValue] = try foreignMemberContainer.decode(JSONValue?.self, forKey: key)
            }
        }
    }

    /**
     Encodes any foreign members using the given encoder.
     */
    func encodeForeignMembers<WellKnownCodingKeys>(notKeyedBy _: WellKnownCodingKeys.Type, to encoder: Encoder) throws where WellKnownCodingKeys: CodingKey {
        var foreignMemberContainer = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in foreignMembers {
            if let key = AnyCodingKey(stringValue: key),
               WellKnownCodingKeys(stringValue: key.stringValue) == nil {
                try foreignMemberContainer.encode(value, forKey: key)
            }
        }
    }
}

/**
 A class that can contain foreign members in arbitrary keys.
 
 When subclassing `ForeignMemberContainerClass` type, you should call `decodeForeignMembers(notKeyedBy:with:)` during your `Decodable.init(from:)` initializer if your subclass has added any new properties.
 
 Structures should conform to the `ForeignMemberContainer` protocol instead of this protocol.
 */
public protocol ForeignMemberContainerClass: AnyObject {
    /**
     Foreign members to round-trip to JSON.
     
     Foreign members are unrecognized properties, similar to [foreign members](https://datatracker.ietf.org/doc/html/rfc7946#section-6.1) in GeoJSON. This library does not officially support any property that is documented as a “beta” property in the Mapbox Directions API response format, but you can get and set it as an element of this `JSONObject`.
     */
    var foreignMembers: JSONObject { get set }
    
    /**
     Decodes any foreign members using the given decoder.
     
     - parameter codingKeys: `CodingKeys` type which describes all properties declared  in current subclass.
     - parameter decoder: `Decoder` instance, which perfroms the decoding process.
     */
    func decodeForeignMembers<WellKnownCodingKeys>(notKeyedBy codingKeys: WellKnownCodingKeys.Type, with decoder: Decoder) throws where WellKnownCodingKeys: CodingKey & CaseIterable
    
    /**
     Encodes any foreign members using the given encoder.
     
     This method should be called in your `Encodable.encode(to:)` implementation only in the **base class**. Otherwise it will not encode  `foreignMembers` or way overwrite it.
     
     - parameter encoder: `Encoder` instance, performing the encoding process.
     */
    func encodeForeignMembers(to encoder: Encoder) throws
}

extension ForeignMemberContainerClass {

    public func decodeForeignMembers<WellKnownCodingKeys>(notKeyedBy _: WellKnownCodingKeys.Type, with decoder: Decoder) throws where WellKnownCodingKeys: CodingKey & CaseIterable {
        if foreignMembers.isEmpty {
            let foreignMemberContainer = try decoder.container(keyedBy: AnyCodingKey.self)
            for key in foreignMemberContainer.allKeys {
                if WellKnownCodingKeys(stringValue: key.stringValue) == nil {
                    foreignMembers[key.stringValue] = try foreignMemberContainer.decode(JSONValue?.self, forKey: key)
                }
            }
        }
        WellKnownCodingKeys.allCases.forEach {
            foreignMembers.removeValue(forKey: $0.stringValue)
        }
    }
    
    public func encodeForeignMembers(to encoder: Encoder) throws {
        var foreignMemberContainer = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in foreignMembers {
            if let key = AnyCodingKey(stringValue: key) {
                try foreignMemberContainer.encode(value, forKey: key)
            }
        }
    }
}


public enum MapboxStreetsRoadClass: String, Codable {
    /// High-speed, grade-separated highways
    case motorway = "motorway"
    /// Link roads/lanes/ramps connecting to motorways
    case motorwayLink = "motorway_link"
    /// Important roads that are not motorways.
    case trunk = "trunk"
    /// Link roads/lanes/ramps connecting to trunk roads
    case trunkLink = "trunk_link"
    /// A major highway linking large towns.
    case primary = "primary"
    /// Link roads/lanes connecting to primary roads
    case primaryLink = "primary_link"
    /// A highway linking large towns.
    case secondary = "secondary"
    /// Link roads/lanes connecting to secondary roads
    case secondaryLink = "secondary_link"
    /// A road linking small settlements, or the local centres of a large town or city.
    case tertiary = "tertiary"
    /// Link roads/lanes connecting to tertiary roads
    case tertiaryLink = "tertiary_link"
    /// Standard unclassified, residential, road, and living_street road types
    case street = "street"
    /// Streets that may have limited or no access for motor vehicles.
    case streetLimited = "street_limited"
    /// Includes pedestrian streets, plazas, and public transportation platforms.
    case pedestrian = "pedestrian"
    /// Includes motor roads under construction (but not service roads, paths, etc.
    case construction = "construction"
    /// Roads mostly for agricultural and forestry use etc.
    case track = "track"
    /// Access roads, alleys, agricultural tracks, and other services roads. Also includes parking lot aisles, public & private driveways.
    case service = "service"
    /// Those that serves automobiles and no or unspecified automobile service.
    case ferry = "ferry"
    /// Foot paths, cycle paths, ski trails.
    case path = "path"
    /// Railways, including mainline, commuter rail, and rapid transit.
    case majorRail = "major_rail"
    /// Includes light rail & tram lines.
    case minorRail = "minor_rail"
    /// Yard and service railways.
    case serviceRail = "service_rail"
    /// Ski lifts, gondolas, and other types of aerialway.
    case aerialway = "aerialway"
    /// The approximate centerline of a golf course hole
    case golf = "golf"
}





public struct RestStop: Codable, Equatable, ForeignMemberContainer {
    public var foreignMembers: JSONObject = [:]

    /// A kind of rest stop.
    public enum StopType: String, Codable {
        /// A primitive rest stop that provides parking but no additional services.
        case serviceArea = "service_area"
        /// A major rest stop that provides amenities such as fuel and food.
        case restArea = "rest_area"
    }

    /**
     The kind of the rest stop.
     */
    public let type: StopType
    
    /// The name of the rest stop, if available.
    public let name: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case name
    }
    
    /**
     Initializes an unnamed rest stop of a certain kind.
     
     - parameter type: The kind of rest stop.
     */
    public init(type: StopType) {
        self.type = type
        self.name = nil
    }
    
    /**
     Initializes an optionally named rest stop of a certain kind.
     
     - parameter type: The kind of rest stop.
     - parameter name: The name of the rest stop.
     */
    public init(type: StopType, name: String?) {
        self.type = type
        self.name = name
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(StopType.self, forKey: .type)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        
        try decodeForeignMembers(notKeyedBy: CodingKeys.self, with: decoder)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(name, forKey: .name)
        
        try encodeForeignMembers(notKeyedBy: CodingKeys.self, to: encoder)
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.type == rhs.type && lhs.name == rhs.name
    }
}


public struct TollCollection: Codable, Equatable, ForeignMemberContainer {
    public var foreignMembers: JSONObject = [:]

    public enum CollectionType: String, Codable {
        case booth = "toll_booth"
        case gantry = "toll_gantry"
    }

    /**
     The type of the toll collection point.
     */
    public let type: CollectionType
    
    /**
     The name of the toll collection point.
     */
    public var name: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case name
    }

    public init(type: CollectionType) {
        self.init(type: type, name: nil)
    }
    
    public init(type: CollectionType, name: String?) {
        self.type = type
        self.name = name
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(CollectionType.self, forKey: .type)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        
        try decodeForeignMembers(notKeyedBy: CodingKeys.self, with: decoder)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(name, forKey: .name)
        
        try encodeForeignMembers(notKeyedBy: CodingKeys.self, to: encoder)
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.type == rhs.type
    }
}

//public enum ManeuverDirection: String, Codable {
//    /**
//     The maneuver requires a sharp turn to the right.
//     */
//    case sharpRight = "sharp right"
//
//    /**
//     The maneuver requires a turn to the right, a merge to the right, or an exit on the right, or the destination is on the right.
//     */
//    case right
//
//    /**
//     The maneuver requires a slight turn to the right.
//     */
//    case slightRight = "slight right"
//
//    /**
//     The maneuver requires no notable change in direction, or the destination is straight ahead.
//     */
//    case straightAhead = "straight"
//
//    /**
//     The maneuver requires a slight turn to the left.
//     */
//    case slightLeft = "slight left"
//
//    /**
//     The maneuver requires a turn to the left, a merge to the left, or an exit on the left, or the destination is on the right.
//     */
//    case left
//
//    /**
//     The maneuver requires a sharp turn to the left.
//     */
//    case sharpLeft = "sharp left"
//
//    /**
//     The maneuver requires a U-turn when possible.
//     Use the difference between the step’s initial and final headings to distinguish between a U-turn to the left (typical in countries that drive on the right) and a U-turn on the right (typical in countries that drive on the left). If the difference in headings is greater than 180 degrees, the maneuver requires a U-turn to the left. If the difference in headings is less than 180 degrees, the maneuver requires a U-turn to the right.
//     */
//    case uTurn = "uturn"
//}

public struct LaneIndication: OptionSet, CustomStringConvertible {
    public var rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /// Indicates a sharp turn to the right.
    public static let sharpRight = LaneIndication(rawValue: 1 << 1)
    
    /// Indicates a turn to the right.
    public static let right = LaneIndication(rawValue: 1 << 2)
    
    /// Indicates a turn to the right.
    public static let slightRight = LaneIndication(rawValue: 1 << 3)
    
    /// Indicates no turn.
    public static let straightAhead = LaneIndication(rawValue: 1 << 4)
    
    /// Indicates a slight turn to the left.
    public static let slightLeft = LaneIndication(rawValue: 1 << 5)
    
    /// Indicates a turn to the left.
    public static let left = LaneIndication(rawValue: 1 << 6)
    
    /// Indicates a sharp turn to the left.
    public static let sharpLeft = LaneIndication(rawValue: 1 << 7)
    
    /// Indicates a U-turn.
    public static let uTurn = LaneIndication(rawValue: 1 << 8)
    
    /**
     Creates a lane indication from the given description strings.
     */
    public init?(descriptions: [String]) {
        var laneIndication: LaneIndication = []
        for description in descriptions {
            switch description {
            case "sharp right":
                laneIndication.insert(.sharpRight)
            case "right":
                laneIndication.insert(.right)
            case "slight right":
                laneIndication.insert(.slightRight)
            case "straight":
                laneIndication.insert(.straightAhead)
            case "slight left":
                laneIndication.insert(.slightLeft)
            case "left":
                laneIndication.insert(.left)
            case "sharp left":
                laneIndication.insert(.sharpLeft)
            case "uturn":
                laneIndication.insert(.uTurn)
            case "none":
                break
            default:
                return nil
            }
        }
        self.init(rawValue: laneIndication.rawValue)
    }
    
    init?(from direction: ManeuverDirection) {
        // Assuming that every possible raw value of ManeuverDirection matches valid raw value of LaneIndication
        self.init(descriptions: [direction.rawValue])
    }
    
    public var descriptions: [String] {
        if isEmpty {
            return []
        }
        
        var descriptions: [String] = []
        if contains(.sharpRight) {
            descriptions.append("sharp right")
        }
        if contains(.right) {
            descriptions.append("right")
        }
        if contains(.slightRight) {
            descriptions.append("slight right")
        }
        if contains(.straightAhead) {
            descriptions.append("straight")
        }
        if contains(.slightLeft) {
            descriptions.append("slight left")
        }
        if contains(.left) {
            descriptions.append("left")
        }
        if contains(.sharpLeft) {
            descriptions.append("sharp left")
        }
        if contains(.uTurn) {
            descriptions.append("uturn")
        }
        return descriptions
    }
    
    public var description: String {
        return descriptions.joined(separator: ",")
    }
    
    static func indications(from strings: [String], container: SingleValueDecodingContainer) throws -> LaneIndication {
        guard let indications = self.init(descriptions: strings) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to initialize lane indications from decoded string. This should not happen.")
        }
        return indications
    }
}

extension LaneIndication: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stringValues = try container.decode([String].self)
        
        self = try LaneIndication.indications(from: stringValues, container: container)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(descriptions)
    }
}


public struct RoadClasses: OptionSet, CustomStringConvertible {
    public var rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /**
     The road segment is [tolled](https://wiki.openstreetmap.org/wiki/Key:toll).
     
     This option can only be used with `RouteOptions.roadClassesToAvoid`.
     */
    public static let toll = RoadClasses(rawValue: 1 << 1)
    
    /**
     The road segment has access restrictions.
     
     A road segment may have this class if there are [general access restrictions](https://wiki.openstreetmap.org/wiki/Key:access) or a [high-occupancy vehicle](https://wiki.openstreetmap.org/wiki/Key:hov) restriction.

     This option **cannot** be used with `RouteOptions.roadClassesToAvoid` or `RouteOptions.roadClassesToAllow`.
     */
    public static let restricted = RoadClasses(rawValue: 1 << 2)
    
    /**
     The road segment is a [freeway](https://wiki.openstreetmap.org/wiki/Tag:highway%3Dmotorway) or [freeway ramp](https://wiki.openstreetmap.org/wiki/Tag:highway%3Dmotorway_link).
     
     It may be desirable to suppress the name of the freeway when giving instructions and give instructions at fixed distances before an exit (such as 1 mile or 1 kilometer ahead).
     
     This option can only be used with `RouteOptions.roadClassesToAvoid`.
     */
    public static let motorway = RoadClasses(rawValue: 1 << 3)
    
    /**
     The user must travel this segment of the route by ferry.
     
     The user should verify that the ferry is in operation. For driving and cycling directions, the user should also verify that their vehicle is permitted onboard the ferry.
     
     In general, the transport type of the step containing the road segment is also `TransportType.ferry`.
     
     This option can only be used with `RouteOptions.roadClassesToAvoid`.
     */
    public static let ferry = RoadClasses(rawValue: 1 << 4)
    
    /**
     The user must travel this segment of the route through a [tunnel](https://wiki.openstreetmap.org/wiki/Key:tunnel).

     This option **cannot** be used with `RouteOptions.roadClassesToAvoid` or `RouteOptions.roadClassesToAllow`.
     */
    public static let tunnel = RoadClasses(rawValue: 1 << 5)
    
    /**
     The road segment is a [high occupancy vehicle road](https://wiki.openstreetmap.org/wiki/Key:hov) that requires a minimum of two vehicle occupants.
     
     This option includes high occupancy vehicle road segments that require a minimum of two vehicle occupants only, not high occupancy vehicle lanes.
     
     If the user is in a high-occupancy vehicle with two occupants and would accept a route that uses a [high occupancy toll road](https://wikipedia.org/wiki/High-occupancy_toll_lane), specify both `highOccupancyVehicle2` and `highOccupancyToll`. Otherwise, the routes will avoid any road that requires anyone to pay a toll.
     
     This option can only be used with `RouteOptions.roadClassesToAllow`.
    */
    public static let highOccupancyVehicle2 = RoadClasses(rawValue: 1 << 6)
    
    /**
     The road segment is a [high occupancy vehicle road](https://wiki.openstreetmap.org/wiki/Key:hov) that requires a minimum of three vehicle occupants.
     
     This option includes high occupancy vehicle road segments that require a minimum of three vehicle occupants only, not high occupancy vehicle lanes.
     
     This option can only be used with `RouteOptions.roadClassesToAllow`.
    */
    public static let highOccupancyVehicle3 = RoadClasses(rawValue: 1 << 7)
    
    /**
     The road segment is a [high occupancy toll road](https://wikipedia.org/wiki/High-occupancy_toll_lane) that is tolled if the user's vehicle does not meet the minimum occupant requirement.
     
     This option includes high occupancy toll road segments only, not high occupancy toll lanes.
     
     This option can only be used with `RouteOptions.roadClassesToAllow`.
    */
    public static let highOccupancyToll = RoadClasses(rawValue: 1 << 8)
    
    /**
     The user must travel this segment of the route on an unpaved road.
     
     This option can only be used with `RouteOptions.roadClassesToAvoid`.
     */
    public static let unpaved = RoadClasses(rawValue: 1 << 9)
    
    /**
     The road segment is [tolled](https://wiki.openstreetmap.org/wiki/Key:toll) and only accepts cash payment.
     
     This option can only be used with `RouteOptions.roadClassesToAvoid`.
     */
    public static let cashTollOnly = RoadClasses(rawValue: 1 << 10)
    
    /**
     Creates a `RoadClasses` given an array of strings.
     */
    public init?(descriptions: [String]) {
        var roadClasses: RoadClasses = []
        for description in descriptions {
            switch description {
            case "toll":
                roadClasses.insert(.toll)
            case "restricted":
                roadClasses.insert(.restricted)
            case "motorway":
                roadClasses.insert(.motorway)
            case "ferry":
                roadClasses.insert(.ferry)
            case "tunnel":
                roadClasses.insert(.tunnel)
            case "hov2":
                roadClasses.insert(.highOccupancyVehicle2)
            case "hov3":
                roadClasses.insert(.highOccupancyVehicle3)
            case "hot":
                roadClasses.insert(.highOccupancyToll)
            case "unpaved":
                roadClasses.insert(.unpaved)
            case "cash_only_toll":
                roadClasses.insert(.cashTollOnly)
            case "":
                continue
            default:
                return nil
            }
        }
        self.init(rawValue: roadClasses.rawValue)
    }
    
    public var description: String {
        var descriptions: [String] = []
        if contains(.toll) {
            descriptions.append("toll")
        }
        if contains(.restricted) {
            descriptions.append("restricted")
        }
        if contains(.motorway) {
            descriptions.append("motorway")
        }
        if contains(.ferry) {
            descriptions.append("ferry")
        }
        if contains(.tunnel) {
            descriptions.append("tunnel")
        }
        if contains(.highOccupancyVehicle2) {
            descriptions.append("hov2")
        }
        if contains(.highOccupancyVehicle3) {
            descriptions.append("hov3")
        }
        if contains(.highOccupancyToll) {
            descriptions.append("hot")
        }
        if contains(.unpaved) {
            descriptions.append("unpaved")
        }
        if contains(.cashTollOnly) {
            descriptions.append("cash_only_toll")
        }
        return descriptions.joined(separator: ",")
    }
}

extension RoadClasses: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description.components(separatedBy: ",").filter { !$0.isEmpty })
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let descriptions = try container.decode([String].self)
        if let roadClasses = RoadClasses(descriptions: descriptions){
            self = roadClasses
        }
        else{
            throw DirectionsError.invalidResponse(nil)
        }
    }
}
public struct Intersection: ForeignMemberContainer {
    public var foreignMembers: JSONObject = [:]
    public var lanesForeignMembers: [JSONObject] = []
    
    // MARK: Creating an Intersection
    
    public init(location: LocationCoordinate2D,
                headings: [LocationDirection],
                approachIndex: Int,
                outletIndex: Int,
                outletIndexes: IndexSet,
                approachLanes: [LaneIndication]?,
                usableApproachLanes: IndexSet?,
                preferredApproachLanes: IndexSet?,
                usableLaneIndication: ManeuverDirection?,
                outletRoadClasses: RoadClasses? = nil,
                tollCollection: TollCollection? = nil,
                tunnelName: String? = nil,
                restStop: RestStop? = nil,
                isUrban: Bool? = nil,
                regionCode: String? = nil,
                outletMapboxStreetsRoadClass: MapboxStreetsRoadClass? = nil,
                railroadCrossing: Bool? = nil,
                trafficSignal: Bool? = nil,
                stopSign: Bool? = nil,
                yieldSign: Bool? = nil) {
        self.location = location
        self.headings = headings
        self.approachIndex = approachIndex
        self.approachLanes = approachLanes
        self.outletIndex = outletIndex
        self.outletIndexes = outletIndexes
        self.usableApproachLanes = usableApproachLanes
        self.preferredApproachLanes = preferredApproachLanes
        self.usableLaneIndication = usableLaneIndication
        self.outletRoadClasses = outletRoadClasses
        self.tollCollection = tollCollection
        self.tunnelName = tunnelName
        self.isUrban = isUrban
        self.restStop = restStop
        self.regionCode = regionCode
        self.outletMapboxStreetsRoadClass = outletMapboxStreetsRoadClass
        self.railroadCrossing = railroadCrossing
        self.trafficSignal = trafficSignal
        self.stopSign = stopSign
        self.yieldSign = yieldSign
    }
    
    // MARK: Getting the Location of the Intersection
    
    /**
     The geographic coordinates at the center of the intersection.
     */
    public let location: LocationCoordinate2D
    
    // MARK: Getting the Roads that Meet at the Intersection
    
    /**
     An array of `LocationDirection`s indicating the absolute headings of the roads that meet at the intersection.
     
     A road is represented in this array by a heading indicating the direction from which the road meets the intersection. To get the direction of travel when leaving the intersection along the road, rotate the heading 180 degrees.
     
     A single road that passes through this intersection is represented by two items in this array: one for the segment that enters the intersection and one for the segment that exits it.
     */
    public let headings: [LocationDirection]
    
    /**
     The indices of the items in the `headings` array that correspond to the roads that may be used to leave the intersection.
     
     This index set effectively excludes any one-way road that leads toward the intersection.
     */
    public let outletIndexes: IndexSet
    
    // MARK: Getting the Roads That Take the Route Through the Intersection
    
    /**
     The index of the item in the `headings` array that corresponds to the road that the containing route step uses to approach the intersection.
     
     This property is set to `nil` for a departure maneuver.
     */
    public let approachIndex: Int?
    
    /**
     The index of the item in the `headings` array that corresponds to the road that the containing route step uses to leave the intersection.
     
     This property is set to `nil` for an arrival maneuver.
     */
    public let outletIndex: Int?
    
    /**
     The road classes of the road that the containing step uses to leave the intersection.
     
     If road class information is unavailable, this property is set to `nil`.
     */
    public let outletRoadClasses: RoadClasses?

    /**
     The road classes of the road that the containing step uses to leave the intersection, according to the [Mapbox Streets source](https://docs.mapbox.com/vector-tiles/reference/mapbox-streets-v8/#road) , version 8.
          
     If detailed road class information is unavailable, this property is set to `nil`. This property only indicates the road classification; for other aspects of the road, use the `outletRoadClasses` property.
     */
    public let outletMapboxStreetsRoadClass: MapboxStreetsRoadClass?
    
    /**
     The name of the tunnel that this intersection is a part of.

     If this Intersection is not a tunnel entrance or exit, or if information is unavailable then this property is set to `nil`.
     */
    public let tunnelName: String?

    /**
     A toll collection point.

     If this Intersection is not a toll collection intersection, or if this information is unavailable then this property is set to `nil`.
     */
    public let tollCollection: TollCollection?

    /**
     Corresponding rest stop.

     If this Intersection is not a rest stop, or if this information is unavailable then this property is set to `nil`.
     */
    public let restStop: RestStop?

    /**
     Whether the intersection lays within the bounds of an urban zone.

     If this information is unavailable, then this property is set to `nil`.
     */
    public let isUrban: Bool?
    
    /**
     A 2-letter region code to identify corresponding country that this intersection lies in.
     
     Automatically populated during decoding a `RouteLeg` object, since this is the source of all `AdministrativeRegion`s. Value is `nil` if such information is unavailable.
     
     - seealso: `RouteStep.regionCode(atStepIndex:, intersectionIndex:)`
     */
    public private(set) var regionCode: String?
    
    mutating func updateRegionCode(_ regionCode: String?) {
        self.regionCode = regionCode
    }
    
    // MARK: Telling the User Which Lanes to Use
    
    /**
     All the lanes of the road that the containing route step uses to approach the intersection. Each item in the array represents a lane, which is represented by one or more `LaneIndication`s.
     
     If no lane information is available for the intersection, this property’s value is `nil`. The first item corresponds to the leftmost lane, the second item corresponds to the second lane from the left, and so on, regardless of whether the surrounding country drives on the left or on the right.
     */
    public let approachLanes: [LaneIndication]?
    
    /**
     The indices of the items in the `approachLanes` array that correspond to the lanes that may be used to execute the maneuver.
     
     If no lane information is available for an intersection, this property’s value is `nil`.
     */
    public let usableApproachLanes: IndexSet?
    
    /**
     The indices of the items in the `approachLanes` array that correspond to the lanes that are preferred to execute the maneuver.
     
     If no lane information is available for an intersection, this property’s value is `nil`.
     */
    public let preferredApproachLanes: IndexSet?
    
    /**
     Which of the `LaneIndication`s is applicable to the current route when there is more than one.
     
     If no lane information is available for the intersection, this property’s value is `nil`
     */
    public let usableLaneIndication: ManeuverDirection?
    
    /**
     Indicates whether there is a railroad crossing at the intersection.
     
     If such information is not available for an intersection, this property’s value is `nil`.
     */
    public let railroadCrossing: Bool?
    
    /**
     Indicates whether there is a traffic signal at the intersection.
     
     If such information is not available for an intersection, this property’s value is `nil`.
     */
    public let trafficSignal: Bool?
    
    /**
     Indicates whether there is a stop sign at the intersection.
     
     If such information is not available for an intersection, this property’s value is `nil`.
     */
    public let stopSign: Bool?
    
    /**
     Indicates whether there is a yield sign at the intersection.
     
     If such information is not available for an intersection, this property’s value is `nil`.
     */
    public let yieldSign: Bool?
}

extension Intersection: Codable {
    private enum CodingKeys: String, CodingKey {
        case outletIndexes = "entry"
        case headings = "bearings"
        case location
        case approachIndex = "in"
        case outletIndex = "out"
        case lanes
        case outletRoadClasses = "classes"
        case tollCollection = "toll_collection"
        case tunnelName = "tunnelName"
        case mapboxStreets = "mapbox_streets_v8"
        case isUrban = "is_urban"
        case restStop = "rest_stop"
        case administrativeRegionIndex = "admin_index"
        case geometryIndex = "geometry_index"
        case railroadCrossing = "railway_crossing"
        case trafficSignal = "traffic_signal"
        case stopSign = "stop_sign"
        case yieldSign = "yield_sign"
    }
    
    /// Used to code `Intersection.outletMapboxStreetsRoadClass`
    private struct MapboxStreetClassCodable: Codable, ForeignMemberContainer {
        var foreignMembers: JSONObject = [:]
        
        private enum CodingKeys: String, CodingKey {
            case streetClass = "class"
        }
        
        let streetClass: MapboxStreetsRoadClass?
        
        init(streetClass: MapboxStreetsRoadClass?) {
            self.streetClass = streetClass
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            if let classString = try container.decodeIfPresent(String.self, forKey: .streetClass) {
                streetClass = MapboxStreetsRoadClass(rawValue: classString)
            } else {
                streetClass = nil
            }
            
            try decodeForeignMembers(notKeyedBy: CodingKeys.self, with: decoder)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(streetClass, forKey: .streetClass)
            
            try encodeForeignMembers(notKeyedBy: CodingKeys.self, to: encoder)
        }
    }

    static func encode(intersections: [Intersection],
                       to parentContainer: inout UnkeyedEncodingContainer,
                       administrativeRegionIndices: [Int?]?,
                       segmentIndicesByIntersection: [Int?]?) throws {
        guard administrativeRegionIndices == nil || administrativeRegionIndices?.count == intersections.count else {
            let error = EncodingError.Context(codingPath: parentContainer.codingPath,
                                              debugDescription: "`administrativeRegionIndices` should be `nil` or match provided `intersections` to encode")
            throw EncodingError.invalidValue(administrativeRegionIndices as Any, error)
        }
        guard segmentIndicesByIntersection == nil || segmentIndicesByIntersection?.count == intersections.count else {
            let error = EncodingError.Context(codingPath: parentContainer.codingPath,
                                              debugDescription: "`segmentIndicesByIntersection` should be `nil` or match provided `intersections` to encode")
            throw EncodingError.invalidValue(segmentIndicesByIntersection as Any, error)
        }
        
        for (index, intersection) in intersections.enumerated() {
            var adminIndex: Int?
            var geometryIndex: Int?
            if index < administrativeRegionIndices?.count ?? -1 {
                adminIndex = administrativeRegionIndices?[index]
                geometryIndex = segmentIndicesByIntersection?[index]
            }
            
            try intersection.encode(to: parentContainer.superEncoder(),
                                    administrativeRegionIndex: adminIndex,
                                    geometryIndex: geometryIndex)
        }
    }

    
    public func encode(to encoder: Encoder) throws {
        try encode(to: encoder, administrativeRegionIndex: nil, geometryIndex: nil)
    }
    
    func encode(to encoder: Encoder, administrativeRegionIndex: Int?, geometryIndex: Int?) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(LocationCoordinate2DCodable(location), forKey: .location)
        try container.encode(headings, forKey: .headings)
        
        try container.encodeIfPresent(approachIndex, forKey: .approachIndex)
        try container.encodeIfPresent(outletIndex, forKey: .outletIndex)
        
        var outletArray = headings.map { _ in false }
        for index in outletIndexes {
            outletArray[index] = true
        }
        
        try container.encode(outletArray, forKey: .outletIndexes)
        
        var lanes: [Lane]?
        if let approachLanes = approachLanes,
            let usableApproachLanes = usableApproachLanes,
            let preferredApproachLanes = preferredApproachLanes
        {
            lanes = approachLanes.map { Lane(indications: $0) }
            for i in usableApproachLanes {
                lanes?[i].isValid = true
                if let usableLaneIndication = usableLaneIndication,
                   let validLanes = lanes,
                   validLanes[i].indications.descriptions.contains(usableLaneIndication.rawValue) {
                    lanes?[i].validIndication = usableLaneIndication
                }
                if usableApproachLanes.count == lanesForeignMembers.count {
                    lanes?[i].foreignMembers = lanesForeignMembers[i]
                }
            }
            
            for j in preferredApproachLanes {
                lanes?[j].isActive = true
            }
        }
        try container.encodeIfPresent(lanes, forKey: .lanes)
        
        if let classes = outletRoadClasses?.description.components(separatedBy: ",").filter({ !$0.isEmpty }) {
            try container.encode(classes, forKey: .outletRoadClasses)
        }

        if let tolls = tollCollection {
            try container.encode(tolls, forKey: .tollCollection)
        }

        if let outletMapboxStreetsRoadClass = outletMapboxStreetsRoadClass {
            try container.encode(MapboxStreetClassCodable(streetClass: outletMapboxStreetsRoadClass), forKey: .mapboxStreets)
        }
        
        if let isUrban = isUrban {
            try container.encode(isUrban, forKey: .isUrban)
        }

        if let restStop = restStop {
            try container.encode(restStop, forKey: .restStop)
        }

        if let tunnelName = tunnelName {
            try container.encode(tunnelName, forKey: .tunnelName)
        }

        if let adminIndex = administrativeRegionIndex {
            try container.encode(adminIndex, forKey: .administrativeRegionIndex)
        }
        
        if let geoIndex = geometryIndex {
            try container.encode(geoIndex, forKey: .geometryIndex)
        }
        
        if let railwayCrossing = railroadCrossing {
            try container.encode(railwayCrossing, forKey: .railroadCrossing)
        }
        
        if let trafficSignal = trafficSignal {
            try container.encode(trafficSignal, forKey: .trafficSignal)
        }
        
        if let stopSign = stopSign {
            try container.encode(stopSign, forKey: .stopSign)
        }
        
        if let yieldSign = yieldSign {
            try container.encode(yieldSign, forKey: .yieldSign)
        }
        
        try encodeForeignMembers(notKeyedBy: CodingKeys.self, to: encoder)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        location = try container.decode(LocationCoordinate2DCodable.self, forKey: .location).decodedCoordinates
        headings = try container.decode([LocationDirection].self, forKey: .headings)
        
        if let lanes = try container.decodeIfPresent([Lane].self, forKey: .lanes) {
            lanesForeignMembers = lanes.map(\.foreignMembers)
            approachLanes = lanes.map { $0.indications }
            
            usableApproachLanes = lanes.indices { $0.isValid }
            preferredApproachLanes = lanes.indices { ($0.isActive ?? false) }
            let validIndications = lanes.compactMap { $0.validIndication}
            if Set(validIndications).count > 1 {
                let context = EncodingError.Context(codingPath: decoder.codingPath, debugDescription: "Inconsistent valid indications.")
                throw EncodingError.invalidValue(validIndications, context)
            }
            usableLaneIndication = validIndications.first
        } else {
            approachLanes = nil
            usableApproachLanes = nil
            preferredApproachLanes = nil
            usableLaneIndication = nil
        }
        
        outletRoadClasses = try container.decodeIfPresent(RoadClasses.self, forKey: .outletRoadClasses)
        
        let outletsArray = try container.decode([Bool].self, forKey: .outletIndexes)
        outletIndexes = outletsArray.indices { $0 }
        
        outletIndex = try container.decodeIfPresent(Int.self, forKey: .outletIndex)
        approachIndex = try container.decodeIfPresent(Int.self, forKey: .approachIndex)

        tollCollection = try container.decodeIfPresent(TollCollection.self, forKey: .tollCollection)

        tunnelName = try container.decodeIfPresent(String.self, forKey: .tunnelName)

        outletMapboxStreetsRoadClass = try container.decodeIfPresent(MapboxStreetClassCodable.self, forKey: .mapboxStreets)?.streetClass
        
        isUrban = try container.decodeIfPresent(Bool.self, forKey: .isUrban)

        restStop = try container.decodeIfPresent(RestStop.self, forKey: .restStop)
        
        railroadCrossing = try container.decodeIfPresent(Bool.self, forKey: .railroadCrossing)
        trafficSignal = try container.decodeIfPresent(Bool.self, forKey: .trafficSignal)
        stopSign = try container.decodeIfPresent(Bool.self, forKey: .stopSign)
        yieldSign = try container.decodeIfPresent(Bool.self, forKey: .yieldSign)
        
        try decodeForeignMembers(notKeyedBy: CodingKeys.self, with: decoder)
    }
}

extension Intersection: Equatable {
    public static func == (lhs: Intersection, rhs: Intersection) -> Bool {
        return lhs.location == rhs.location &&
            lhs.headings == rhs.headings &&
            lhs.outletIndexes == rhs.outletIndexes &&
            lhs.approachIndex == rhs.approachIndex &&
            lhs.outletIndex == rhs.outletIndex &&
            lhs.approachLanes == rhs.approachLanes &&
            lhs.usableApproachLanes == rhs.usableApproachLanes &&
            lhs.preferredApproachLanes == rhs.preferredApproachLanes &&
            lhs.usableLaneIndication == rhs.usableLaneIndication &&
            lhs.restStop == rhs.restStop &&
            lhs.regionCode == rhs.regionCode &&
            lhs.outletMapboxStreetsRoadClass == rhs.outletMapboxStreetsRoadClass &&
            lhs.outletRoadClasses == rhs.outletRoadClasses &&
            lhs.tollCollection == rhs.tollCollection &&
            lhs.tunnelName == rhs.tunnelName &&
            lhs.isUrban == rhs.isUrban &&
            lhs.railroadCrossing == rhs.railroadCrossing &&
            lhs.trafficSignal == rhs.trafficSignal &&
            lhs.stopSign == rhs.stopSign &&
            lhs.yieldSign == rhs.yieldSign
    }
}

// Will automatically read localized Instructions.plist
let OSRMTextInstructionsStrings = NSDictionary(contentsOfFile: Bundle(for: OSRMInstructionFormatter.self).path(forResource: "Instructions", ofType: "plist")!)!

protocol Tokenized {
    associatedtype T

    /**
     Replaces `{tokens}` in the receiver using the given closure.
     */
    func replacingTokens(using interpolator: ((TokenType) -> T)) -> T
}

extension String: Tokenized {
    public var sentenceCased: String {
        return prefix(1).uppercased() + dropFirst()
    }

    public func replacingTokens(using interpolator: ((TokenType) -> String)) -> String {
        let scanner = Scanner(string: self)
        scanner.charactersToBeSkipped = nil
        var result = ""
        while !scanner.isAtEnd {
            var buffer: NSString?

            if scanner.scanUpTo("{", into: &buffer) {
                result += buffer! as String
            }
            guard scanner.scanString("{", into: nil) else {
                continue
            }

            var token: NSString?
            guard scanner.scanUpTo("}", into: &token) else {
                result += "{"
                continue
            }

            if scanner.scanString("}", into: nil) {
                if let tokenType = TokenType(description: token! as String) {
                    result += interpolator(tokenType)
                } else {
                    result += "{\(token!)}"
                }
            } else {
                result += "{\(token!)"
            }
        }

        // remove excess spaces
        result = result.replacingOccurrences(of: "\\s\\s", with: " ", options: .regularExpression)

        // capitalize
        let meta = OSRMTextInstructionsStrings["meta"] as! [String: Any]
        if meta["capitalizeFirstLetter"] as? Bool ?? false {
            result = result.sentenceCased
        }
        return result
    }
}

extension NSAttributedString: Tokenized {
    @objc public func replacingTokens(using interpolator: ((TokenType) -> NSAttributedString)) -> NSAttributedString {
        let scanner = Scanner(string: string)
        scanner.charactersToBeSkipped = nil
        let result = NSMutableAttributedString()
        while !scanner.isAtEnd {
            var buffer: NSString?

            if scanner.scanUpTo("{", into: &buffer) {
                result.append(NSAttributedString(string: buffer! as String))
            }
            guard scanner.scanString("{", into: nil) else {
                continue
            }

            var token: NSString?
            guard scanner.scanUpTo("}", into: &token) else {
                continue
            }

            if scanner.scanString("}", into: nil) {
                if let tokenType = TokenType(description: token! as String) {
                    result.append(interpolator(tokenType))
                }
            } else {
                result.append(NSAttributedString(string: token! as String))
            }
        }

        // remove excess spaces
        let wholeRange = NSRange(location: 0, length: result.mutableString.length)
        result.mutableString.replaceOccurrences(of: "\\s\\s", with: " ", options: .regularExpression, range: wholeRange)

        // capitalize
        let meta = OSRMTextInstructionsStrings["meta"] as! [String: Any]
        if meta["capitalizeFirstLetter"] as? Bool ?? false {
            result.replaceCharacters(in: NSRange(location: 0, length: 1), with: String(result.string.first!).uppercased())
        }
        return result as NSAttributedString
    }
}

@objc public class OSRMInstructionFormatter: Formatter {
    let version: String
    let instructions: [String: Any]

    let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .current
        if #available(iOS 9.0, OSX 10.11, *) {
            formatter.numberStyle = .ordinal
        }
        return formatter
    }()

    @objc public init(version: String) {
        self.version = version
        self.instructions = OSRMTextInstructionsStrings[version] as! [String: Any]

        super.init()
    }

    required public init?(coder decoder: NSCoder) {
        if let version = decoder.decodeObject(of: NSString.self, forKey: "version") as String? {
            self.version = version
        } else {
            return nil
        }

        if let instructions = decoder.decodeObject(of: [NSDictionary.self, NSArray.self, NSString.self], forKey: "instructions") as? [String: Any] {
            self.instructions = instructions
        } else {
            return nil
        }

        super.init(coder: decoder)
    }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)

        coder.encode(version, forKey: "version")
        coder.encode(instructions, forKey: "instructions")
    }

    var constants: [String: Any] {
        return instructions["constants"] as! [String: Any]
    }

    /**
     Returns a format string with the given name.

     - returns: A format string suitable for `String.replacingTokens(using:)`.
     */
    @objc public func phrase(named name: PhraseName) -> String {
        let phrases = instructions["phrase"] as! [String: String]
        return phrases["\(name)"]!
    }

    func laneConfig(intersection: Intersection) -> String? {
        guard let approachLanes = intersection.approachLanes else {
            return ""
        }

        guard let useableApproachLanes = intersection.usableApproachLanes else {
            return ""
        }

        // find lane configuration
        var config = Array(repeating: "x", count: approachLanes.count)
        for index in useableApproachLanes {
            config[index] = "o"
        }

        // reduce lane configurations to common cases
        var current = ""
        return config.reduce("", {
            (result: String?, lane: String) -> String? in
            if (lane != current) {
                current = lane
                return result! + lane
            } else {
                return result
            }
        })
    }

    func directionFromDegree(degree: Int?) -> String {
        guard let degree = degree else {
            // step had no bearing_after degree, ignoring
            return ""
        }

        // fetch locatized compass directions strings
        let directions = constants["direction"] as! [String: String]

        // Transform degrees to their translated compass direction
        switch degree {
        case 340...360, 0...20:
            return directions["north"]!
        case 20..<70:
            return directions["northeast"]!
        case 70...110:
            return directions["east"]!
        case 110..<160:
            return directions["southeast"]!
        case 160...200:
            return directions["south"]!
        case 200..<250:
            return directions["southwest"]!
        case 250...290:
            return directions["west"]!
        case 290..<340:
            return directions["northwest"]!
        default:
            return "";
        }
    }

    typealias InstructionsByToken = [String: String]
    typealias InstructionsByModifier = [String: InstructionsByToken]

    override public func string(for obj: Any?) -> String? {
        return string(for: obj, legIndex: nil, numberOfLegs: nil, roadClasses: nil, modifyValueByKey: nil)
    }

    /**
     Creates an instruction given a step and options.

     - parameter step: The step to format.
     - parameter legIndex: Current leg index the user is currently on.
     - parameter numberOfLegs: Total number of `RouteLeg` for the given `Route`.
     - parameter roadClasses: Option set representing the classes of road for the `RouteStep`.
     - parameter modifyValueByKey: Allows for mutating the instruction at given parts of the instruction.
     - returns: An instruction as a `String`.
     */
    public func string(for obj: Any?, legIndex: Int?, numberOfLegs: Int?, roadClasses: RoadClasses? = RoadClasses([]), modifyValueByKey: ((TokenType, String) -> String)?) -> String? {
        guard let obj = obj else {
            return nil
        }

        var modifyAttributedValueByKey: ((TokenType, NSAttributedString) -> NSAttributedString)?
        if let modifyValueByKey = modifyValueByKey {
            modifyAttributedValueByKey = { (key: TokenType, value: NSAttributedString) -> NSAttributedString in
                return NSAttributedString(string: modifyValueByKey(key, value.string))
            }
        }
        return attributedString(for: obj, legIndex: legIndex, numberOfLegs: numberOfLegs, roadClasses: roadClasses, modifyValueByKey: modifyAttributedValueByKey)?.string
    }

    /**
     Creates an instruction as an attributed string given a step and options.

     - parameter obj: The step to format.
     - parameter attrs: The default attributes to use for the returned attributed string.
     - parameter legIndex: Current leg index the user is currently on.
     - parameter numberOfLegs: Total number of `RouteLeg` for the given `Route`.
     - parameter roadClasses: Option set representing the classes of road for the `RouteStep`.
     - parameter modifyValueByKey: Allows for mutating the instruction at given parts of the instruction.
     - returns: An instruction as an `NSAttributedString`.
     */
    public func attributedString(for obj: Any, withDefaultAttributes attrs: [NSAttributedStringKey: Any]? = nil, legIndex: Int?, numberOfLegs: Int?, roadClasses: RoadClasses? = RoadClasses([]), modifyValueByKey: ((TokenType, NSAttributedString) -> NSAttributedString)?) -> NSAttributedString? {
        guard let step = obj as? RouteStep else {
            return nil
        }

        var type = step.maneuverType
        let modifier = step.maneuverDirection?.rawValue.description
//        let modifier = step.maneuverDirection.description
        let mode = step.transportType

        if type != .depart && type != .arrive && modifier == .none {
            return nil
        }

        if instructions[type.rawValue.description] == nil {
            // OSRM specification assumes turn types can be added without
            // major version changes. Unknown types are to be treated as
            // type `turn` by clients
            type = .turn
        }

        var instructionObject: InstructionsByToken
        var rotaryName = ""
        var wayName: NSAttributedString
        switch type {
        case .takeRotary, .takeRoundabout:
            // Special instruction types have an intermediate level keyed to “default”.
            let instructionsByModifier = instructions[type.rawValue.description] as! [String: InstructionsByModifier]
            let defaultInstructions = instructionsByModifier["default"]!

            wayName = NSAttributedString(string: step.exitNames?.first ?? "", attributes: attrs)
            if let _rotaryName = step.names?.first, let _ = step.exitIndex, let obj = defaultInstructions["name_exit"] {
                instructionObject = obj
                rotaryName = _rotaryName
            } else if let _rotaryName = step.names?.first, let obj = defaultInstructions["name"] {
                instructionObject = obj
                rotaryName = _rotaryName
            } else if let _ = step.exitIndex, let obj = defaultInstructions["exit"] {
                instructionObject = obj
            } else {
                instructionObject = defaultInstructions["default"]!
            }
        default:
            var typeInstructions = instructions[type.rawValue.description] as! InstructionsByModifier
            let modesInstructions = instructions["modes"] as? InstructionsByModifier
            if let modesInstructions = modesInstructions, let modesInstruction = modesInstructions[mode.rawValue.description] {
                instructionObject = modesInstruction
            } else if let typeInstruction = typeInstructions[modifier!] {
                instructionObject = typeInstruction
            } else {
                instructionObject = typeInstructions["default"]!
            }

            // Set wayName
            let name = step.names?.first
            let ref = step.codes?.first
            let isMotorway = roadClasses?.contains(.motorway) ?? false

            if let name = name, let ref = ref, name != ref, !isMotorway {
                let attributedName = NSAttributedString(string: name, attributes: attrs)
                let attributedRef = NSAttributedString(string: ref, attributes: attrs)
                let phrase = NSAttributedString(string: self.phrase(named: .nameWithCode), attributes: attrs)
                wayName = phrase.replacingTokens(using: { (tokenType) -> NSAttributedString in
                    switch tokenType {
                    case .wayName:
                        return modifyValueByKey?(.wayName, attributedName) ?? attributedName
                    case .code:
                        return modifyValueByKey?(.code, attributedRef) ?? attributedRef
                    default:
                        fatalError("Unexpected token type \(tokenType) in name-and-ref phrase")
                    }
                })
            } else if let ref = ref, isMotorway, let decimalRange = ref.rangeOfCharacter(from: .decimalDigits), !decimalRange.isEmpty {
                let attributedRef = NSAttributedString(string: ref, attributes: attrs)
                if let modifyValueByKey = modifyValueByKey {
                    wayName = modifyValueByKey(.code, attributedRef)
                } else {
                    wayName = attributedRef
                }
            } else if name == nil, let ref = ref {
                let attributedRef = NSAttributedString(string: ref, attributes: attrs)
                if let modifyValueByKey = modifyValueByKey {
                    wayName = modifyValueByKey(.code, attributedRef)
                } else {
                    wayName = attributedRef
                }
            } else if let name = name {
                let attributedName = NSAttributedString(string: name, attributes: attrs)
                if let modifyValueByKey = modifyValueByKey {
                    wayName = modifyValueByKey(.wayName, attributedName)
                } else {
                    wayName = attributedName
                }
            } else {
                wayName = NSAttributedString()
            }
        }

        // Special case handling
        var laneInstruction: String?
        switch type {
        case .useLane:
            var laneConfig: String?
            if let intersection = step.intersections?.first {
                laneConfig = self.laneConfig(intersection: intersection)
            }
            let laneInstructions = constants["lanes"] as! [String: String]
            laneInstruction = laneInstructions[laneConfig ?? ""]

            if laneInstruction == nil {
                // Lane configuration is not found, default to continue
                let useLaneConfiguration = instructions["use lane"] as! InstructionsByModifier
                instructionObject = useLaneConfiguration["no_lanes"]!
            }
        default:
            break
        }

        // Decide which instruction string to use
        // Destination takes precedence over name
        var instruction: String
        if let _ = step.destinations ?? step.destinationCodes, let _ = step.exitCodes?.first, let obj = instructionObject["exit_destination"] {
            instruction = obj
        } else if let _ = step.destinations ?? step.destinationCodes, let obj = instructionObject["destination"] {
            instruction = obj
        } else if let _ = step.exitCodes?.first, let obj = instructionObject["exit"] {
            instruction = obj
        } else if !wayName.string.isEmpty, let obj = instructionObject["name"] {
            instruction = obj
        } else {
            instruction = instructionObject["default"]!
        }

        // Prepare token replacements
        var nthWaypoint: String? = nil
        if let legIndex = legIndex, let numberOfLegs = numberOfLegs, legIndex != numberOfLegs - 1 {
            nthWaypoint = ordinalFormatter.string(from: (legIndex + 1) as NSNumber)
        }
        let exitCode = step.exitCodes?.first ?? ""
        let destination = [step.destinationCodes, step.destinations].flatMap { $0?.first }.joined(separator: ": ")
        var exitOrdinal: String = ""
        if let exitIndex = step.exitIndex, exitIndex <= 10 {
            exitOrdinal = ordinalFormatter.string(from: exitIndex as NSNumber)!
        }
        let modifierConstants = constants["modifier"] as! [String: String]
        let modifierConstant = modifierConstants[(modifier == "none" ? "straight" : modifier)!]!
        var bearing: Int? = nil
        if step.finalHeading != nil { bearing = Int(step.finalHeading! as Double) }

        // Replace tokens
        let result = NSAttributedString(string: instruction, attributes: attrs).replacingTokens { (tokenType) -> NSAttributedString in
            var replacement: String
            switch tokenType {
            case .code: replacement = step.codes?.first ?? ""
            case .wayName: replacement = "" // ignored
            case .destination: replacement = destination
            case .exitCode: replacement = exitCode
            case .exitIndex: replacement = exitOrdinal
            case .rotaryName: replacement = rotaryName
            case .laneInstruction: replacement = laneInstruction ?? ""
            case .modifier: replacement = modifierConstant
            case .direction: replacement = directionFromDegree(degree: bearing)
            case .wayPoint: replacement = nthWaypoint ?? ""
            case .firstInstruction, .secondInstruction, .distance:
                fatalError("Unexpected token type \(tokenType) in individual instruction")
            }
            if tokenType == .wayName {
                return wayName // already modified above
            } else {
                let attributedReplacement = NSAttributedString(string: replacement, attributes: attrs)
                return modifyValueByKey?(tokenType, attributedReplacement) ?? attributedReplacement
            }
        }

        return result
    }

    override public func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        return false
    }
}
