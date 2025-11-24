import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/location_service.dart';
import '../utils/image_url_helper.dart';
import '../utils/server_config.dart';
import '../utils/navigation_helper.dart';
import '../widgets/video_player_widget.dart';
import 'staff_camera_page.dart';
import 'image_viewer_page.dart';

class TaskDetailPage extends StatefulWidget {
  final QueryDocumentSnapshot task;

  const TaskDetailPage({super.key, required this.task});

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  // Removed live distance calculation and GPS UI per request

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Distance and GPS helpers removed
  @override
  Widget build(BuildContext context) {
    final taskData = widget.task.data() as Map<String, dynamic>;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Task Details'),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Display the image from the URL
            GestureDetector(
              onTap: () => _showImageOptions(context, taskData),
              child: Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildTaskImage(taskData),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Display the AI Caption
            Text(
              'AI Generated Caption',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              taskData['aiCaption'] ?? taskData['caption'] ?? 'No Caption',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            
            // Display student caption if available
            if (taskData['studentCaption'] != null && taskData['studentCaption'].toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Student Notes',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                taskData['studentCaption'],
                style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
              ),
            ],
            
            const Divider(height: 32),

            // Display other details with navigation button
            _buildLocationRow(context, taskData),
            // Distance and GPS coordinates removed from UI as requested
            _buildDetailRow(
              icon: Icons.calendar_today,
              title: 'Created Date',
              content: _formatTimestamp(taskData['createdAt']),
            ),
            _buildDetailRow(
              icon: Icons.person,
              title: 'Reported By',
              content: '${taskData['studentName'] ?? 'Unknown'} (${taskData['registerNumber'] ?? 'N/A'})',
            ),
            _buildDetailRow(
              icon: Icons.engineering,
              title: 'Assigned To',
              content: taskData['assignedTo'] ?? 'Not Assigned',
            ),
            _buildDetailRow(
              icon: Icons.info_outline,
              title: 'Status',
              content: (taskData['status'] ?? 'pending').toString().toUpperCase(),
              contentColor: taskData['status'] == 'completed' ? Colors.green : Colors.orange,
            ),
          ],
        ),
      ),
      floatingActionButton: taskData['status'] == 'pending' 
        ? Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Removed the "Mark Done" button and its SizedBox
              FloatingActionButton.extended(
                heroTag: "complete_photo",
                onPressed: () async {
                  // Get current staff ID from SharedPreferences
                  final prefs = await SharedPreferences.getInstance();
                  final currentStaffId = prefs.getString('staff_id') ?? 'staff1';

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => StaffCameraPage(
                        taskId: widget.task.id,
                        staffId: currentStaffId,
                      ),
                    ),
                  );
                },
                label: const Text('Photo'),
                icon: const Icon(Icons.camera_alt),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ],
          )
        : FloatingActionButton.extended(
            onPressed: null,
            label: const Text('Task Completed'),
            icon: const Icon(Icons.check_circle),
            backgroundColor: Colors.grey,
            foregroundColor: Colors.white,
          ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'No Date';
    
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else {
        return 'Invalid Date';
      }
      
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Invalid Date';
    }
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String title,
    required String content,
    Color? contentColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blueGrey, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 2),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: contentColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildGpsDetailRow(BuildContext context, Map<String, dynamic> gpsData) {
    double? latitude = gpsData['latitude']?.toDouble();
    double? longitude = gpsData['longitude']?.toDouble();
    double? accuracy = gpsData['accuracy']?.toDouble();
    String address = gpsData['address'] ?? 'Unknown Address';
    
    if (latitude == null || longitude == null) {
      return const SizedBox.shrink();
    }
    
    String coordinates = '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
    String accuracyText = accuracy != null ? '±${accuracy.toStringAsFixed(1)}m' : 'Unknown';
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gps_fixed, color: Colors.blueGrey, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GPS Coordinates',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 2),
                Text(
                  coordinates,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      accuracy != null && accuracy < 10 
                        ? Icons.gps_fixed 
                        : Icons.gps_not_fixed,
                      size: 16,
                      color: accuracy != null && accuracy < 10 
                        ? Colors.green 
                        : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Accuracy: $accuracyText',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                if (address.isNotEmpty && address != 'Unknown Address') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.map, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            address,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _openInMaps(context, latitude, longitude),
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Icon(Icons.open_in_new, size: 16, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _markAsCompleted(BuildContext context) async {
    try {
      // Show confirmation dialog
      bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mark Task as Completed'),
          content: const Text('Are you sure you want to mark this task as completed?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Mark Completed'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Updating task status...'),
            ],
          ),
        ),
      );

      // Get current staff ID
      final prefs = await SharedPreferences.getInstance();
      final staffId = prefs.getString('staff_id') ?? 'Garden Staff';
      
      // Call the server to mark task as completed
      final uri = Uri.parse('${ServerConfig.baseUrl}/mark_completed');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'taskId': widget.task.id,
          'staffId': staffId,
        }),
      );

      Navigator.of(context).pop(); // Close loading dialog

      if (response.statusCode == 200) {
        // Success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task marked as completed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(); // Go back to dashboard
      } else {
        throw Exception('Failed to update task: ${response.statusCode}');
      }
    } catch (e) {
      Navigator.of(context).pop(); // Close any open dialogs
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openInMaps(BuildContext context, double latitude, double longitude) {
    // This would open the coordinates in the default maps application
    // For now, just show a dialog with map link options
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open in Maps'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Coordinates: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}'),
            const SizedBox(height: 16),
            const Text('Map links:'),
            const SizedBox(height: 8),
            SelectableText(
              'Google Maps: https://maps.google.com/?q=$latitude,$longitude',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  bool _isVideoUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv'];
    final lowerUrl = url.toLowerCase();
    return videoExtensions.any((ext) => lowerUrl.endsWith(ext));
  }

  Widget _buildTaskImage(Map<String, dynamic> taskData) {
    final imageUrl = taskData['imageUrl'];
    final resolvedImageUrl = ImageUrlHelper.resolveImageUrl(imageUrl);
    
    // Check if it's a video
    final isVideo = _isVideoUrl(resolvedImageUrl);
    
    print('Loading task media URL: $resolvedImageUrl (isVideo: $isVideo)');
    
    if (resolvedImageUrl.isEmpty) {
      return Container(
        width: double.infinity,
        height: 250,
        color: Colors.grey[300],
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 8),
            Text('Media not available', style: TextStyle(color: Colors.grey[600])),
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('URL: $imageUrl', style: TextStyle(color: Colors.grey[500], fontSize: 10)),
            ],
          ],
        ),
      );
    }
    
    // If it's a video, use video player
    if (isVideo) {
      return Container(
        width: double.infinity,
        height: 250,
        color: Colors.black,
        child: VideoPlayerWidget(
          videoUrl: resolvedImageUrl,
          isLocalFile: false,
        ),
      );
    }
    
    // Otherwise, display as image
    if (!ImageUrlHelper.isValidImageUrl(resolvedImageUrl)) {
      return Container(
        width: double.infinity,
        height: 250,
        color: Colors.grey[300],
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 8),
            Text('Invalid media URL', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }
    
    return Image.network(
      resolvedImageUrl,
      width: double.infinity,
      height: 250,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: double.infinity,
          height: 250,
          color: Colors.grey[200],
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        print('Error loading task image: $error');
        return Container(
          width: double.infinity,
          height: 250,
          color: Colors.grey[300],
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 48, color: Colors.red[400]),
              const SizedBox(height: 8),
              Text('Failed to load image', style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 4),
              Text('Error: $error', style: TextStyle(color: Colors.grey[500], fontSize: 10)),
            ],
          ),
        );
      },
    );
  }

  // Show options dialog when image is tapped
  void _showImageOptions(BuildContext context, Map<String, dynamic> taskData) {
    final gpsData = taskData['gpsData'] as Map<String, dynamic>?;
    final hasLocation = gpsData != null && 
                       gpsData['latitude'] != null && 
                       gpsData['longitude'] != null;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Options'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.fullscreen, color: Colors.blue),
                title: const Text('View Full Picture'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showFullScreenImage(context);
                },
              ),
              if (hasLocation)
                ListTile(
                  leading: const Icon(Icons.navigation, color: Colors.green),
                  title: const Text('Navigate to Location'),
                  subtitle: Text(taskData['location'] ?? 'Report location'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _navigateToTaskLocation(context, taskData);
                  },
                ),
              if (hasLocation)
                ListTile(
                  leading: const Icon(Icons.map, color: Colors.orange),
                  title: const Text('Show on Map'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showOnMap(context, taskData);
                  },
                ),
            ],
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

  // Navigate to task location using Google Maps
  void _navigateToTaskLocation(BuildContext context, Map<String, dynamic> taskData) {
    final gpsData = taskData['gpsData'] as Map<String, dynamic>?;
    
    if (gpsData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location data not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final latitude = gpsData['latitude']?.toDouble();
    final longitude = gpsData['longitude']?.toDouble();
    
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid location coordinates'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final locationName = taskData['location'] ?? 'Report Location';
    
    NavigationHelper.navigateToLocation(
      context: context,
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
    );
  }

  // Show location on map (view only)
  void _showOnMap(BuildContext context, Map<String, dynamic> taskData) {
    final gpsData = taskData['gpsData'] as Map<String, dynamic>?;
    
    if (gpsData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location data not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final latitude = gpsData['latitude']?.toDouble();
    final longitude = gpsData['longitude']?.toDouble();
    
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid location coordinates'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final locationName = taskData['location'] ?? 'Report Location';
    
    NavigationHelper.showLocationOnMap(
      context: context,
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
    );
  }

  // Build location row with navigation button
  Widget _buildLocationRow(BuildContext context, Map<String, dynamic> taskData) {
    final gpsData = taskData['gpsData'] as Map<String, dynamic>?;
    final hasLocation = gpsData != null && 
                       gpsData['latitude'] != null && 
                       gpsData['longitude'] != null;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on, color: Colors.blueGrey, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Location',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 2),
                Text(
                  taskData['location'] ?? 'Unknown Location',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (hasLocation) ...[
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _navigateToTaskLocation(context, taskData),
                    icon: const Icon(Icons.navigation, size: 18),
                    label: const Text('Navigate Here'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Add this method to the class
  void _showFullScreenImage(BuildContext context) {
    final taskData = widget.task.data() as Map<String, dynamic>;
    final imageUrl = taskData['imageUrl'];
    final resolvedImageUrl = ImageUrlHelper.resolveImageUrl(imageUrl);
    final isVideo = _isVideoUrl(resolvedImageUrl);
    
    if (resolvedImageUrl.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImageViewerPage(
            imageUrl: resolvedImageUrl,
            title: isVideo ? 'Task Video' : 'Task Image',
            subtitle: taskData['aiCaption'] ?? taskData['caption'] ?? '',
            isLocalFile: false,
            isVideo: isVideo,
            taskDetails: {
              'aiCaption': taskData['aiCaption'] ?? taskData['caption'] ?? 'No description',
              'studentCaption': taskData['studentCaption'],
              'location': taskData['location'] ?? 'Unknown location',
              'studentName': taskData['studentName'] ?? 'Unknown',
              'registerNumber': taskData['registerNumber'],
              'status': taskData['status'] ?? 'pending',
              'assignedTo': taskData['assignedTo'],
            },
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
