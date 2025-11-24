import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'report_detail_page.dart';
import 'notification_detail_page.dart';
import '../utils/server_config.dart';
import '../utils/image_url_helper.dart';
import 'image_viewer_page.dart';

class HistoryPage extends StatefulWidget {
  final String name;
  final String registerNumber;

  const HistoryPage({
    super.key,
    required this.name,
    required this.registerNumber,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  List<Map<String, dynamic>> _uploadHistory = [];
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = false;
  bool _isLoadingNotifications = false;

  final ImagePicker _picker = ImagePicker();
  late TabController _tabController;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh data when app comes back to foreground
      _loadData();
      // Restart auto-refresh timer
      _autoRefreshTimer?.cancel();
      _startAutoRefresh();
    } else if (state == AppLifecycleState.paused) {
      // Pause auto-refresh when app goes to background
      _autoRefreshTimer?.cancel();
    }
  }

  void _startAutoRefresh() {
    // Auto-refresh every 15 seconds like the staff in-progress page
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted && !_isLoading && !_isLoadingNotifications) {
        _loadData();
      }
    });
  }

  Future<void> _loadData() async {
    await _loadUploadHistory();
    await _fetchHistoryFromServer(); // Always try to fetch from server first
    await _loadNotifications();
  }

  Future<void> _refreshData() async {
    // Manual refresh with loading indicator
    setState(() {
      _isLoading = true;
      _isLoadingNotifications = true;
    });
    
    await _loadData();
    
    setState(() {
      _isLoading = false;
      _isLoadingNotifications = false;
    });
  }

  Future<void> _refreshTaskData() async {
    print('Refreshing task data after upload...');
    await _fetchHistoryFromServer();
    await _loadUploadHistory();
  }



  Future<void> _loadNotifications() async {
    setState(() {
      _isLoadingNotifications = true;
    });

    try {
      // Try to fetch from server first
      await _fetchNotificationsFromServer();
    } catch (e) {
      // Fallback to local storage if server is not reachable
      await _loadNotificationsFromLocal();
    } finally {
      setState(() {
        _isLoadingNotifications = false;
      });
    }
  }

  Future<void> _fetchNotificationsFromServer() async {
    try {
      final uri = Uri.parse('${ServerConfig.baseUrl}/notifications?register_number=${widget.registerNumber}');
      print('🔍 NOTIFICATION DEBUG: Fetching from: $uri');
      
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      print('📡 NOTIFICATION DEBUG: Response status: ${response.statusCode}');
      print('📡 NOTIFICATION DEBUG: Response body length: ${response.body.length}');

      if (response.statusCode == 200) {
        final List<dynamic> notificationsData = json.decode(response.body);
        print('📊 NOTIFICATION DEBUG: Received ${notificationsData.length} notifications from server');
        
        // Log first few notifications for debugging
        if (notificationsData.isNotEmpty) {
          print('📋 NOTIFICATION DEBUG: First notification: ${notificationsData[0]}');
          if (notificationsData.length > 1) {
            print('📋 NOTIFICATION DEBUG: Second notification: ${notificationsData[1]}');
          }
        }
        
        setState(() {
          // Keep all relevant notifications, just filter out old "Thank You" messages
          _notifications = notificationsData
              .map((item) => item as Map<String, dynamic>)
              .where((notification) {
                final title = notification['title']?.toString() ?? '';
                final message = notification['message']?.toString() ?? '';
                final type = notification['type']?.toString() ?? '';
                
                // Filter out only old "Thank You" notifications, keep everything else
                final shouldFilter = (title.contains('Thank You') && 
                        message.contains('Thank you for helping us maintain'));
                
                if (shouldFilter) {
                  print('🚫 NOTIFICATION DEBUG: Filtering out: $title');
                } else {
                  print('✅ NOTIFICATION DEBUG: Keeping notification: $title (type: $type)');
                }
                
                return !shouldFilter;
              })
              .toList();
        });
        
        print('✅ NOTIFICATION DEBUG: After filtering: ${_notifications.length} notifications');
        print('📝 NOTIFICATION DEBUG: Notification titles: ${_notifications.map((n) => n['title']).toList()}');
        
        await _saveNotificationsToLocal();
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      print('❌ NOTIFICATION DEBUG: Failed to fetch notifications from server: $e');
      throw e;
    }
  }

  Future<void> _loadNotificationsFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final notificationsJson = prefs.getStringList('notifications') ?? [];
    setState(() {
      // Filter out only old "Thank You" notifications from local storage
      _notifications = notificationsJson
          .map((item) => json.decode(item) as Map<String, dynamic>)
          .where((notification) {
            final title = notification['title']?.toString() ?? '';
            final message = notification['message']?.toString() ?? '';
            final type = notification['type']?.toString() ?? '';
            
            // Filter out only old "Thank You" notifications, keep everything else
            return !(title.contains('Thank You') && 
                    message.contains('Thank you for helping us maintain'));
          })
          .toList();
    });
  }

  Future<void> _saveNotificationsToLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final notificationsJson = _notifications.map((item) => json.encode(item)).toList();
    await prefs.setStringList('notifications', notificationsJson);
  }

  Future<void> _fetchHistoryFromServer() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Check server availability first if offline mode is enabled
      bool serverAvailable = true;
      if (true) { // Always check server availability
        try {
          final testUri = Uri.parse('${ServerConfig.baseUrl}/health');
          final testResponse = await http.get(testUri).timeout(const Duration(seconds: 3));
          serverAvailable = testResponse.statusCode == 200;
        } catch (e) {
          serverAvailable = false;
          print('Server not available for history, using offline data: $e');
        }
      }
      
      if (!serverAvailable) {
        await _handleOfflineHistory();
        return;
      }
      
      final uri = Uri.parse('${ServerConfig.baseUrl}/history?register_number=${widget.registerNumber}');
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
            'name': serverItem['name'] ?? widget.name,
            'register_number': serverItem['register_number'] ?? widget.registerNumber,
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
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      print('Failed to fetch history from server: $e');
      // Keep using local data if server fails
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _handleOfflineHistory() async {
    try {
      print('📴 Loading history in offline mode');
      
      // Simulate network delay
      await Future.delayed(const Duration(seconds: 1));
      
      // Get offline history data
      final offlineData = ServerConfig.getOfflineHistoryResponse(widget.registerNumber);
      
      // Merge with existing local data
      final existingHistory = _uploadHistory.where((item) => item['offline_mode'] == true).toList();
      final allHistory = [...existingHistory, ...offlineData];
      
      // Remove duplicates based on ID
      final Map<String, Map<String, dynamic>> uniqueHistory = {};
      for (final item in allHistory) {
        uniqueHistory[item['id']] = item;
      }
      
      setState(() {
        _uploadHistory = uniqueHistory.values.toList()
          ..sort((a, b) => DateTime.parse(b['timestamp']).compareTo(DateTime.parse(a['timestamp'])));
      });
      
      await _saveUploadHistory();
      print('✅ Offline history loaded successfully');
      
    } catch (e) {
      print('❌ Error loading offline history: $e');
      // Don't show error to user, just keep existing local data
    }
  }

  Future<void> _loadUploadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('upload_history') ?? [];
    setState(() {
      _uploadHistory = historyJson.map((item) {
        final decodedItem = json.decode(item) as Map<String, dynamic>;
        return {
          'id': decodedItem['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(), // Provide a default ID if missing
          'type': decodedItem['type'] ?? 'image',
          'caption': decodedItem['caption'] ?? '',
          'user_caption': decodedItem['user_caption'] ?? '',
          'status': decodedItem['status'] ?? 'Pending',
          'timestamp': decodedItem['timestamp'] ?? DateTime.now().toIso8601String(),
          'name': decodedItem['name'] ?? widget.name, // Provide default name
          'register_number': decodedItem['register_number'] ?? widget.registerNumber, // Provide default register number
          'location': decodedItem['location'] ?? 'Unknown Location', // Provide default location
          'ai_confidence': decodedItem['ai_confidence'] ?? 0.0,
          'assignedTo': decodedItem['assignedTo'] ?? '',
          'notification_sent': decodedItem['notification_sent'] ?? false,
          'imageUrl': decodedItem['imageUrl'] ?? '',
        };
      }).toList();
    });
  }

  Future<void> _saveUploadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = _uploadHistory.map((item) => json.encode(item)).toList();
    await prefs.setStringList('upload_history', historyJson);
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        await _showCaptionDialog(image);
      }
    } catch (e) {
      _showErrorDialog('Failed to pick image: $e');
    }
  }

  Future<void> _showCaptionDialog(XFile imageFile) async {
    final TextEditingController captionController = TextEditingController();
    
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Caption'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(imageFile.path),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: captionController,
                decoration: const InputDecoration(
                  labelText: 'Caption',
                  hintText: 'Describe what you see in the image...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                captionController.dispose();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final caption = captionController.text.trim();
                captionController.dispose();
                Navigator.of(context).pop();
                if (caption.isNotEmpty) {
                  _compressAndUploadImage(imageFile, caption);
                } else {
                  _showErrorDialog('Please add a caption for the image');
                }
              },
              child: const Text('Upload'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _compressAndUploadImage(XFile imageFile, String userCaption) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final directory = await getTemporaryDirectory();
      final targetPath = path.join(
        directory.path,
        'compressed_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        imageFile.path,
        targetPath,
        quality: 70,
        minWidth: 800,
        minHeight: 600,
      );

      if (compressedFile != null) {
        final fileSize = await compressedFile.length();
        if (fileSize <= 500 * 1024) { // 500KB limit
          await _uploadFile(compressedFile, 'image', userCaption);
        } else {
          // Further compress if still too large
          final furtherCompressed = await FlutterImageCompress.compressAndGetFile(
            compressedFile.path,
            targetPath.replaceAll('.jpg', '_small.jpg'),
            quality: 50,
            minWidth: 600,
            minHeight: 400,
          );
          if (furtherCompressed != null) {
            await _uploadFile(furtherCompressed, 'image', userCaption);
          }
        }
      }
    } catch (e) {
      _showErrorDialog('Failed to compress image: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _uploadFile(dynamic file, String type, String userCaption) async {
    try {
      final uri = Uri.parse('${ServerConfig.baseUrl}/upload/image');
      final request = http.MultipartRequest('POST', uri);

      request.fields['name'] = widget.name;
      request.fields['register_number'] = widget.registerNumber;
      request.fields['user_caption'] = userCaption;

      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        file is File ? file.path : file.path,
        filename: file is File ? path.basename(file.path) : path.basename(file.path),
      );
      request.files.add(multipartFile);

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 15),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final responseData = json.decode(response.body);
        print('Upload response: $responseData');
        
        // Refresh task data from server to get updated imageUrl
        await _refreshTaskData();

        // The notification to staff is already sent by the server upon task creation.
        _showSuccessDialog('Upload successful! Staff has been notified.');
      } else {
        _showErrorDialog('Upload failed: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorDialog('Upload failed: $e');
    }
  }

  Future<void> _updateItemStatus(String itemId, String newStatus) async {
    setState(() {
      final index = _uploadHistory.indexWhere((item) => item['id'] == itemId);
      if (index != -1) {
        _uploadHistory[index]['status'] = newStatus;
        _uploadHistory[index]['updated_at'] = DateTime.now().toIso8601String();
      }
    });
    await _saveUploadHistory();
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Success'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'in progress':
        return Colors.orange;
      case 'resolved':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Icons.check_circle;
      case 'in progress':
        return Icons.hourglass_empty;
      case 'resolved':
        return Icons.verified;
      default:
        return Icons.help_outline;
    }
  }

  bool _isVideoUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv'];
    final lowerUrl = url.toLowerCase();
    return videoExtensions.any((ext) => lowerUrl.endsWith(ext));
  }

  Widget _buildThumbnail(Map<String, dynamic> item) {
    final imageUrl = item['imageUrl'] as String?;
    final imagePath = item['image_path'] as String?;
    final itemType = item['type'] ?? 'image';
    
    // Check if it's a video based on URL
    final isVideo = _isVideoUrl(imageUrl) || _isVideoUrl(imagePath) || itemType == 'video';

    Widget placeholder = Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        isVideo ? Icons.play_circle_filled : Icons.photo,
        color: isVideo ? Colors.red[700] : Colors.grey[600],
        size: 32,
      ),
    );

    // For videos, just show the video icon placeholder
    if (isVideo) {
      return placeholder;
    }

    // For images, try to load thumbnail
    final resolvedImageUrl = ImageUrlHelper.resolveImageUrl(imageUrl);
    print('Loading thumbnail for image URL: $resolvedImageUrl');

    ImageProvider? imageProvider;

    if (resolvedImageUrl.isNotEmpty && ImageUrlHelper.isValidImageUrl(resolvedImageUrl)) {
      imageProvider = NetworkImage(resolvedImageUrl);
    } else if (imagePath != null && imagePath.isNotEmpty) {
      final imageFile = File(imagePath);
      if (imageFile.existsSync()) {
        imageProvider = FileImage(imageFile);
      }
    }

    if (imageProvider != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image(
          image: imageProvider,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            print('Error loading thumbnail: $error');
            return placeholder;
          },
        ),
      );
    }

    return placeholder;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('History'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 0,
        actions: [
          // Auto-refresh indicator
          if (_autoRefreshTimer?.isActive == true)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.assignment),
              text: 'My Reports',
            ),
            Tab(
              icon: Icon(Icons.check_circle),
              text: 'Completed',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Header with upload button only
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.inversePrimary.withAlpha((0.1 * 255).toInt()),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _pickAndUploadImage,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_photo_alternate),
                label: Text(_isLoading ? 'Uploading...' : 'Upload New Photo'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // My Reports Tab
                _buildReportsTab(),
                // Notifications Tab
                _buildNotificationsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsTab() {
    if (_uploadHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No reports yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload your first photo to get started',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _uploadHistory.length,
        itemBuilder: (context, index) {
          final item = _uploadHistory[index];
          return _buildReportCard(item);
        },
      ),
    );
  }

  Widget _buildNotificationsTab() {
    print('🎨 NOTIFICATION DEBUG: Building notifications tab');
    print('🎨 NOTIFICATION DEBUG: _isLoadingNotifications = $_isLoadingNotifications');
    print('🎨 NOTIFICATION DEBUG: _notifications.length = ${_notifications.length}');
    
    // Only show loading indicator if we're loading AND have no data yet
    if (_isLoadingNotifications && _notifications.isEmpty) {
      print('🎨 NOTIFICATION DEBUG: Showing loading indicator');
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_notifications.isEmpty) {
      print('🎨 NOTIFICATION DEBUG: Showing empty state (no notifications)');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No completed tasks',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Completed reports will appear here',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    print('🎨 NOTIFICATION DEBUG: Building ListView with ${_notifications.length} items');
    return RefreshIndicator(
      onRefresh: () async {
        print('🔄 NOTIFICATION DEBUG: Pull-to-refresh triggered');
        await _loadNotifications();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          print('🎨 NOTIFICATION DEBUG: Building card $index');
          final notification = _notifications[index];
          return _buildNotificationCard(notification);
        },
      ),
    );
  }

  DateTime _safeParse(dynamic raw) {
    if (raw is DateTime) return raw.toLocal();
    if (raw == null) return DateTime.now();
    String s = raw.toString();
    if (s.contains(' ') && !s.contains('T')) s = s.replaceFirst(' ', 'T');
    if (s.endsWith('Z') && s.contains('+')) s = s.substring(0, s.length - 1);
    return DateTime.tryParse(s)?.toLocal() ?? DateTime.now();
  }

  String _asString(dynamic v, [String fallback = '']) => v?.toString() ?? fallback;

  Widget _buildReportCard(Map<String, dynamic> item) {
    final timestamp = _safeParse(item['timestamp']);
    final confidence = (((item['ai_confidence'] ?? 0.0) as num).toDouble() * 100).toStringAsFixed(1);
    final status = _asString(item['status'], 'In Progress');
    final location = _asString(item['location'], 'Unknown Location');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReportDetailPage(report: item),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with thumbnail, status and timestamp
              Row(
                children: [
                  // Photo/Video thumbnail
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _buildThumbnail(item),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getStatusColor(status).withAlpha((0.1 * 255).toInt()),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _getStatusColor(status).withAlpha((0.1 * 255).toInt())),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _getStatusIcon(status),
                                    size: 16,
                                    color: _getStatusColor(status),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      color: _getStatusColor(status),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          location,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Caption from server response
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha((0.05 * 255).toInt()),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withAlpha((0.2 * 255).toInt())),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.psychology, size: 16, color: Colors.blue),
                        const SizedBox(width: 4),
                        const Text(
                          'AI Analysis',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withAlpha((0.1 * 255).toInt()),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$confidence% confidence',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _asString(item['caption'], 'No AI analysis available'),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),

              // User caption if available
              if ((item['user_caption']?.toString().isNotEmpty ?? false)) ...[
                const SizedBox(height: 12),
                const Text(
                  'Your Caption:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _asString(item['user_caption']),
                  style: const TextStyle(fontSize: 14),
                ),
              ],

              // Action buttons
              const SizedBox(height: 12),
              Row(
                children: [
                  if (item['notification_sent'] == true)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withAlpha((0.1 * 255).toInt()),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_active, size: 12, color: Colors.green),
                          SizedBox(width: 4),
                          Text(
                            'Staff Notified',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  if (status != 'Completed')
                    PopupMenuButton<String>(
                      onSelected: (value) => _updateItemStatus(item['id'], value),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'In Progress',
                          child: Text('Mark as In Progress'),
                        ),
                        const PopupMenuItem(
                          value: 'Resolved',
                          child: Text('Mark as Resolved'),
                        ),
                        const PopupMenuItem(
                          value: 'Completed',
                          child: Text('Mark as Completed'),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.withAlpha((0.1 * 255).toInt()),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Update Status',
                              style: TextStyle(fontSize: 12),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_drop_down, size: 16),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    // Debug: Print notification data
    print('=== NOTIFICATION CARD DEBUG ===');
    print('Notification data: $notification');
    print('imageUrl: ${notification['imageUrl']}');
    print('type: ${notification['type']}');
    print('hasImage check: ${notification['imageUrl'] != null && notification['imageUrl'].toString().isNotEmpty}');
    print('==============================');
    
    final timestamp = _safeParse(notification['timestamp']);
    final isRead = notification['read'] ?? false;
    final hasImage = notification['imageUrl'] != null && notification['imageUrl'].toString().isNotEmpty;
    final isTaskCompleted = notification['type'] == 'task_completed';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isRead ? 1 : 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: isRead ? null : Border.all(
            color: isTaskCompleted ? Colors.green.withAlpha((0.3 * 255).toInt()) : Colors.blue.withAlpha((0.3 * 255).toInt()), 
            width: 2
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NotificationDetailPage(notification: notification),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isTaskCompleted ? Icons.check_circle : Icons.message,
                    color: isTaskCompleted 
                      ? (isRead ? Colors.green[400] : Colors.green) 
                      : (isRead ? Colors.grey[600] : Colors.blue),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notification['title'] ?? 'Staff Message',
                      style: TextStyle(
                        fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                        fontSize: 16,
                        color: isTaskCompleted ? Colors.green[700] : null,
                      ),
                    ),
                  ),
                  if (!isRead)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isTaskCompleted ? Colors.green : Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                notification['message'] ?? 'No message content',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              
              // Show staff info for completed tasks
              if (isTaskCompleted && notification['staffInfo'] != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withAlpha((0.1 * 255).toInt()),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.withAlpha((0.3 * 255).toInt())),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person, size: 16, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(
                        'Completed by: ${notification['staffInfo']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'From: ${notification['sender'] ?? (isTaskCompleted ? notification['staffInfo'] ?? 'Garden Staff' : 'Staff')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  Text(
                    '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              
              // Show "See Image" button for task completion notifications
              if (hasImage) ...[
                const SizedBox(height: 12),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      print('Navigating to ImageViewerPage with imageUrl: ${notification['imageUrl']}'); // Debug print
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ImageViewerPage(
                            imageUrl: notification['imageUrl'],
                            title: 'Task Completed',
                            subtitle: '', // Added missing subtitle parameter
                            showThankYouMessage: true,
                            staffInfo: notification['staffInfo'] ?? 'Garden Staff',
                            isLocalFile: false,
                            taskDetails: {
                              'taskId': notification['taskId'],
                              'completedAt': notification['timestamp'],
                              'staffInfo': notification['staffInfo'],
                            },
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.image, size: 18),
                    label: const Text('See Completion Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        ),
      ),
    );
  }
}