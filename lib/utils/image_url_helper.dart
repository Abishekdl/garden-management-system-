import '../utils/server_config.dart';

class ImageUrlHelper {
  /// Resolves an image URL to ensure it's a complete, accessible URL
  static String resolveImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return '';
    }
    
    // If already a complete URL, return as-is
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return imageUrl;
    }
    
    // If it's a relative path, prepend the server base URL
    final baseUrl = ServerConfig.baseUrl;
    final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final cleanImageUrl = imageUrl.startsWith('/') ? imageUrl.substring(1) : imageUrl;
    
    final resolvedUrl = '$cleanBaseUrl/$cleanImageUrl';
    print('Resolved image URL: $imageUrl -> $resolvedUrl');
    return resolvedUrl;
  }
  
  /// Checks if an image URL is valid and accessible
  static bool isValidImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return false;
    }
    
    try {
      final uri = Uri.parse(imageUrl);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }
}