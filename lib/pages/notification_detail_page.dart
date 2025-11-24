import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../utils/image_url_helper.dart';
import '../widgets/video_player_widget.dart';
import 'image_viewer_page.dart';

class NotificationDetailPage extends StatefulWidget {
  final Map<String, dynamic> notification;

  const NotificationDetailPage({
    super.key,
    required this.notification,
  });

  @override
  State<NotificationDetailPage> createState() => _NotificationDetailPageState();
}

class _NotificationDetailPageState extends State<NotificationDetailPage> {
  late Map<String, dynamic> notification;
  
  @override
  void initState() {
    super.initState();
    notification = Map<String, dynamic>.from(widget.notification);
  }

  bool _isVideoUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv'];
    final lowerUrl = url.toLowerCase();
    return videoExtensions.any((ext) => lowerUrl.endsWith(ext));
  }

  @override
  Widget build(BuildContext context) {
    // Debug: Print notification data to understand what we're receiving
    print('=== NOTIFICATION DETAIL DEBUG ===');
    print('Full notification data: $notification');
    print('imageUrl: ${notification['imageUrl']}');
    print('type: ${notification['type']}');
    print('================================');
    
    final timestamp = _safeParseTimestamp(notification['timestamp']);
    final isRead = notification['read'] ?? false;
    final title = notification['title'] ?? 'Staff Message';
    final message = notification['message'] ?? 'No message content';
    final sender = notification['sender'] ?? 'Staff';
    final type = notification['type'] ?? 'general';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Notification Details'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareNotification(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // If the notification data contains an imageUrl, display it (or video)
            // Check multiple possible field names
            if ((notification.containsKey('imageUrl') && notification['imageUrl'].toString().isNotEmpty) ||
                (notification.containsKey('completionImageUrl') && notification['completionImageUrl'].toString().isNotEmpty) ||
                (notification.containsKey('completedImageUrl') && notification['completedImageUrl'].toString().isNotEmpty) ||
                (notification.containsKey('image_url') && notification['image_url'].toString().isNotEmpty)) ...[
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: GestureDetector(
                    onTap: () => _showFullScreenImage(context),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12.0),
                      child: SizedBox(
                        height: 200,
                        child: _buildMediaWidget(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              // Debug: Show why image is not displaying
              Card(
                elevation: 2,
                color: Colors.orange[50],
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange),
                          SizedBox(width: 8),
                          Text('Debug Info', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Has imageUrl key: ${notification.containsKey('imageUrl')}'),
                      Text('imageUrl value: ${notification['imageUrl']}'),
                      Text('imageUrl isEmpty: ${notification['imageUrl']?.toString().isEmpty ?? true}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Header Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title and Read Status
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Type Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        // ## UPDATED: Replaced deprecated withOpacity with withAlpha ##
                        color: _getTypeColor(type).withAlpha(26), // 0.1 opacity
                        borderRadius: BorderRadius.circular(16),
                        // ## UPDATED: Replaced deprecated withOpacity with withAlpha ##
                        border: Border.all(color: _getTypeColor(type).withAlpha(77)), // 0.3 opacity
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getTypeIcon(type),
                            size: 16,
                            color: _getTypeColor(type),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _getTypeLabel(type),
                            style: TextStyle(
                              color: _getTypeColor(type),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Message Content Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.message, color: Colors.blue, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'Message',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Details Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'Details',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    _buildDetailRow(
                      icon: Icons.person,
                      label: 'From',
                      value: sender,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      icon: Icons.access_time,
                      label: 'Date & Time',
                      value: _formatDateTime(timestamp),
                      color: Colors.purple,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      icon: isRead ? Icons.mark_email_read : Icons.mark_email_unread,
                      label: 'Status',
                      value: isRead ? 'Read' : 'Unread',
                      color: isRead ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      icon: Icons.tag,
                      label: 'Notification ID',
                      value: notification['id'] ?? 'N/A',
                      color: Colors.grey,
                      copyable: true,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _copyNotificationDetails(context),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Details'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isRead ? null : () => _markAsRead(context),
                    icon: const Icon(Icons.mark_email_read),
                    label: Text(isRead ? 'Already Read' : 'Mark as Read'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  DateTime _safeParseTimestamp(dynamic raw) {
    if (raw is DateTime) return raw.toLocal();
    if (raw == null) return DateTime.now();
    String s = raw.toString().trim();
    // Normalize common issues: space separator and double timezone markers
    if (s.contains(' ') && !s.contains('T')) {
      s = s.replaceFirst(' ', 'T');
    }
    if (s.endsWith('Z') && s.contains('+')) {
      s = s.substring(0, s.length - 1); // drop extra Z if offset already present
    }
    DateTime? dt = DateTime.tryParse(s);
    if (dt != null) return dt.toLocal();
    // Fallbacks: remove trailing Z or offset and retry
    s = s.replaceAll(RegExp(r'Z$'), '');
    s = s.replaceAll(RegExp(r'\+\d{2}:\d{2}$'), '');
    dt = DateTime.tryParse(s);
    return (dt ?? DateTime.now()).toLocal();
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool copyable = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (copyable)
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: value));
                        // Show snackbar
                      },
                      child: Icon(
                        Icons.copy,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final months = [ 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' ];
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = months[dateTime.month - 1];
    final year = dateTime.year;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day $month $year at $hour:$minute';
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'update': return Colors.blue;
      case 'appreciation': return Colors.green;
      case 'warning': return Colors.orange;
      case 'urgent': return Colors.red;
      case 'task_completed': return Colors.green;
      default: return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'update': return Icons.update;
      case 'appreciation': return Icons.thumb_up;
      case 'warning': return Icons.warning;
      case 'urgent': return Icons.priority_high;
      case 'task_completed': return Icons.check_circle;
      default: return Icons.info;
    }
  }

  String _getTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'update': return 'Update';
      case 'appreciation': return 'Appreciation';
      case 'warning': return 'Warning';
      case 'urgent': return 'Urgent';
      case 'task_completed': return 'Task Completed';
      default: return 'General';
    }
  }

  void _shareNotification(BuildContext context) {
    final notificationText = '''
Notification Details

Title: ${notification['title']}
From: ${notification['sender']}
Date: ${_formatDateTime(DateTime.parse(notification['timestamp'] ?? DateTime.now().toIso8601String()))}
Type: ${_getTypeLabel(notification['type'] ?? 'general')}

Message:
${notification['message']}

Notification ID: ${notification['id']}
''';
    Clipboard.setData(ClipboardData(text: notificationText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notification details copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _copyNotificationDetails(BuildContext context) {
    final notificationText = '''
Title: ${notification['title']}
From: ${notification['sender']}
Date: ${_formatDateTime(_safeParseTimestamp(notification['timestamp']))}
Type: ${_getTypeLabel(notification['type'] ?? 'general')}
Message: ${notification['message']}
Notification ID: ${notification['id']}
''';
    Clipboard.setData(ClipboardData(text: notificationText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notification details copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _markAsRead(BuildContext context) async {
    try {
      // Update local state
      setState(() {
        notification['read'] = true;
      });
      
      // Update in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final notificationsJson = prefs.getStringList('notifications') ?? [];
      
      // Find and update the notification
      final updatedNotifications = notificationsJson.map((item) {
        final notif = json.decode(item) as Map<String, dynamic>;
        if (notif['id'] == notification['id']) {
          notif['read'] = true;
        }
        return json.encode(notif);
      }).toList();
      
      await prefs.setStringList('notifications', updatedNotifications);
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Notification marked as read'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error marking notification as read: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
  // Build media widget (image or video)
  Widget _buildMediaWidget() {
    // Try multiple possible field names for the completion image
    final imageUrl = notification['imageUrl'] ?? 
                     notification['completionImageUrl'] ?? 
                     notification['completedImageUrl'] ?? 
                     notification['image_url'];
    final resolvedUrl = ImageUrlHelper.resolveImageUrl(imageUrl);
    final isVideo = _isVideoUrl(resolvedUrl);
    
    if (isVideo) {
      return Container(
        height: 200,
        color: Colors.black,
        child: VideoPlayerWidget(
          videoUrl: resolvedUrl,
          isLocalFile: false,
        ),
      );
    }
    
    return Image.network(
      resolvedUrl,
      height: 200,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(child: CircularProgressIndicator());
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: 200,
          color: Colors.grey[200],
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, size: 48, color: Colors.grey),
                SizedBox(height: 8),
                Text('Media not available', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );
  }

  // Add this method to the class
  void _showFullScreenImage(BuildContext context) {
    // Try multiple possible field names for the completion image
    final imageUrl = notification['imageUrl'] ?? 
                     notification['completionImageUrl'] ?? 
                     notification['completedImageUrl'] ?? 
                     notification['image_url'];
    final resolvedUrl = ImageUrlHelper.resolveImageUrl(imageUrl);
    final isVideo = _isVideoUrl(resolvedUrl);
    
    if (imageUrl != null && imageUrl.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImageViewerPage(
            imageUrl: resolvedUrl,
            title: isVideo ? 'Completion Video' : 'Completion Photo',
            subtitle: notification['message'] ?? '',
            isLocalFile: false,
            isVideo: isVideo,
            taskDetails: {
              'originalIssue': notification['message'] ?? 'No description',
              'completedAt': notification['timestamp'],
              'staffInfo': notification['sender'] ?? 'Staff',
            },
            showThankYouMessage: notification['type'] == 'task_completed',
            staffInfo: notification['sender'],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Media not available'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

