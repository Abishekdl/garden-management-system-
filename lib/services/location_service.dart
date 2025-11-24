import 'dart:async';
import 'dart:convert'; // For jsonEncode
import 'package:http/http.dart' as http; // For making HTTP requests
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/vit_location_mapper.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamController<Position>? _locationStreamController;
  StreamSubscription<LocationData>? _locationUpdateSubscription; // For background updates

  Future<void> initialize() async {
    await requestLocationPermission();
  }

  Stream<LocationData> getLocationStream() {
    if (_locationStreamController == null) {
      _locationStreamController = StreamController<Position>.broadcast();
      _startLocationUpdates();
    }
    return _locationStreamController!.stream.asyncMap((position) async {
      String address = await getAddressFromCoordinates(position.latitude, position.longitude);
      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        timestamp: position.timestamp ?? DateTime.now(),
        address: address,
      );
    });
  }

  void _startLocationUpdates() async {
    bool serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      _locationStreamController!.addError(LocationServiceDisabledException());
      return;
    }

    bool hasPermission = await requestLocationPermission();
    if (!hasPermission) {
      _locationStreamController!.addError(PermissionDeniedException('Location permission denied'));
      return;
    }

    Geolocator.getPositionStream().listen((Position position) {
      _locationStreamController!.add(position);
    }, onError: (e) {
      _locationStreamController!.addError(e);
    });
  }

  void disposeLocationStream() {
    _locationStreamController?.close();
    _locationStreamController = null;
  }

  /// ## NEW: Start sending location updates to the server ##
  void startSendingLocationUpdates({
    required String userType,
    required String userId,
  }) {
    // Stop any existing update streams
    stopSendingLocationUpdates();

    // Get the location stream
    _locationUpdateSubscription = getLocationStream().listen(
      (LocationData locationData) async {
        try {
          final response = await http.post(
            // ## FIXED: Use the correct server URL ##
            Uri.parse('http://10.117.108.82:5000/update_location'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_type': userType,
              'user_id': userId,
              'latitude': locationData.latitude,
              'longitude': locationData.longitude,
              'accuracy': locationData.accuracy,
              'timestamp': locationData.timestamp.toIso8601String(),
              'address': locationData.address,
            }),
          );

          if (response.statusCode == 200) {
            print('Location update sent successfully.');
          } else {
            print('Failed to send location update: ${response.statusCode}');
          }
        } catch (e) {
          print('Error sending location update: $e');
        }
      },
      onError: (error) {
        print("Error in location update stream: $error");
      },
    );
  }

  /// ## NEW: Stop sending location updates ##
  void stopSendingLocationUpdates() {
    _locationUpdateSubscription?.cancel();
    _locationUpdateSubscription = null;
  }

  /// Request location permissions from the user
  Future<bool> requestLocationPermission() async {
    try {
      // Check current permission status
      PermissionStatus permission = await Permission.location.status;
      
      if (permission.isGranted) {
        return true;
      }
      
      // Request permission if not granted
      if (permission.isDenied) {
        permission = await Permission.location.request();
        
        if (permission.isGranted) {
          return true;
        }
      }
      
      // Handle permanent denial
      if (permission.isPermanentlyDenied) {
        // Guide user to settings
        await openAppSettings();
        return false;
      }
      
      return false;
    } catch (e) {
      print('Error requesting location permission: $e');
      return false;
    }
  }

  /// Check if location services are enabled on the device
  Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      print('Error checking location service: $e');
      return false;
    }
  }

  /// Get current GPS position
  Future<Position?> getCurrentPosition() async {
    try {
      // Check permissions first
      bool hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        print('Location permission denied');
        return null;
      }

      // Check if location services are enabled
      bool serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled');
        throw LocationServiceDisabledException();
      }

      // Get current position with high accuracy
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      print('GPS Position obtained: ${position.latitude}, ${position.longitude}');
      return position;
    } on TimeoutException {
      print('Location timeout - trying with lower accuracy');
      try {
        // Retry with medium accuracy and longer timeout
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 15),
        );
        return position;
      } catch (e) {
        print('Location retry failed: $e');
        return null;
      }
    } on LocationServiceDisabledException {
      print('Location services are disabled');
      return null;
    } on PermissionDeniedException {
      print('Location permissions are denied');
      return null;
    } catch (e) {
      print('Error getting current position: $e');
      return null;
    }
  }

  /// Convert GPS coordinates to readable address with VIT campus block detection
  Future<String> getAddressFromCoordinates(double latitude, double longitude) async {
    try {
      // First, check if within VIT campus and get specific block
      if (VITLocationMapper.isWithinVITCampus(latitude, longitude)) {
        List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
        String genericAddress = 'VIT University Vellore';
        
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          String locationName = place.name ?? '';
          
          if (locationName.toLowerCase().contains('vit')) {
            genericAddress = locationName;
          } else if (place.locality != null && place.locality!.isNotEmpty) {
            genericAddress = place.locality!;
          }
        }
        
        // Get specific block location using our mapper
        String specificLocation = VITLocationMapper.getSpecificLocation(
          latitude,
          longitude,
          genericAddress,
        );
        
        print('📍 VIT Location: $specificLocation (${latitude}, ${longitude})');
        return specificLocation;
      }
      
      // Not in VIT campus, use regular geocoding
      List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
      
      if (placemarks.isEmpty) {
        return 'Unknown Location';
      }

      Placemark place = placemarks[0];
      
      // Build formatted address - focus on location name only
      String locationName = place.name ?? '';
      
      // Check for Vellore Fort specifically
      if (locationName.toLowerCase().contains('fort')) {
        return 'Vellore Fort';
      }
      
      // For other locations, use locality or name
      if (place.locality != null && place.locality!.isNotEmpty) {
        return place.locality!;
      }
      if (locationName.isNotEmpty) {
        return locationName;
      }
      if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
        return place.administrativeArea!;
      }
      
      return 'Unknown Location';
    } catch (e) {
      print('Error getting address from coordinates: $e');
      return 'Unknown Location';
    }
  }

  /// Get location with address information
  Future<LocationData?> getCurrentLocationWithAddress() async {
    try {
      Position? position = await getCurrentPosition();
      
      if (position == null) {
        return null;
      }

      String address = await getAddressFromCoordinates(
        position.latitude, 
        position.longitude
      );

      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        timestamp: position.timestamp ?? DateTime.now(),
        address: address,
      );
    } catch (e) {
      print('Error getting location with address: $e');
      return null;
    }
  }

  /// Calculate distance between two coordinates in meters
  double calculateDistance(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  /// Format distance for display
  String formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toStringAsFixed(0)} m';
    } else {
      double distanceInKm = distanceInMeters / 1000;
      return '${distanceInKm.toStringAsFixed(1)} km';
    }
  }
}

/// Data class to hold location information
class LocationData {
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;
  final String address;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
    required this.address,
  });

  /// Convert to JSON for server upload
  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'timestamp': timestamp.toIso8601String(),
      'address': address,
    };
  }

  /// Create from JSON
  factory LocationData.fromJson(Map<String, dynamic> json) {
    return LocationData(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.parse(json['timestamp'] as String? ?? DateTime.now().toIso8601String()),
      address: json['address'] as String? ?? 'Unknown Location',
    );
  }

  /// Check if location has high accuracy (< 10 meters)
  bool get isHighAccuracy => accuracy < 10.0;

  @override
  String toString() {
    return 'LocationData(address: $address)';
  }

  LocationData copyWith({
    double? latitude,
    double? longitude,
    double? accuracy,
    DateTime? timestamp,
    String? address,
  }) {
    return LocationData(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      timestamp: timestamp ?? this.timestamp,
      address: address ?? this.address,
    );
  }
}