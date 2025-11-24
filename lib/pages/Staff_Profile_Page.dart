import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'role_selection_page.dart';
import 'package:garden_app/utils/server_config.dart';
import '../services/notification_service.dart';

class StaffProfilePage extends StatefulWidget {
  final String userName;
  final String staffId;

  const StaffProfilePage({
    super.key,
    required this.userName,
    required this.staffId,
  });

  @override
  State<StaffProfilePage> createState() => _StaffProfilePageState();
}

class _StaffProfilePageState extends State<StaffProfilePage> with WidgetsBindingObserver, RouteAware {
  File? profileImage;
  String deviceId = '';
  String staffId = '';
  Map<String, dynamic> staffStats = {};
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  Timer? _refreshTimer;
  Timer? _fcmRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeProfile();
    _startAutoRefresh();
    _startAutoFCMRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _fcmRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when returning to this page from another page
    _onPageResumed();
  }

  @override
  void didPushNext() {
    // Called when navigating away from this page
    _refreshTimer?.cancel();
  }

  void _startAutoRefresh() {
    // Auto-refresh every 15 seconds for more responsive updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted && !_isLoading) {
        _loadStaffStats();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh stats when app comes back to foreground
      _loadStaffStats();
      // Restart auto-refresh timer
      _refreshTimer?.cancel();
      _startAutoRefresh();
      // Restart FCM refresh timer
      _fcmRefreshTimer?.cancel();
      _startAutoFCMRefresh();
      // Also refresh FCM token when app resumes
      _refreshFCMTokenSilently();
    } else if (state == AppLifecycleState.paused) {
      // Pause auto-refresh when app goes to background
      _refreshTimer?.cancel();
      _fcmRefreshTimer?.cancel();
    }
  }

  Future<void> _initializeProfile() async {
    await _generateDeviceId();
    await _generateStaffId();
    await _loadStaffStats();
    await _checkExistingProfile();
  }

  Future<void> _generateStaffId() async {
    final prefs = await SharedPreferences.getInstance();
    String? existingStaffId = prefs.getString('staff_id');

    setState(() {
      staffId = existingStaffId!;
    });
  }

  Future<void> _loadStaffStats() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      print('🔄 Fetching staff stats for: ${widget.staffId}');
      print('🌐 Server URL: ${ServerConfig.baseUrl}');
      
      // Check server connectivity first
      try {
        final healthCheck = await http.get(
          Uri.parse('${ServerConfig.baseUrl}/health'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 5));
        
        if (healthCheck.statusCode != 200) {
          print('⚠️ Server health check failed: ${healthCheck.statusCode}');
        } else {
          print('✅ Server is accessible');
        }
      } catch (e) {
        print('⚠️ Server connectivity issue: $e');
      }
      
      // Fetch real-time task data from server
      final response = await http.get(
        Uri.parse('${ServerConfig.baseUrl}/staff/tasks/${widget.staffId}'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('📊 Server response: $data');
        
        // Use server-calculated statistics directly
        final totalTasks = data['totalTasks'] ?? 0;
        final completedTasks = data['completedTasks'] ?? 0;
        final inProgressTasks = data['pendingTasks'] ?? 0;

        final prefs = await SharedPreferences.getInstance();
        final currentTime = DateTime.now().toIso8601String();
        
        final newStats = {
          'totalTasks': totalTasks,
          'completedTasks': completedTasks,
          'inProgressTasks': inProgressTasks,
          'joinDate': prefs.getString('join_date') ?? currentTime,
          'lastActive': currentTime,
          'staffName': widget.userName,
          'staffEmail': '${widget.staffId}@garden.com',
          'lastUpdated': currentTime,
        };

        if (mounted) {
          setState(() {
            staffStats = newStats;
          });
        }

        // Cache the stats and update last active time
        await prefs.setString('staff_stats_${widget.staffId}', json.encode(newStats));
        await prefs.setString('last_active', currentTime);
        
        print('✅ Staff stats updated: Total: $totalTasks, Completed: $completedTasks, In Progress: $inProgressTasks');
      } else {
        print('⚠️ Failed to load staff tasks: ${response.statusCode}');
        print('Response body: ${response.body}');
        print('Request URL: ${ServerConfig.baseUrl}/staff/tasks/${widget.staffId}');
        await _loadFallbackStats();
      }
    } catch (e) {
      print('❌ Error fetching staff tasks: $e');
      await _loadFallbackStats();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadFallbackStats() async {
    final prefs = await SharedPreferences.getInstance();
    
    print('📱 Loading fallback stats for ${widget.staffId}');
    
    // Use cached stats if available
    final cachedStats = prefs.getString('staff_stats_${widget.staffId}');
    if (cachedStats != null) {
      try {
        final stats = json.decode(cachedStats) as Map<String, dynamic>;
        print('📊 Using cached stats: $stats');
        if (mounted) {
          setState(() {
            staffStats = stats;
          });
        }
        return;
      } catch (e) {
        print('❌ Error loading cached stats: $e');
      }
    }

    // Fallback to default values with current timestamp
    final currentTime = DateTime.now().toIso8601String();
    final fallbackStats = {
      'totalTasks': 0,
      'completedTasks': 0,
      'inProgressTasks': 0,
      'joinDate': prefs.getString('join_date') ?? currentTime,
      'lastActive': currentTime,
      'staffName': widget.userName,
      'staffEmail': '${widget.staffId}@garden.com',
      'lastUpdated': currentTime,
    };
    
    if (mounted) {
      setState(() {
        staffStats = fallbackStats;
      });
      
      // Cache the fallback stats
      await prefs.setString('staff_stats_${widget.staffId}', json.encode(fallbackStats));
      print('💾 Cached fallback stats for future use');
    }
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
        identifier = _generateFallbackId();
      }

      setState(() {
        deviceId = identifier.substring(0, 12).toUpperCase();
      });

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
      debugPrint('Profile image synced: ${profileImage!.path}');
    }
  }

  Future<void> _refreshProfile() async {
    print('🔄 Manual refresh triggered');
    await _loadStaffStats();
    
    // Show a brief success message with stats
    if (mounted) {
      final total = staffStats['totalTasks'] ?? 0;
      final completed = staffStats['completedTasks'] ?? 0;
      final inProgress = staffStats['inProgressTasks'] ?? 0;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stats updated: $total total ($completed completed, $inProgress in progress)'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.green[600],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Method to be called when returning from other pages
  void _onPageResumed() {
    if (mounted) {
      print('📱 Page resumed - refreshing stats');
      _loadStaffStats();
    }
  }

  // Force refresh method for immediate updates
  Future<void> _forceRefresh() async {
    if (mounted) {
      print('⚡ Force refresh triggered');
      setState(() {
        _isLoading = true;
      });
      await _loadStaffStats();
    }
  }

  void _startAutoFCMRefresh() {
    // Auto-refresh FCM token every 2 minutes to ensure it stays valid
    _fcmRefreshTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (mounted) {
        _refreshFCMTokenSilently();
      }
    });
  }

  Future<void> _refreshFCMTokenSilently() async {
    try {
      print('🔄 Auto-refreshing FCM token for staff...');
      await NotificationService.forceRefreshFCMToken();
      print('✅ Staff FCM token auto-refreshed successfully');
    } catch (e) {
      print('⚠️ Silent FCM token refresh failed: $e');
      // Try force refresh as fallback
      try {
        await NotificationService.refreshFCMToken();
        print('✅ Staff FCM token force refreshed as fallback');
      } catch (e2) {
        print('❌ All FCM token refresh attempts failed: $e2');
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Profile'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: _isLoading 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _forceRefresh,
            tooltip: 'Refresh Stats',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _forceRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildProfileHeader(context),
              _buildProfileDetailsCard(),
              _buildDynamicStatisticsCard(),
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
        color: Theme.of(
          context,
        ).colorScheme.primary.withAlpha((255 * 0.8).round()),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(30.0),
        ),
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
                  : const AssetImage('assets/default_profile.png')
                        as ImageProvider,
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
            staffStats['staffName'] ?? widget.userName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            staffStats['staffEmail'] ?? '${widget.staffId}@example.com',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withAlpha((255 * 0.8).round()),
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
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _buildDetailRow('Staff ID', widget.staffId),
            _buildDetailRow('User ID', staffId),
            _buildDetailRow('Join Date', _formatDate(staffStats['joinDate'])),
            _buildDetailRow(
              'Last Active',
              _formatDate(staffStats['lastActive']),
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
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicStatisticsCard() {
    final totalTasks = staffStats['totalTasks'] ?? 0;
    final completedTasks = staffStats['completedTasks'] ?? 0;
    final inProgressTasks = staffStats['inProgressTasks'] ?? 0;
    final lastUpdated = staffStats['lastUpdated'];

    return Card(
      margin: const EdgeInsets.all(15.0),
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Task Statistics',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isLoading)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Updating...',
                        style: TextStyle(fontSize: 10, color: Colors.blue[600]),
                      ),
                    ],
                  ),
              ],
            ),
            const Divider(),
            
            // Total Tasks
            _buildDynamicStatRow(
              icon: Icons.assignment,
              label: 'Total Tasks',
              value: totalTasks.toString(),
              color: Colors.blue,
            ),
            const SizedBox(height: 12),
            
            // In Progress Tasks
            _buildDynamicStatRow(
              icon: Icons.hourglass_empty,
              label: 'In Progress',
              value: inProgressTasks.toString(),
              color: Colors.orange,
            ),
            const SizedBox(height: 12),
            
            // Completed Tasks
            _buildDynamicStatRow(
              icon: Icons.check_circle,
              label: 'Completed',
              value: completedTasks.toString(),
              color: Colors.green,
            ),
            
            const SizedBox(height: 16),
            
            // Progress Bar
            if (totalTasks > 0) ...[
              const Text(
                'Completion Progress',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: completedTasks / totalTasks,
                backgroundColor: Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
              ),
              const SizedBox(height: 4),
              Text(
                '${((completedTasks / totalTasks) * 100).toStringAsFixed(1)}% Complete',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicStatRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
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
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            const SizedBox(height: 10),
            // Only Refresh button, Dashboard removed
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _forceRefresh,
                icon: _isLoading 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh),
                label: const Text('Refresh'),
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
          ],
        ),
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
        child: const Text('Logout', style: TextStyle(fontSize: 18)),
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

  String _formatTime(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final dateTime = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else {
        return '${dateTime.day}/${dateTime.month} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      debugPrint('Error parsing time: $e');
      return 'N/A';
    }
  }
}
