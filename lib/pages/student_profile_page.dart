import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../utils/server_config.dart';
import 'role_selection_page.dart';
import '../services/notification_service.dart';

class StudentProfilePage extends StatefulWidget {
  const StudentProfilePage({super.key});

  @override
  State<StudentProfilePage> createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage> with WidgetsBindingObserver {
  String _userName = 'Unknown';
  String _registerNumber = 'Unknown';
  String _userEmail = '';
  String _joinDate = 'N/A';
  String _lastActive = 'N/A';
  
  // Statistics
  int _totalReports = 0;
  int _completedReports = 0;
  int _inProgressReports = 0;
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _uploadHistory = [];
  Timer? _fcmRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfileData();
    _startAutoFCMRefresh();
  }

  @override
  void dispose() {
    _fcmRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh profile when app comes back to foreground
      _loadProfileData();
      // Restart FCM refresh timer
      _fcmRefreshTimer?.cancel();
      _startAutoFCMRefresh();
      // Also refresh FCM token when app resumes
      _refreshFCMTokenSilently();
      // Force immediate refresh on resume
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          NotificationService.forceRefreshStudentToken();
        }
      });
    } else if (state == AppLifecycleState.paused) {
      // Pause auto-refresh when app goes to background
      _fcmRefreshTimer?.cancel();
    }
  }

  Future<void> _loadProfileData() async {
    setState(() {
      _isLoading = true;
    });

    await _loadUserData();
    await _loadUploadHistory();
    await _fetchHistoryFromServer();
    await _calculateStatistics();
    await _updateLastActive();

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? 'Unknown';
      _registerNumber = prefs.getString('register_number') ?? 'Unknown';
      _userEmail = prefs.getString('user_email') ?? '${_registerNumber}@example.com';
      
      // Get join date (first time app was opened)
      final joinDateStr = prefs.getString('join_date');
      if (joinDateStr != null) {
        _joinDate = _formatDate(DateTime.parse(joinDateStr));
      } else {
        // Set join date to now if not set
        final now = DateTime.now();
        _joinDate = _formatDate(now);
        prefs.setString('join_date', now.toIso8601String());
      }
    });
  }

  Future<void> _updateLastActive() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString('last_active', now.toIso8601String());
    setState(() {
      _lastActive = _formatDateTime(now);
    });
  }

  Future<void> _loadUploadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('upload_history') ?? [];
    setState(() {
      _uploadHistory = historyJson.map((item) {
        final decodedItem = json.decode(item) as Map<String, dynamic>;
        return {
          'id': decodedItem['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'type': decodedItem['type'] ?? 'image',
          'caption': decodedItem['caption'] ?? '',
          'user_caption': decodedItem['user_caption'] ?? '',
          'status': decodedItem['status'] ?? 'Pending',
          'timestamp': decodedItem['timestamp'] ?? DateTime.now().toIso8601String(),
          'name': decodedItem['name'] ?? _userName,
          'register_number': decodedItem['register_number'] ?? _registerNumber,
          'location': decodedItem['location'] ?? 'Unknown Location',
          'ai_confidence': decodedItem['ai_confidence'] ?? 0.0,
          'assignedTo': decodedItem['assignedTo'] ?? '',
          'notification_sent': decodedItem['notification_sent'] ?? false,
          'imageUrl': decodedItem['imageUrl'] ?? '',
        };
      }).toList();
    });
  }

  Future<void> _fetchHistoryFromServer() async {
    try {
      // Check server availability first
      bool serverAvailable = true;
      try {
        final testUri = Uri.parse('${ServerConfig.baseUrl}/health');
        final testResponse = await http.get(testUri).timeout(const Duration(seconds: 3));
        serverAvailable = testResponse.statusCode == 200;
      } catch (e) {
        serverAvailable = false;
        print('Server not available for profile, using offline data: $e');
      }
      
      if (!serverAvailable) {
        return; // Use local data only
      }
      
      final uri = Uri.parse('${ServerConfig.baseUrl}/history?register_number=$_registerNumber');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> historyData = json.decode(response.body);
        
        // Convert server data to match local format
        final serverHistory = historyData.map((item) {
          final serverItem = item as Map<String, dynamic>;
          return {
            'id': serverItem['id'] ?? '',
            'type': serverItem['type'] ?? 'image',
            'caption': serverItem['caption'] ?? '',
            'user_caption': serverItem['user_caption'] ?? '',
            'status': serverItem['status'] ?? 'Pending',
            'timestamp': serverItem['timestamp'] ?? DateTime.now().toIso8601String(),
            'name': serverItem['name'] ?? _userName,
            'register_number': serverItem['register_number'] ?? _registerNumber,
            'location': serverItem['location'] ?? 'Unknown Location',
            'ai_confidence': serverItem['ai_confidence'] ?? 0.85,
            'assignedTo': serverItem['assignedTo'] ?? '',
            'notification_sent': true,
            'imageUrl': serverItem['imageUrl'] ?? '',
          };
        }).toList();
        
        setState(() {
          _uploadHistory = serverHistory;
        });
        await _saveUploadHistory();
      }
    } catch (e) {
      print('Failed to fetch history from server: $e');
      // Keep using local data if server fails
    }
  }

  Future<void> _saveUploadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = _uploadHistory.map((item) => json.encode(item)).toList();
    await prefs.setStringList('upload_history', historyJson);
  }

  Future<void> _calculateStatistics() async {
    setState(() {
      _totalReports = _uploadHistory.length;
      
      _completedReports = _uploadHistory.where((item) {
        final status = item['status']?.toString().toLowerCase() ?? '';
        return status == 'completed' || status == 'resolved';
      }).length;
      
      _inProgressReports = _uploadHistory.where((item) {
        final status = item['status']?.toString().toLowerCase() ?? '';
        return status == 'pending' || status == 'in progress' || status == 'assigned';
      }).length;
    });
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const RoleSelectionPage()),
        (Route<dynamic> route) => false,
      );
    }
  }

  Future<void> _refreshFCMToken() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Refreshing notification token...'),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 3),
        ),
      );

      await NotificationService.refreshFCMToken();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Notification token refreshed successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh token: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testNotifications() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Sending test notification...'),
            ],
          ),
          backgroundColor: Colors.teal,
          duration: Duration(seconds: 2),
        ),
      );

      await NotificationService.sendTestNotificationToStudent(_registerNumber);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Test notification sent! Check your notification tray.'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testTaskCompletion() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Sending task completion notification...'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      // Call the test task completion endpoint
      final response = await http.post(
        Uri.parse('${ServerConfig.baseUrl}/test_task_completion'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'studentId': _registerNumber,
          'staffId': 'Test Staff'
        }),
      );

      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Task completion notification sent! Check History → Notifications.'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to send completion notification: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startAutoFCMRefresh() {
    // Auto-refresh FCM token every 30 seconds to ensure it stays valid (very aggressive)
    _fcmRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _refreshFCMTokenSilently();
      }
    });
  }

  Future<void> _refreshFCMTokenSilently() async {
    try {
      print('🔄 Auto-refreshing FCM token for student...');
      // Use dedicated student token refresh method
      await NotificationService.forceRefreshStudentToken();
      print('✅ Student FCM token auto-refreshed successfully');
      
      // Also check for any pending refresh requests from server
      await _checkForRefreshRequests();
    } catch (e) {
      print('⚠️ Silent FCM token refresh failed: $e');
      // Try multiple fallback attempts
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          print('🔄 Fallback attempt $attempt...');
          await Future.delayed(Duration(seconds: attempt * 2)); // Progressive delay
          await NotificationService.forceRefreshStudentToken();
          print('✅ Student FCM token refreshed on attempt $attempt');
          break;
        } catch (e2) {
          print('❌ Fallback attempt $attempt failed: $e2');
          if (attempt == 3) {
            print('❌ All FCM token refresh attempts failed');
            // Last resort - try the general refresh method
            try {
              await NotificationService.refreshFCMToken();
              print('✅ Student FCM token refreshed with general method');
            } catch (e3) {
              print('❌ All refresh methods failed: $e3');
            }
          }
        }
      }
    }
  }

  Future<void> _checkForRefreshRequests() async {
    try {
      // Check if server has requested a token refresh
      final response = await http.get(
        Uri.parse('${ServerConfig.baseUrl}/check_refresh_requests?studentId=$_registerNumber'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['hasRefreshRequest'] == true) {
          print('🔄 Server requested token refresh, forcing immediate refresh...');
          await NotificationService.forceRefreshStudentToken();
          
          // Mark refresh request as completed
          await http.post(
            Uri.parse('${ServerConfig.baseUrl}/complete_refresh_request'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'studentId': _registerNumber}),
          ).timeout(const Duration(seconds: 5));
        }
      }
    } catch (e) {
      print('⚠️ Error checking refresh requests: $e');
    }
  }

  Future<void> _forceRefreshToken() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Force refreshing FCM token...'),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );

      // Force refresh the FCM token
      await NotificationService.forceRefreshStudentToken();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('FCM token force refreshed! Try sending a test notification now.'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Force refresh failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadProfileData,
              child: CustomScrollView(
                slivers: [
                  // Custom App Bar with Profile Header
                  SliverAppBar(
                    expandedHeight: 280,
                    floating: false,
                    pinned: true,
                    backgroundColor: Colors.green[600],
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.green[600]!,
                              Colors.green[700]!,
                            ],
                          ),
                        ),
                        child: SafeArea(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 60),
                              // Profile Avatar
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                ),
                                child: Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // User Name
                              Text(
                                _userName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              // User Email
                              Text(
                                _userEmail,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  // Profile Content
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // Personal Details Card
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Personal Details',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _buildDetailRow('Register Number', _registerNumber),
                                  _buildDetailRow('User ID', _registerNumber),
                                  _buildDetailRow('Join Date', _joinDate),
                                  _buildDetailRow('Last Active', _lastActive),
                                ],
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Statistics Card
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Statistics',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _buildStatRow('Total Reports', _totalReports, Colors.blue),
                                  _buildStatRow('Completed Reports', _completedReports, Colors.green),
                                  _buildStatRow('In Progress Reports', _inProgressReports, Colors.orange),
                                ],
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Quick Actions Card
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Quick Actions',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () async {
                                            // Navigate to camera and refresh when returning
                                            await Navigator.pushNamed(context, '/camera');
                                            _loadProfileData(); // Refresh profile after returning
                                          },
                                          icon: const Icon(Icons.camera_alt),
                                          label: const Text('Take Photo'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green[600],
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () async {
                                            // Navigate to history and refresh when returning
                                            await Navigator.pushNamed(context, '/history');
                                            _loadProfileData(); // Refresh profile after returning
                                          },
                                          icon: const Icon(Icons.history),
                                          label: const Text('View History'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue[600],
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 12),
                                  
                                  // Notification test buttons
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _refreshFCMToken,
                                          icon: const Icon(Icons.refresh, size: 14),
                                          label: const Text('Refresh Notifications', style: TextStyle(fontSize: 11)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.purple[600],
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _testNotifications,
                                          icon: const Icon(Icons.notifications_active, size: 14),
                                          label: const Text('Test Notifications', style: TextStyle(fontSize: 11)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.teal[600],
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 8),
                                  
                                  // Test completion notification button
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: _testTaskCompletion,
                                      icon: const Icon(Icons.check_circle, size: 16),
                                      label: const Text('Test Task Completion (with Image)', style: TextStyle(fontSize: 12)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green[600],
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                      ),
                                    ),
                                  ),
                                  
                                  const SizedBox(height: 8),
                                  
                                  // Force token refresh button
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: _forceRefreshToken,
                                      icon: const Icon(Icons.security, size: 16),
                                      label: const Text('Force Refresh FCM Token', style: TextStyle(fontSize: 12)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red[600],
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                      ),
                                    ),
                                  ),
                                  
                                  const SizedBox(height: 8),
                                  
                                  // Update Profile buttons
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _updateRegisterNumber,
                                          icon: const Icon(Icons.badge, size: 14),
                                          label: const Text('Update Register', style: TextStyle(fontSize: 11)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.indigo[600],
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _updateName,
                                          icon: const Icon(Icons.person_outline, size: 14),
                                          label: const Text('Update Name', style: TextStyle(fontSize: 11)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.deepPurple[600],
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Logout Button
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: ElevatedButton(
                              onPressed: _logout,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Logout',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              value.toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateRegisterNumber() async {
    final TextEditingController controller = TextEditingController();
    
    // Show dialog to enter new register number
    final newRegisterNumber = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Update Register Number'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current: $_registerNumber'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'New Register Number',
                  hintText: 'e.g., 24MCA0018',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newNumber = controller.text.trim().toUpperCase();
                if (newNumber.isNotEmpty && newNumber != _registerNumber) {
                  Navigator.of(context).pop(newNumber);
                } else {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );

    if (newRegisterNumber != null && newRegisterNumber.isNotEmpty) {
      await _performRegisterNumberUpdate(newRegisterNumber);
    }
  }

  Future<void> _performRegisterNumberUpdate(String newRegisterNumber) async {
    try {
      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Updating register number...'),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 3),
        ),
      );

      // Update SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('register_number', newRegisterNumber);
      await prefs.setString('user_name', _userName); // Keep the same name
      
      // Update local state
      setState(() {
        _registerNumber = newRegisterNumber;
      });

      // Refresh FCM token with new register number
      await NotificationService.refreshFCMToken();

      // Reload profile data
      await _loadProfileData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text('Register number updated to $newRegisterNumber successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Failed to update: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _updateName() async {
    final TextEditingController controller = TextEditingController();
    controller.text = _userName; // Pre-fill with current name
    
    // Show dialog to enter new name
    final newName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Update Name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current: $_userName'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'New Name',
                  hintText: 'e.g., John Doe',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newNameValue = controller.text.trim();
                if (newNameValue.isNotEmpty && newNameValue != _userName) {
                  Navigator.of(context).pop(newNameValue);
                } else {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );

    if (newName != null && newName.isNotEmpty) {
      await _performNameUpdate(newName);
    }
  }

  Future<void> _performNameUpdate(String newName) async {
    try {
      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Updating name...'),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );

      // Update SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', newName);
      await prefs.setString('register_number', _registerNumber); // Keep the same register number
      
      // Update local state
      setState(() {
        _userName = newName;
      });

      // Reload profile data
      await _loadProfileData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text('Name updated to $newName successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Failed to update name: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
