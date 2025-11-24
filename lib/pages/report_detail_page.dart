import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'image_viewer_page.dart';
import '../utils/image_url_helper.dart';
import '../widgets/video_player_widget.dart';

class ReportDetailPage extends StatelessWidget {
  final Map<String, dynamic> report;

  const ReportDetailPage({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final timestamp = DateTime.parse(report['timestamp']);
    final confidence = ((report['ai_confidence'] ?? 0.0) * 100).toStringAsFixed(
      1,
    );
    final status = report['status'] ?? 'In Progress';
    final dynamic rawLocation = report['location'];
    final String locationStr = () {
      if (rawLocation == null) return 'Unknown Location';
      if (rawLocation is Map) {
        final addr = rawLocation['address'] ?? rawLocation['name'];
        return (addr?.toString().isNotEmpty ?? false)
            ? addr.toString()
            : rawLocation.toString();
      }
      return rawLocation.toString();
    }();
    final caption = report['caption'] ?? 'No caption available';
    final userCaption = report['user_caption'] ?? '';
    final reportType = report['type'] ?? 'image';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Report Details'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareReport(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () => _showFullScreenImage(context),
                      child: Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: _buildImageWidget(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        // ## FIXED: Replaced deprecated withOpacity ##
                        color: _getStatusColor(
                          status,
                        ).withAlpha(26), // 0.1 opacity
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _getStatusColor(status).withAlpha(77),
                        ), // 0.3 opacity
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getStatusIcon(status),
                            size: 20,
                            color: _getStatusColor(status),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            status,
                            style: TextStyle(
                              color: _getStatusColor(status),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
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
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.psychology,
                          color: Colors.blue,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'AI Analysis',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            // ## FIXED: Replaced deprecated withOpacity ##
                            color: Colors.blue.withAlpha(26), // 0.1 opacity
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '$confidence% confidence',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      caption,
                      style: const TextStyle(fontSize: 16, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            if (userCaption.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.person, color: Colors.green, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Your Caption',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        userCaption,
                        style: const TextStyle(fontSize: 16, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange,
                          size: 24,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Report Details',
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
                      icon: Icons.location_on,
                      label: 'Location',
                      value: locationStr,
                      color: Colors.red,
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
                      icon: reportType == 'image'
                          ? Icons.photo
                          : Icons.videocam,
                      label: 'Type',
                      value: reportType == 'image' ? 'Photo' : 'Video',
                      color: Colors.teal,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      icon: Icons.person_outline,
                      label: 'Reported by',
                      value: '${report['name'] ?? 'Unknown'} (${report['register_number'] ?? 'Unknown'})',
                      color: Colors.indigo,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      icon: Icons.tag,
                      label: 'Report ID',
                      value: report['id'] ?? 'N/A',
                      color: Colors.grey,
                      copyable: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _copyReportDetails(context),
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
                    onPressed: () => _showUpdateStatusDialog(context),
                    icon: const Icon(Icons.edit),
                    label: const Text('Update Status'),
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
                        // Show snackbar or toast
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
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = months[dateTime.month - 1];
    final year = dateTime.year;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day $month $year at $hour:$minute';
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

  void _shareReport(BuildContext context) {
    final reportText =
        '''
Garden Report Details

Status: ${report['status']}
Location: ${report['location']}
Date: ${_formatDateTime(DateTime.parse(report['timestamp']))}

AI Analysis: ${report['caption']}
Confidence: ${((report['ai_confidence'] ?? 0.0) * 100).toStringAsFixed(1)}%

${report['user_caption']?.isNotEmpty == true ? 'User Notes: ${report['user_caption']}\n' : ''}
Reported by: ${report['name']} (${report['register_number']})
Report ID: ${report['id']}
''';
    Clipboard.setData(ClipboardData(text: reportText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report details copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _copyReportDetails(BuildContext context) {
    final reportText =
        '''
Report ID: ${report['id']}
Status: ${report['status']}
Location: ${report['location']}
Date: ${_formatDateTime(DateTime.parse(report['timestamp']))}
AI Analysis: ${report['caption']}
Confidence: ${((report['ai_confidence'] ?? 0.0) * 100).toStringAsFixed(1)}%
${report['user_caption']?.isNotEmpty == true ? 'User Notes: ${report['user_caption']}' : ''}
Reported by: ${report['name']} (${report['register_number']})
''';
    Clipboard.setData(ClipboardData(text: reportText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report details copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showUpdateStatusDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Update Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.hourglass_empty,
                  color: Colors.orange,
                ),
                title: const Text('In Progress'),
                onTap: () {
                  Navigator.of(context).pop();
                  _updateStatus(context, 'In Progress');
                },
              ),
              ListTile(
                leading: const Icon(Icons.verified, color: Colors.blue),
                title: const Text('Resolved'),
                onTap: () {
                  Navigator.of(context).pop();
                  _updateStatus(context, 'Resolved');
                },
              ),
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('Completed'),
                onTap: () {
                  Navigator.of(context).pop();
                  _updateStatus(context, 'Completed');
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

  void _updateStatus(BuildContext context, String newStatus) {
    // In a real app, this would update the status on the server
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Status updated to: $newStatus'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _isVideoUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv'];
    final lowerUrl = url.toLowerCase();
    return videoExtensions.any((ext) => lowerUrl.endsWith(ext));
  }

  Widget _buildImageWidget() {
    final imageUrl = report['imageUrl'] as String?;
    final imagePath = report['image_path'] as String?;
    final reportType = report['type'] ?? 'image';
    
    // Check if it's a video
    final isVideo = _isVideoUrl(imageUrl) || _isVideoUrl(imagePath) || reportType == 'video';

    // Resolve the URL
    final resolvedImageUrl = ImageUrlHelper.resolveImageUrl(imageUrl);
    print('Loading media for report detail - URL: $resolvedImageUrl, isVideo: $isVideo');

    // Handle video
    if (isVideo) {
      String? videoUrl;
      bool isLocalFile = false;
      
      if (resolvedImageUrl.isNotEmpty) {
        videoUrl = resolvedImageUrl;
        isLocalFile = false;
      } else if (imagePath != null && imagePath.isNotEmpty) {
        final videoFile = File(imagePath);
        if (videoFile.existsSync()) {
          videoUrl = imagePath;
          isLocalFile = true;
        }
      }
      
      if (videoUrl != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: double.infinity,
            height: 200,
            child: VideoPlayerWidget(
              videoUrl: videoUrl,
              isLocalFile: isLocalFile,
            ),
          ),
        );
      }
      return _buildPlaceholder(reportType);
    }

    // Handle image
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
        borderRadius: BorderRadius.circular(12),
        child: Image(
          image: imageProvider,
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            print('Error loading image in report detail: $error');
            return _buildPlaceholder(reportType);
          },
        ),
      );
    }

    return _buildPlaceholder(reportType);
  }

  Widget _buildPlaceholder(String reportType) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          reportType == 'image' ? Icons.photo : Icons.videocam,
          size: 64,
          color: Colors.grey[600],
        ),
        const SizedBox(height: 8),
        Text(
          reportType == 'image' ? 'Photo' : 'Video',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Image not available',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
      ],
    );
  }

  void _showFullScreenImage(BuildContext context) {
    final imageUrl = report['imageUrl'] as String?;
    final imagePath = report['image_path'] as String?;
    final reportType = report['type'] ?? 'image';
    
    // Check if it's a video
    final isVideo = _isVideoUrl(imageUrl) || _isVideoUrl(imagePath) || reportType == 'video';

    // Resolve the image URL to ensure it's complete
    final resolvedImageUrl = ImageUrlHelper.resolveImageUrl(imageUrl);

    String? finalMediaUrl;
    bool isLocalFile = false;

    if (resolvedImageUrl.isNotEmpty && (ImageUrlHelper.isValidImageUrl(resolvedImageUrl) || isVideo)) {
      finalMediaUrl = resolvedImageUrl;
      isLocalFile = false;
    } else if (imagePath != null && imagePath.isNotEmpty) {
      final mediaFile = File(imagePath);
      if (mediaFile.existsSync()) {
        finalMediaUrl = imagePath;
        isLocalFile = true;
      }
    }

    if (finalMediaUrl != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ImageViewerPage(
            imageUrl: finalMediaUrl!, // Add null assertion since we checked for null
            title: isVideo ? 'Report Video' : 'Report Image',
            subtitle: report['caption'] ?? '',
            isLocalFile: isLocalFile,
            isVideo: isVideo,
            taskDetails: {
              'originalIssue': report['caption'] ?? 'No caption provided',
              'location': report['location'] ?? 'Unknown location',
              'reportedBy': report['name'] ?? 'Unknown',
              'reportedOn': _formatDateTime(DateTime.parse(report['timestamp'])),
              'status': report['status'] ?? 'Pending',
            },
          ),
        ),
      );
      return;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isVideo ? 'Video not available' : 'Image not available'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

