
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'role_selection_page.dart';
import 'package:garden_app/utils/server_config.dart';
import '../services/notification_service.dart';

class ProfilePage extends StatefulWidget {
  final String userName;
  final String registerNumber;

  const ProfilePage({
    super.key,
    required this.userName,
    required this.registerNumber,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  File? profileImage;
  String deviceId = '';
  String userId = '';
  Map<String, dynamic> userStats = {};
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh profile when app comes back to foreground
      _loadUserStats();
    }
  }

  Future<void> _initializeProfile() async {
    await _generateDeviceId();
    await _generateUserId();
    await _loadUserStats();
    await _checkExistingProfile();
  }

  Future<void> _generateUserId() async {
    final prefs = await SharedPreferences.getInstance();
    String? existingUserId = prefs.getString('user_id');

    setState(() {
      userId = existingUserId!;
    });
  }

  Future<void> _loadUserStats() async {
    // Always load from local data first for immediate display
    await _loadFallbackStats();
    
    // Then try to fetch from server to get latest data
    try {
      final response = await http.get(
        Uri.parse('${ServerConfig.baseUrl}/history?register_number=${widget.registerNumber}'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> serverHistory = json.decode(response.body);
        
        // Calculate statistics from server data
        final totalReports = serverHistory.length;
        final completedReports = serverHistory.where((item) {
          final status = item['status']?.toString().toLowerCase() ?? '';
          return status == 'completed' || status == 'resolved';
        }).length;
        final inProgressReports = serverHistory.where((item) {
          final status = item['status']?.toString().toLowerCase() ?? '';
          return status == 'pending' || status == 'in progress' || status == 'assigned';
        }).length;

        final prefs = await SharedPreferences.getInstance();
        
        setState(() {
          userStats = {
            'totalReports': totalReports,
            'completedReports': completedReports,
            'inProgressReports': inProgressReports,
            'joinDate': prefs.getString('join_date') ?? DateTime.now().toIso8601String(),
            'lastActive': DateTime.now().toIso8601String(),
            'studentName': widget.userName,
            'studentEmail': '${widget.registerNumber}@example.com',
          };
        });
        
        // Update last active time
        await prefs.setString('last_active', DateTime.now().toIso8601String());
      } else {
        debugPrint('Failed to load student details: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching student details: $e');
      // Keep using local data if server fails
    }
  }

  Future<void> _loadFallbackStats() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('upload_history') ?? [];
    final uploadHistory = historyJson
        .map((item) => json.decode(item) as Map<String, dynamic>).toList();

    // Calculate statistics with proper status matching
    final totalReports = uploadHistory.length;
    final completedReports = uploadHistory.where((item) {
      final status = item['status']?.toString().toLowerCase() ?? '';
      return status == 'completed' || status == 'resolved';
    }).length;
    final inProgressReports = uploadHistory.where((item) {
      final status = item['status']?.toString().toLowerCase() ?? '';
      return status == 'pending' || status == 'in progress' || status == 'assigned';
    }).length;

    // Set join date if not already set
    String joinDate = prefs.getString('join_date') ?? '';
    if (joinDate.isEmpty) {
      joinDate = DateTime.now().toIso8601String();
      await prefs.setString('join_date', joinDate);
    }

    setState(() {
      userStats = {
        'totalReports': totalReports,
        'completedReports': completedReports,
        'inProgressReports': inProgressReports,
        'joinDate': joinDate,
        'lastActive': DateTime.now().toIso8601String(),
        'studentName': widget.userName,
        'studentEmail': '${widget.registerNumber}@example.com',
      };
    });
    
    // Update last active time
    await prefs.setString('last_active', DateTime.now().toIso8601String());
  }

  Future<void> _generateDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String identifier = '';

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        identifier = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        identifier = iosInfo.identifierForVendor ?? '';
      }

      if (identifier.isEmpty) {
        // Fallback to random UUID
        identifier = _generateFallbackId();
      }

      setState(() {
        deviceId = identifier.substring(0, 12).toUpperCase();
      });

