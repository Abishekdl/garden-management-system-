import 'dart:math';

class VITLocationMapper {
  // VIT Campus blocks with their exact GPS coordinates
  static final List<Map<String, dynamic>> vitBlocks = [
    {
      'name': 'GDN Block',
      'fullName': 'VIT University - GDN Block',
      'lat': 12.96991,
      'lng': 79.15482,
      'radius': 80,
    },
    {
      'name': 'MGR Block',
      'fullName': 'VIT University - MGR Block',
      'lat': 12.96909,
      'lng': 79.15583,
      'radius': 80,
    },
    {
      'name': 'Periyar Library',
      'fullName': 'VIT University - Periyar Library',
      'lat': 12.96917,
      'lng': 79.15687,
      'radius': 80,
    },
    {
      'name': 'SMV Block',
      'fullName': 'VIT University - SMV Block',
      'lat': 12.96934,
      'lng': 79.15764,
      'radius': 80,
    },
    {
      'name': 'TT Block',
      'fullName': 'VIT University - TT Block',
      'lat': 12.97081,
      'lng': 79.15953,
      'radius': 80,
    },
    {
      'name': 'SJT Block',
      'fullName': 'VIT University - SJT Block',
      'lat': 12.97113,
      'lng': 79.16368,
      'radius': 80,
    },
    {
      'name': 'SJT Foody',
      'fullName': 'VIT University - SJT Foody',
      'lat': 12.97107,
      'lng': 79.16438,
      'radius': 60,
    },
    {
      'name': 'PRP Block',
      'fullName': 'VIT University - PRP Block',
      'lat': 12.97117,
      'lng': 79.16640,
      'radius': 80,
    },
    {
      'name': 'Greenos near PRP',
      'fullName': 'VIT University - Greenos near PRP',
      'lat': 12.97149,
      'lng': 79.16515,
      'radius': 60,
    },
    {
      'name': 'MGB Block',
      'fullName': 'VIT University - MGB Block',
      'lat': 12.97215,
      'lng': 79.16797,
      'radius': 80,
    },
  ];

  /// Calculate distance between two GPS coordinates in meters
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // meters
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) {
    return degrees * pi / 180;
  }

  /// Get specific location name based on distance from VIT blocks
  /// Returns detailed location based on distance to nearest block:
  /// - 0-50m: "[Block Name], VIT University" (e.g., "PRP Block, VIT University")
  /// - 50-100m: "Near [Block Name], VIT University" (e.g., "Near PRP Block, VIT University")
  /// - 100m+: Just place name without block reference (e.g., "Arani", "Gudiyatham")
  static String getSpecificLocation(
    double latitude,
    double longitude,
    String genericAddress,
  ) {
    // Find nearest block and its distance
    Map<String, dynamic>? nearestBlock;
    double minDistance = double.infinity;

    for (final block in vitBlocks) {
      final double distance = calculateDistance(
        latitude,
        longitude,
        block['lat'],
        block['lng'],
      );

      if (distance < minDistance) {
        minDistance = distance;
        nearestBlock = block;
      }
    }

    // Check distance to nearest block
    if (nearestBlock != null && minDistance <= 100) {
      // 0-50 meters: Show exact block name with VIT University
      if (minDistance <= 50) {
        return '${nearestBlock['name']}, VIT University';
      }
      
      // 50-100 meters: Show "Near [Block]" with VIT University
      return 'Near ${nearestBlock['name']}, VIT University';
    }

    // More than 100 meters from any block: Show only the place name (no block reference)
    // Extract just the place name from the generic address
    String placeName = _extractPlaceName(genericAddress);
    return placeName;
  }

  /// Extract clean place name from generic address
  /// Removes unnecessary details and returns just the place name
  static String _extractPlaceName(String address) {
    if (address.isEmpty) {
      return 'Unknown Location';
    }

    // Remove common suffixes and prefixes
    String cleaned = address
        .replaceAll(', Tamil Nadu', '')
        .replaceAll(', India', '')
        .replaceAll('VIT University', '')
        .replaceAll('Vellore', '')
        .replaceAll(RegExp(r'\s+'), ' ') // Replace multiple spaces with single space
        .trim();
    
    // If address has commas, take the first meaningful part
    if (cleaned.contains(',')) {
      List<String> parts = cleaned.split(',');
      for (String part in parts) {
        String trimmed = part.trim();
        // Skip empty, unnamed, road names, and very short strings
        if (trimmed.isNotEmpty && 
            !trimmed.toLowerCase().contains('unnamed') &&
            !trimmed.toLowerCase().contains('road') &&
            !trimmed.toLowerCase().contains('street') &&
            !trimmed.toLowerCase().contains('near') &&
            trimmed.length > 2) {
          return trimmed;
        }
      }
    }
    
    // If no commas or no good parts found, return cleaned address
    if (cleaned.isEmpty || cleaned.toLowerCase().contains('unnamed')) {
      return 'Unknown Location';
    }
    
    return cleaned;
  }

  /// Get short block name (for display in compact spaces)
  static String getShortBlockName(String fullLocation) {
    for (final block in vitBlocks) {
      if (fullLocation.contains(block['name'])) {
        return block['name'];
      }
    }
    return 'VIT Campus';
  }

  /// Check if location is within VIT campus
  static bool isWithinVITCampus(double latitude, double longitude) {
    const double vitMinLat = 12.965;
    const double vitMaxLat = 12.980;
    const double vitMinLng = 79.150;
    const double vitMaxLng = 79.170;

    return latitude >= vitMinLat &&
        latitude <= vitMaxLat &&
        longitude >= vitMinLng &&
        longitude <= vitMaxLng;
  }

  /// Get all nearby blocks (within 200m)
  static List<String> getNearbyBlocks(double latitude, double longitude) {
    final List<String> nearby = [];

    for (final block in vitBlocks) {
      final double distance = calculateDistance(
        latitude,
        longitude,
        block['lat'],
        block['lng'],
      );

      if (distance <= 200) {
        nearby.add(block['name']);
      }
    }

    return nearby;
  }
}
