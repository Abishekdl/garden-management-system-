import 'package:http/http.dart' as http;

class ServerConfig {
  // Primary server URL - Updated to use tunnel URL for remote access
  static String _baseUrl = 'https://zhgkq02n-5000.inc1.devtunnels.ms'; // Tunnel URL for remote access
  
  // Alias for primaryServerUrl to maintain backward compatibility
  static String SERVER_URL = _baseUrl;
  
  // Fallback URLs for different environments
  static const List<String> fallbackUrls = [
    'http://localhost:5000', // Local development
    'http://127.0.0.1:5000', // Alternative localhost
    'http://10.0.2.2:5000', // Android emulator
    'http://192.168.0.105:5000', // Network IP from logs
    'http://10.117.108.82:5000', // Previous server IP
    'http://192.168.1.100:5000', // Common local network IP
  ];
  
  // Enable offline mode for testing
  static const bool enableOfflineMode = false;
  
  static String get baseUrl => _baseUrl;
  
  // New method to set the base URL dynamically
  static void setBaseUrl(String url) {
    _baseUrl = url;
    SERVER_URL = url; // Keep alias updated
    print('✅ Server URL has been set to: $_baseUrl');
  }
  
  static String get uploadEndpoint => '$_baseUrl/upload/image';
  static String get completeTaskEndpoint => '$_baseUrl/complete_task';
  static String get historyEndpoint => '$_baseUrl/history';
  static String get notificationsEndpoint => '$baseUrl/notifications';
  
  static String getUploadEndpoint(String baseUrl) {
    final cleanUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$cleanUrl/upload';
  }
  
  static bool isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }
  
  // Test server connectivity and auto-configure working URL
  static Future<String?> findWorkingServer() async {
    print('🔍 Testing server connectivity...');
    
    // Test primary server first
    print('Testing primary server: $_baseUrl');
    if (await testConnection(_baseUrl)) {
      print('✅ Primary server is accessible: $_baseUrl');
      return _baseUrl;
    }
    
    // Test fallback URLs
    for (String url in fallbackUrls) {
      print('Testing fallback server: $url');
      if (await testConnection(url)) {
        print('✅ Found working server: $url');
        setBaseUrl(url); // Auto-configure the working URL
        return url;
      }
    }
    
    print('❌ No working server found');
    return null;
  }
  
  // Auto-configure server URL on app startup
  static Future<void> autoConfigureServer() async {
    final workingServer = await findWorkingServer();
    if (workingServer != null) {
      print('🚀 Server auto-configured to: $workingServer');
    } else {
      print('⚠️ No server available - app will use offline mode');
    }
  }
  
  static Future<bool> testConnection(String url) async {
    try {
      final uri = Uri.parse('$url/health'); // Health check endpoint
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  
  // Simulate server response for offline mode
  static Map<String, dynamic> getOfflineUploadResponse(String studentName, String registerNumber) {
    final mockTaskId = 'offline_${DateTime.now().millisecondsSinceEpoch}';
    return {
      'aiCaption': 'Garden maintenance required - offline mode simulation',
      'caption': 'Garden maintenance required - offline mode simulation',
      'imageUrl': 'https://via.placeholder.com/400x300?text=Offline+Mode',
      'taskId': mockTaskId,
      'assignedTo': 'staff1',
      'status': 'Task created successfully (offline mode)',
      'location': 'VIT Vellore Campus',
      'timestamp': DateTime.now().toIso8601String(),
      'studentName': studentName,
      'registerNumber': registerNumber,
      'gpsData': null
    };
  }
  
  static List<Map<String, dynamic>> getOfflineHistoryResponse(String registerNumber) {
    return [
      {
        'id': '1',
        'type': 'image',
        'caption': 'AI: Detected healthy plant growth.',
        'user_caption': 'The roses are blooming beautifully!',
        'status': 'Completed',
        'timestamp': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'name': 'DEVIKA',
        'register_number': registerNumber,
        'location': 'Garden Zone A',
        'ai_confidence': 0.92,
        'assignedTo': 'staff1',
        'notification_sent': true,
        'imageUrl': 'https://via.placeholder.com/150',
      },
      {
        'id': '2',
        'type': 'video',
        'caption': 'AI: Watering system appears to be malfunctioning.',
        'user_caption': 'Found a leak in the irrigation pipe.',
        'status': 'Pending',
        'timestamp': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        'name': 'DEVIKA',
        'register_number': registerNumber,
        'location': 'Garden Zone B',
        'ai_confidence': 0.78,
        'assignedTo': 'staff2',
        'notification_sent': false,
        'imageUrl': 'https://via.placeholder.com/150',
      },
    ];
  }
}