      // Store device ID
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_id', deviceId);
    } catch (e) {
      setState(() {
        deviceId = _generateFallbackId();
      });
    }
  }

  String _generateFallbackId() {
    final random = Random();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _checkExistingProfile() async {
    // Load existing profile image if available
    final prefs = await SharedPreferences.getInstance();
    final imagePath = prefs.getString('profile_image_path');
    if (imagePath != null && File(imagePath).existsSync()) {
      setState(() {
        profileImage = File(imagePath);
      });
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        profileImage = File(pickedFile.path);
      });
      _syncProfileToServer();
    }
  }

  Future<void> _syncProfileToServer() async {
    final prefs = await SharedPreferences.getInstance();
    if (profileImage != null) {
      await prefs.setString('profile_image_path', profileImage!.path);
      // In a real application, you would upload the image to a server here.
      // For this example, we're just storing the path locally.
      debugPrint('Profile image synced: ${profileImage!.path}');
    }
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

  Future<void> _refreshProfile() async {
    await _loadUserStats();
  }

  Future<void> _refreshFCMToken() async {
    try {
      // Show loading indicator
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

      // Refresh the FCM token
      await NotificationService.refreshFCMToken();

      // Show success message
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
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Failed to refresh token: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _testNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final registerNumber = prefs.getString('register_number');
      
      if (registerNumber == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: No student ID found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Show loading indicator
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

      // Send test notification
      await NotificationService.sendTestNotificationToStudent(registerNumber);

      // Show success message
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
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Test failed: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Profile'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshProfile,
            tooltip: 'Refresh Profile',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshProfile,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildProfileHeader(context),
              _buildProfileDetailsCard(),
              _buildStatisticsCard(),
              _buildQuickActionsCard(),
              _buildLogoutButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30.0)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: CircleAvatar(
              radius: 60,
              backgroundColor: Colors.grey.shade300,
              backgroundImage: profileImage != null
                  ? FileImage(profileImage!)
                  : const AssetImage('assets/default_profile.png') as ImageProvider,
              child: profileImage == null
                  ? Icon(
                      Icons.camera_alt,
                      color: Colors.grey.shade800,
                      size: 40,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            userStats['studentName'] ?? widget.userName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            userStats['studentEmail'] ?? '${widget.registerNumber}@example.com',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileDetailsCard() {
    return Card(
      margin: const EdgeInsets.all(15.0),
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
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
            const Divider(),
            _buildDetailRow('Register Number', widget.registerNumber),
            _buildDetailRow('User ID', userId),
            _buildDetailRow('Join Date', _formatDate(userStats['joinDate'])),
            _buildDetailRow('Last Active', _formatDate(userStats['lastActive'])),
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
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
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

  Widget _buildStatisticsCard() {
    return Card(
      margin: const EdgeInsets.all(15.0),
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
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
            const Divider(),
            _buildStatRow('Total Reports', userStats['totalReports']?.toString() ?? '0'),
            _buildStatRow('Completed Reports', userStats['completedReports']?.toString() ?? '0'),
            _buildStatRow('In Progress Reports', userStats['inProgressReports']?.toString() ?? '0'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
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

  Widget _buildLogoutButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(15.0),
      child: ElevatedButton(
        onPressed: _logout,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.redAccent,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.0),
          ),
        ),
        child: const Text(
          'Logout',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard() {
    return Card(
      margin: const EdgeInsets.all(15.0),
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
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
            const Divider(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      // Navigate to camera and refresh when returning
                      Navigator.pushNamed(context, '/camera').then((_) {
                        _refreshProfile();
                      });
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Take Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      // Navigate to history and refresh when returning
                      Navigator.pushNamed(context, '/history').then((_) {
                        _refreshProfile();
                      });
                    },
                    icon: const Icon(Icons.history),
                    label: const Text('View History'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Notification buttons row
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _refreshFCMToken,
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Refresh', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _testNotifications,
                    icon: const Icon(Icons.notifications_active, size: 14),
                    label: const Text('Test', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final dateTime = DateTime.parse(dateString);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (e) {
      debugPrint('Error parsing date: $e');
      return 'N/A';
    }
  }
}