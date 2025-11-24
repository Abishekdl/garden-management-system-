import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import '../utils/server_config.dart';
import '../utils/image_url_helper.dart';
import '../services/notification_service.dart'; // Import NotificationService

class StaffCameraPage extends StatefulWidget {
  final String taskId;
  final String staffId;

  const StaffCameraPage({
    super.key,
    required this.taskId,
    required this.staffId,
  });

  @override
  State<StaffCameraPage> createState() => _StaffCameraPageState();
}

class _StaffCameraPageState extends State<StaffCameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isNotEmpty) {
        _controller = CameraController(_cameras![0], ResolutionPreset.high);
        await _controller!.initialize();
        // Ensure non-zoomed default view
        try {
          final double minZoom = await _controller!.getMinZoomLevel();
          final double maxZoom = await _controller!.getMaxZoomLevel();
          await _controller!.setZoomLevel(minZoom.clamp(1.0, maxZoom));
        } catch (_) {}
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
      }
    } catch (e) {
      if (mounted) _showErrorDialog('Failed to initialize camera: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed && _controller != null && _controller!.value.isInitialized) {
      try {
        final double minZoom = await _controller!.getMinZoomLevel();
        final double maxZoom = await _controller!.getMaxZoomLevel();
        await _controller!.setZoomLevel(minZoom.clamp(1.0, maxZoom));
      } catch (_) {}
    }
  }

  // Upload completion photo to server
  Future<String?> _uploadCompletionPhoto(XFile photo) async {
    // Use server configuration URL
    final uri = Uri.parse(ServerConfig.completeTaskEndpoint);
    
    try {
      final request = http.MultipartRequest('POST', uri)
        // Add the taskId and staffId as fields in the request
        ..fields['taskId'] = widget.taskId
        ..fields['staffId'] = widget.staffId
        ..files.add(await http.MultipartFile.fromPath('file', photo.path,
            filename: path.basename(photo.path)));
      
      print('Uploading completion photo for task: ${widget.taskId}');
      
      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      print('Server response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('Staff upload response: $responseData');
        return responseData['completedImageUrl'] ?? responseData['imageUrl'] ?? responseData['image_url'];
      } else {
        if (mounted) _showErrorDialog('Server failed to process image. Status: ${response.statusCode}\nResponse: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Upload error: $e');
      if (mounted) _showErrorDialog('Failed to upload photo: $e');
      return null;
    }
  }

  Future<void> _updateTaskInFirestore(String completedImageUrl) async {
    try {
      final taskRef = FirebaseFirestore.instance.collection('tasks').doc(widget.taskId);
      
      print('Updating task ${widget.taskId} to completed status');
      
      await taskRef.update({
        'status': 'completed',
        'completedBy': widget.staffId,
        'completionImageUrl': completedImageUrl,
        'imageUrl': completedImageUrl,  // Add for consistent image display
        'completedAt': FieldValue.serverTimestamp(),
        'completedDate': DateTime.now().toIso8601String().split('T')[0],
      });
      
      print('Task successfully updated in Firestore');

    } catch (e) {
      print('Firestore update error: $e');
      if (mounted) _showErrorDialog('Failed to update task in Firestore: $e');
      throw e; // Re-throw to handle in calling function
    }
  }

  Future<void> _takePictureAndCompleteTask() async {
    if (_controller == null || !_controller!.value.isInitialized || _isUploading) return;

    setState(() { _isUploading = true; });

    try {
      print('Taking completion photo for task: ${widget.taskId}');
      final XFile photo = await _controller!.takePicture();
      
      print('Photo taken, uploading to server...');
      final String? completedImageUrl = await _uploadCompletionPhoto(photo);

      if (completedImageUrl != null) {
        print('Completion photo uploaded successfully: $completedImageUrl');
        await _updateTaskInFirestore(completedImageUrl);

        // Fetch task data to get studentId
        final taskDoc = await FirebaseFirestore.instance.collection('tasks').doc(widget.taskId).get();
        final studentId = taskDoc.data()?['registerNumber'];

        // Update upload_history in SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final historyJson = prefs.getStringList('upload_history') ?? [];
        final uploadHistory = historyJson
            .map((item) => json.decode(item) as Map<String, dynamic>).toList();

        uploadHistory.add({
          'taskId': widget.taskId,
          'status': 'Completed',
          'completedImageUrl': completedImageUrl,
          'imageUrl': completedImageUrl,  // Add for consistent display
          'completedAt': DateTime.now().toIso8601String(),
        });
        await prefs.setStringList('upload_history', uploadHistory.map((item) => json.encode(item)).toList());


        if (studentId != null) {
          await NotificationService.sendThankYouNotification(
            studentId: studentId,
            taskId: widget.taskId,
            staffId: widget.staffId,
          );
          print('"Thank you" notification sent to student $studentId');
        }

        Navigator.pop(context, true); // Go back to the previous screen
      } else {
        _showErrorDialog('Failed to upload completion photo.');
      }
    } catch (e) {
      print('Error taking or uploading picture: $e');
      _showErrorDialog('Error taking or uploading picture: $e');
    } finally {
      setState(() { _isUploading = false; });
    }
  }
  
  void _showErrorDialog(String message) {
    if(mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen preview with cover fit (no black bars), still at zoom 1.0
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: Builder(
                builder: (context) {
                  final size = MediaQuery.of(context).size;
                  final previewSize = _controller!.value.previewSize; // may be null on some devices
                  final double childWidth = previewSize != null ? previewSize.height : size.width;
                  final double childHeight = previewSize != null
                      ? previewSize.width
                      : (size.width / _controller!.value.aspectRatio);
                  return SizedBox(
                    width: childWidth,
                    height: childHeight,
                    child: CameraPreview(_controller!),
                  );
                },
              ),
            ),
          ),

          // Top gradient for contrast + floating back button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 110,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.45),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),


          // Bottom gradient for contrast
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 150,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.45),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Hint text just above shutter
          Positioned(
            bottom: 170,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Tap to capture completion photo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

          // Centered shutter button (Snapchat-style)
          Positioned(
            bottom: 90,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isUploading ? null : _takePictureAndCompleteTask,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _isUploading
                      ? const Padding(
                          padding: EdgeInsets.all(18.0),
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : Center(
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt, color: Colors.black87),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}