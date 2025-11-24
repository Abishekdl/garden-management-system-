import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:map_launcher/map_launcher.dart';

class NavigationHelper {
  /// Launch Google Maps navigation to a specific location
  /// This uses the free Google Maps Intent - no paid API required
  static Future<void> navigateToLocation({
    required BuildContext context,
    required double latitude,
    required double longitude,
    String? locationName,
  }) async {
    try {
      // Check if any map apps are available
      final availableMaps = await MapLauncher.installedMaps;
      
      if (availableMaps.isEmpty) {
        _showError(context, 'No map applications found. Please install Google Maps.');
        return;
      }

      // Show map selection dialog if multiple apps available
      if (availableMaps.length > 1) {
        await _showMapSelectionDialog(
          context: context,
          availableMaps: availableMaps,
          latitude: latitude,
          longitude: longitude,
          locationName: locationName,
        );
      } else {
        // Launch the only available map app
        await _launchMap(
          availableMaps.first,
          latitude: latitude,
          longitude: longitude,
          locationName: locationName,
        );
      }
    } catch (e) {
      print('Error launching navigation: $e');
      _showError(context, 'Failed to launch navigation: $e');
    }
  }

  /// Show dialog to select which map app to use
  static Future<void> _showMapSelectionDialog({
    required BuildContext context,
    required List<AvailableMap> availableMaps,
    required double latitude,
    required double longitude,
    String? locationName,
  }) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Choose Navigation App'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: availableMaps.map((map) {
              return ListTile(
                leading: Image.asset(
                  map.icon,
                  width: 32,
                  height: 32,
                ),
                title: Text(map.mapName),
                onTap: () {
                  Navigator.of(context).pop();
                  _launchMap(
                    map,
                    latitude: latitude,
                    longitude: longitude,
                    locationName: locationName,
                  );
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  /// Launch the selected map app with navigation
  static Future<void> _launchMap(
    AvailableMap map, {
    required double latitude,
    required double longitude,
    String? locationName,
  }) async {
    await map.showDirections(
      destination: Coords(latitude, longitude),
      destinationTitle: locationName ?? 'Report Location',
      directionsMode: DirectionsMode.walking, // Default to walking for campus
    );
  }

  /// Fallback method using URL launcher (if map_launcher fails)
  static Future<void> navigateToLocationFallback({
    required BuildContext context,
    required double latitude,
    required double longitude,
  }) async {
    try {
      // Try Google Maps first (most common)
      final googleMapsUrl = Uri.parse(
        'google.navigation:q=$latitude,$longitude&mode=w', // w = walking
      );
      
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
        return;
      }

      // Fallback to universal maps URL
      final universalMapsUrl = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude&travelmode=walking',
      );
      
      if (await canLaunchUrl(universalMapsUrl)) {
        await launchUrl(universalMapsUrl, mode: LaunchMode.externalApplication);
        return;
      }

      _showError(context, 'No navigation app available');
    } catch (e) {
      print('Error in fallback navigation: $e');
      _showError(context, 'Failed to launch navigation: $e');
    }
  }

  /// Show location on map (view only, no navigation)
  static Future<void> showLocationOnMap({
    required BuildContext context,
    required double latitude,
    required double longitude,
    String? locationName,
  }) async {
    try {
      final availableMaps = await MapLauncher.installedMaps;
      
      if (availableMaps.isEmpty) {
        _showError(context, 'No map applications found');
        return;
      }

      // Use the first available map to show the location
      await availableMaps.first.showMarker(
        coords: Coords(latitude, longitude),
        title: locationName ?? 'Report Location',
        description: 'Maintenance report location',
      );
    } catch (e) {
      print('Error showing location: $e');
      _showError(context, 'Failed to show location: $e');
    }
  }

  /// Show error message
  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Calculate distance between two coordinates (in meters)
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // meters
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    
    final double a = 
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
      math.sin(dLon / 2) * math.sin(dLon / 2);
    
    final double c = 2 * math.asin(math.sqrt(a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }

  /// Format distance for display
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }
}
