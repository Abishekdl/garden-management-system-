import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../utils/image_url_helper.dart';
import '../widgets/video_player_widget.dart';

class ImageViewerPage extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String subtitle;
  final Map<String, dynamic>? taskDetails;
  final bool showThankYouMessage;
  final String? staffInfo;
  final bool isLocalFile;
  final bool isVideo;

  const ImageViewerPage({
    super.key,
    required this.imageUrl,
    required this.title,
    this.subtitle = '',
    this.taskDetails,
    this.showThankYouMessage = false,
    this.staffInfo,
    this.isLocalFile = false,
    this.isVideo = false,
  });

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

// Helper function to check if URL is a video
bool _isVideoUrl(String url) {
  final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv'];
  final lowerUrl = url.toLowerCase();
  return videoExtensions.any((ext) => lowerUrl.endsWith(ext));
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.isVideo || _isVideoUrl(widget.imageUrl);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        actions: [
          if (widget.taskDetails != null)
            IconButton(
              icon: Icon(_showDetails ? Icons.info : Icons.info_outline),
              onPressed: () {
                setState(() {
                  _showDetails = !_showDetails;
                });
                HapticFeedback.lightImpact();
              },
              tooltip: 'Task Details',
            ),

        ],
      ),
      body: Stack(
        children: [
          // Main media viewer (image or video)
          Center(
            child: isVideo
                ? VideoPlayerWidget(
                    videoUrl: widget.imageUrl,
                    isLocalFile: widget.isLocalFile,
                  )
                : InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Hero(
                      tag: widget.imageUrl,
                      child: widget.isLocalFile
                          ? _buildLocalImage()
                          : _buildNetworkImage(),
                    ),
                  ),
          ),

          // Thank you message overlay
          if (widget.showThankYouMessage)
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              child: Card(
                color: Colors.green.withOpacity(0.9),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.white,
                        size: 48,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Thank You!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your reported issue has been resolved.',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      if (widget.staffInfo != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Completed by: ${widget.staffInfo}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // Task details overlay
          if (_showDetails && widget.taskDetails != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Card(
                color: Colors.black87,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Task Details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _showDetails = false;
                              });
                            },
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        'Original Issue',
                        widget.taskDetails!['aiCaption'] ??
                            widget.taskDetails!['studentCaption'] ??
                            'No description',
                      ),
                      if (widget.taskDetails!['location'] != null)
                        _buildDetailRow(
                          'Location',
                          widget.taskDetails!['location'],
                        ),
                      if (widget.taskDetails!['studentName'] != null)
                        _buildDetailRow(
                          'Reported by',
                          '${widget.taskDetails!['studentName']} (${widget.taskDetails!['registerNumber'] ?? 'N/A'})',
                        ),
                      if (widget.taskDetails!['completedAt'] != null)
                        _buildDetailRow(
                          'Completed on',
                          _formatDateTime(widget.taskDetails!['completedAt']),
                        ),
                      if (widget.taskDetails!['assignedTo'] != null)
                        _buildDetailRow(
                          'Assigned to',
                          widget.taskDetails!['assignedTo'],
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.white.withOpacity(0.8),
        foregroundColor: Colors.black,
        onPressed: () {
          Navigator.pop(context);
        },
        child: const Icon(Icons.close),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(dynamic dateTime) {
    try {
      DateTime date;
      if (dateTime is String) {
        date = DateTime.parse(dateTime);
      } else if (dateTime is DateTime) {
        date = dateTime;
      } else {
        return 'Unknown date';
      }
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  Widget _buildLocalImage() {
    final file = File(widget.imageUrl);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          print('Error loading local image: $error');
          return _buildErrorWidget();
        },
      );
    } else {
      print('Local file does not exist: ${widget.imageUrl}');
      // Try to load as network image if local file doesn't exist
      return Image.network(
        widget.imageUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                      : null,
                  color: Colors.white,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Loading image...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          print('Error loading network image as fallback: $error');
          return _buildErrorWidget();
        },
      );
    }
  }

  Widget _buildNetworkImage() {
    // Resolve the image URL to ensure it's complete and valid
    final resolvedImageUrl = ImageUrlHelper.resolveImageUrl(widget.imageUrl);
    print('Loading image in viewer: ${widget.imageUrl} -> $resolvedImageUrl');

    if (!ImageUrlHelper.isValidImageUrl(resolvedImageUrl)) {
      print('Invalid URL format: $resolvedImageUrl');
      // Try to load as local file if URL is invalid
      final file = File(widget.imageUrl);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            print('Error loading local image as fallback: $error');
            return _buildErrorWidget();
          },
        );
      } else {
        return _buildErrorWidget();
      }
    }

    return Image.network(
      resolvedImageUrl,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                    : null,
                color: Colors.white,
              ),
              const SizedBox(height: 16),
              const Text(
                'Loading image...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        print('Error loading network image: $error'); // Add this for debugging
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 50),
              const SizedBox(height: 10),
              const Text(
                'Could not load image',
                style: TextStyle(color: Colors.white),
              ),
              Text(
                'URL: $resolvedImageUrl', // Display the resolved URL for debugging
                style: const TextStyle(color: Colors.white70, fontSize: 10),
                textAlign: TextAlign.center,
              ),
              Text(
                'Error: $error', // Display the error for debugging
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image, color: Colors.white, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Failed to load image',
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              setState(() {
                // Trigger rebuild to retry loading
              });
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
