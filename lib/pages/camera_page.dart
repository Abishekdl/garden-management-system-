import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import '../utils/server_config.dart';
import '../services/location_service.dart';
import 'package:geolocator/geolocator.dart';
import 'history_page.dart';
import 'dart:async';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isUploading = false;
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  LocationData? _currentLocation;
  StreamSubscription<LocationData>? _locationSubscription;
  final LocationService _locationService = LocationService();
  List<Map<String, dynamic>> _uploadHistory = [];
  String? _userName;
  String? _registerNumber;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _loadUserData();
    _loadUploadHistory();
    _requestLocationPermission();
    _subscribeToLocationUpdates();
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
    _recordingTimer?.cancel();
    _controller?.dispose();
    _locationSubscription?.cancel();
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

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? 'Unknown';
      _registerNumber = prefs.getString('register_number') ?? 'Unknown';
    });
  }
  
  Future<void> _loadUploadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('upload_history') ?? [];
    setState(() {
      _uploadHistory = historyJson
          .map((item) => json.decode(item) as Map<String, dynamic>)
          .toList();
    });
  }

  Future<void> _saveUploadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson =
        _uploadHistory.map((item) => json.encode(item)).toList();
    await prefs.setStringList('upload_history', historyJson);
  }
  
  void _subscribeToLocationUpdates() {
    _locationSubscription = _locationService.getLocationStream().listen(
      (LocationData locationData) async {
        final address = await _locationService.getAddressFromCoordinates(
          locationData.latitude,
          locationData.longitude,
        );
        if (mounted) {
          setState(() {
            _currentLocation = LocationData(
              latitude: locationData.latitude,
              longitude: locationData.longitude,
              accuracy: locationData.accuracy,
              timestamp: locationData.timestamp,
              address: address,
            );
          });
        }
      },
      onError: (error) {
        print('Error getting location: $error');
        if (error is PermissionDeniedException) {
          _showLocationPermissionDialog();
        }
      },
    );
  }
  
  void _showLocationPermissionDialog([String? message]) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission'),
        content: Text(
          message ??
              'This app needs location permission to tag photos with GPS coordinates for better issue tracking. You can still use the app without location, but staff won\'t know the exact location of reported issues.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Continue Without Location'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _requestLocationPermission();
            },
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestLocationPermission() async {
    LocationService locationService = LocationService();
    bool serviceEnabled = await locationService.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showLocationPermissionDialog(
          'Location services are disabled. Please enable them to use this feature.');
      return;
    }

    bool permissionGranted = await locationService.requestLocationPermission();
    if (!permissionGranted) {
      _showLocationPermissionDialog(
          'Location permissions are denied. Please grant them to use this feature.');
      return;
    }
    await _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position? position = await _locationService.getCurrentPosition();
      if (position != null) {
        final address = await _locationService.getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );
        setState(() {
          _currentLocation = LocationData(
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
            timestamp: position.timestamp,
            address: address,
          );
        });
      }
    } catch (e) {
      print('Error getting current location: $e');
    }
  }

  // Simple photo upload method with location details
  Future<String?> _uploadPhoto(XFile photo, String locationDetails) async {
    print('🚀 Starting photo upload...');
    print('📍 Server URL: ${ServerConfig.baseUrl}');
    print('📍 Upload endpoint: ${ServerConfig.uploadEndpoint}');
    
    // Test server connectivity first
    try {
      final healthUri = Uri.parse('${ServerConfig.baseUrl}/health');
      print('🔍 Testing server connectivity: $healthUri');
      final healthResponse = await http.get(healthUri).timeout(const Duration(seconds: 10));
      print('✅ Server health check: ${healthResponse.statusCode}');
      if (healthResponse.statusCode != 200) {
        if (mounted) _showErrorDialog('Server not accessible. Health check failed with status: ${healthResponse.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Server health check failed: $e');
      if (mounted) _showErrorDialog('Cannot connect to server: $e\n\nPlease check your internet connection.');
      return null;
    }
    
    final uri = Uri.parse(ServerConfig.uploadEndpoint);
    
    try {
      final request = http.MultipartRequest('POST', uri)
        ..fields['name'] = _userName ?? 'Unknown'
        ..fields['register_number'] = _registerNumber ?? 'Unknown'
        ..fields['user_caption'] = locationDetails
        ..fields['latitude'] = _currentLocation != null ? _currentLocation!.latitude.toString() : '0.0'
        ..fields['longitude'] = _currentLocation != null ? _currentLocation!.longitude.toString() : '0.0'
        ..fields['location_accuracy'] = _currentLocation?.accuracy?.toString() ?? '0.0'
        ..fields['location_address'] = _currentLocation?.address ?? ''
        ..fields['location_timestamp'] = DateTime.now().toIso8601String()
        ..files.add(await http.MultipartFile.fromPath('file', photo.path,
            filename: path.basename(photo.path)));
      
      print('📤 Uploading photo for student: $_userName');
      print('📋 Location details: $locationDetails');
      print('📁 Photo path: ${photo.path}');
      
      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      print('📥 Server response status: ${response.statusCode}');
      print('📥 Server response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('✅ Student upload successful: $responseData');
        return responseData['aiCaption'] ?? responseData['caption'] ?? 'Upload successful';
      } else {
        print('❌ Upload failed with status: ${response.statusCode}');
        if (mounted) _showErrorDialog('Server failed to process image. Status: ${response.statusCode}\nResponse: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Upload error: $e');
      if (mounted) _showErrorDialog('Failed to upload photo: $e\n\nPlease check your internet connection.');
      return null;
    }
  }

  // Start video recording
  Future<void> _startVideoRecording() async {
    if (_controller == null || !_controller!.value.isInitialized || _isRecording || _isUploading) return;

    try {
      await _controller!.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });

      // Start timer to show recording duration
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingSeconds++;
        });

        // Auto-stop after 60 seconds (max video length)
        if (_recordingSeconds >= 60) {
          _stopVideoRecording();
        }
      });

      print('🎥 Video recording started');
    } catch (e) {
      print('❌ Error starting video recording: $e');
      _showErrorDialog('Failed to start video recording: $e');
    }
  }

  // Stop video recording and show caption dialog
  Future<void> _stopVideoRecording() async {
    if (_controller == null || !_isRecording) return;

    try {
      _recordingTimer?.cancel();
      final XFile video = await _controller!.stopVideoRecording();
      
      setState(() {
        _isRecording = false;
      });

      print('🎥 Video recording stopped, asking for caption...');
      
      // Show dialog to add caption
      if (mounted) {
        await _showVideoCaptionDialog(video);
      }
    } catch (e) {
      print('❌ Error stopping video: $e');
      _showErrorDialog('Error stopping video: $e');
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
      });
    }
  }

  // Show dialog to add location details for video
  Future<void> _showVideoCaptionDialog(XFile video) async {
    final TextEditingController floorController = TextEditingController();
    final TextEditingController classroomController = TextEditingController();
    
    final Map<String, String>? result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Add Location Details (Optional)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Video recorded: $_recordingSeconds seconds',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  'Location: ${_currentLocation?.address ?? "Unknown"}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Help us locate the issue more precisely:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: floorController,
                  decoration: const InputDecoration(
                    labelText: 'Floor Number (Optional)',
                    hintText: 'e.g., 2nd Floor, Ground Floor',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.layers),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: classroomController,
                  decoration: const InputDecoration(
                    labelText: 'Nearby Classroom/Room (Optional)',
                    hintText: 'e.g., Room 201, Near Lab 3',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.room),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 8),
                const Text(
                  '* These fields are optional',
                  style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(null);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final floor = floorController.text.trim();
                final classroom = classroomController.text.trim();
                Navigator.of(dialogContext).pop({
                  'floor': floor,
                  'classroom': classroom,
                });
              },
              child: const Text('Upload'),
            ),
          ],
        );
      },
    );
    
    // Dispose controllers
    floorController.dispose();
    classroomController.dispose();
    
    // Handle result
    if (result != null) {
      // Build location details string
      String locationDetails = '';
      if (result['floor']!.isNotEmpty) {
        locationDetails += 'Floor: ${result['floor']}';
      }
      if (result['classroom']!.isNotEmpty) {
        if (locationDetails.isNotEmpty) locationDetails += ', ';
        locationDetails += 'Near: ${result['classroom']}';
      }
      
      _uploadVideoWithCaption(video, locationDetails);
    } else {
      // User pressed Cancel
      setState(() {
        _recordingSeconds = 0;
      });
    }
  }

  // Upload video with user caption
  Future<void> _uploadVideoWithCaption(XFile video, String userCaption) async {
    setState(() {
      _isUploading = true;
    });

    try {
      print('🎥 Uploading video with caption: $userCaption');
      final String? caption = await _uploadVideo(video, userCaption);

      if (caption != null) {
        print('✅ Video uploaded successfully');
        
        // Add to upload history
        final newEntry = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'fileName': path.basename(video.path),
          'caption': caption,
          'user_caption': userCaption,
          'latitude': _currentLocation?.latitude ?? 0.0,
          'longitude': _currentLocation?.longitude ?? 0.0,
          'address': _currentLocation?.address ?? '',
          'timestamp': DateTime.now().toIso8601String(),
          'isVideo': true,
          'type': 'video',
          'name': _userName,
          'register_number': _registerNumber,
          'location': _currentLocation?.address ?? '',
          'status': 'Pending',
          'ai_confidence': 0.0,
          'assignedTo': '',
          'notification_sent': true,
          'imageUrl': '',
        };
        
        if (mounted) {
          setState(() => _uploadHistory.insert(0, newEntry));
          _saveUploadHistory();

          _showSuccessDialog('Video Upload Successful!', userCaption);
          
          // Navigate immediately after showing dialog, don't wait
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => HistoryPage(
                  name: _userName ?? 'Unknown',
                  registerNumber: _registerNumber ?? 'Unknown',
                )),
              );
            }
          });
        }
      } else {
        _showErrorDialog('Failed to upload video.');
      }
    } catch (e) {
      print('❌ Error uploading video: $e');
      if (mounted) {
        _showErrorDialog('Error uploading video: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _recordingSeconds = 0;
        });
      }
    }
  }

  // Upload video to server with user caption
  Future<String?> _uploadVideo(XFile video, String userCaption) async {
    print('🚀 Starting video upload...');
    print('📍 Server URL: ${ServerConfig.baseUrl}');
    print('📍 Upload endpoint: ${ServerConfig.uploadEndpoint}');
    
    // Test server connectivity first
    try {
      final healthUri = Uri.parse('${ServerConfig.baseUrl}/health');
      print('🔍 Testing server connectivity: $healthUri');
      final healthResponse = await http.get(healthUri).timeout(const Duration(seconds: 10));
      print('✅ Server health check: ${healthResponse.statusCode}');
      if (healthResponse.statusCode != 200) {
        if (mounted) _showErrorDialog('Server not accessible. Health check failed with status: ${healthResponse.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Server health check failed: $e');
      if (mounted) _showErrorDialog('Cannot connect to server: $e\n\nPlease check your internet connection and server URL.');
      return null;
    }
    
    final uri = Uri.parse(ServerConfig.uploadEndpoint);
    
    try {
      final request = http.MultipartRequest('POST', uri)
        ..fields['name'] = _userName ?? 'Unknown'
        ..fields['register_number'] = _registerNumber ?? 'Unknown'
        ..fields['user_caption'] = userCaption
        ..fields['latitude'] = _currentLocation != null ? _currentLocation!.latitude.toString() : '0.0'
        ..fields['longitude'] = _currentLocation != null ? _currentLocation!.longitude.toString() : '0.0'
        ..fields['location_accuracy'] = _currentLocation?.accuracy?.toString() ?? '0.0'
        ..fields['location_address'] = _currentLocation?.address ?? ''
        ..fields['location_timestamp'] = DateTime.now().toIso8601String()
        ..files.add(await http.MultipartFile.fromPath('file', video.path,
            filename: path.basename(video.path)));
      
      print('📤 Uploading video for student: $_userName');
      print('📁 Video path: ${video.path}');
      print('📝 User caption: $userCaption');
      print('📦 File size: ${await File(video.path).length()} bytes');
      
      final streamedResponse = await request.send().timeout(const Duration(seconds: 120)); // Increased timeout for videos
      final response = await http.Response.fromStream(streamedResponse);

      print('📥 Server response status: ${response.statusCode}');
      print('📥 Server response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final responseData = json.decode(response.body);
          print('✅ Video upload successful: $responseData');
          return responseData['aiCaption'] ?? responseData['caption'] ?? userCaption;
        } catch (e) {
          print('⚠️ Response parsing error: $e');
          return userCaption;
        }
      } else {
        print('❌ Upload failed with status: ${response.statusCode}');
        print('❌ Response body: ${response.body}');
        if (mounted) _showErrorDialog('Server failed to process video.\nStatus: ${response.statusCode}\n\nPlease check if the server is running and accessible.');
        return null;
      }
    } catch (e) {
      print('❌ Upload error: $e');
      if (mounted) _showErrorDialog('Failed to upload video: $e\n\nPlease check your internet connection and try again.');
      return null;
    }
  }

  Future<void> _takePictureAndUpload() async {
    if (_controller == null || !_controller!.value.isInitialized || _isUploading || _isRecording) return;

    try {
      print('Taking photo for student: $_userName');
      final XFile photo = await _controller!.takePicture();
      
      print('Photo taken, asking for location details...');
      
      // Show dialog to add location details
      if (mounted) {
        await _showPhotoLocationDialog(photo);
      }
    } catch (e) {
      print('Error taking picture: $e');
      _showErrorDialog('Error taking picture: $e');
    }
  }

  // Show dialog to add location details for photo
  Future<void> _showPhotoLocationDialog(XFile photo) async {
    final TextEditingController floorController = TextEditingController();
    final TextEditingController classroomController = TextEditingController();
    
    final Map<String, String>? result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Add Location Details (Optional)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Location: ${_currentLocation?.address ?? "Unknown"}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Help us locate the issue more precisely:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: floorController,
                  decoration: const InputDecoration(
                    labelText: 'Floor Number (Optional)',
                    hintText: 'e.g., 2nd Floor, Ground Floor',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.layers),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: classroomController,
                  decoration: const InputDecoration(
                    labelText: 'Nearby Classroom/Room (Optional)',
                    hintText: 'e.g., Room 201, Near Lab 3',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.room),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 8),
                const Text(
                  '* These fields are optional',
                  style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(null);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final floor = floorController.text.trim();
                final classroom = classroomController.text.trim();
                Navigator.of(dialogContext).pop({
                  'floor': floor,
                  'classroom': classroom,
                });
              },
              child: const Text('Upload'),
            ),
          ],
        );
      },
    );
    
    // Dispose controllers
    floorController.dispose();
    classroomController.dispose();
    
    // Handle result
    if (result != null) {
      // Build location details string
      String locationDetails = '';
      if (result['floor']!.isNotEmpty) {
        locationDetails += 'Floor: ${result['floor']}';
      }
      if (result['classroom']!.isNotEmpty) {
        if (locationDetails.isNotEmpty) locationDetails += ', ';
        locationDetails += 'Near: ${result['classroom']}';
      }
      
      _uploadPhotoWithDetails(photo, locationDetails);
    }
    // If cancelled, just don't upload
  }

  // Upload photo with location details
  Future<void> _uploadPhotoWithDetails(XFile photo, String locationDetails) async {
    setState(() { _isUploading = true; });

    try {
      print('Uploading photo with details: $locationDetails');
      final String? caption = await _uploadPhoto(photo, locationDetails);

      if (caption != null) {
        print('Photo uploaded successfully with caption: $caption');
        
        // Add to upload history
        final newEntry = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'fileName': path.basename(photo.path),
          'caption': caption,
          'user_caption': locationDetails,
          'latitude': _currentLocation?.latitude ?? 0.0,
          'longitude': _currentLocation?.longitude ?? 0.0,
          'address': _currentLocation?.address ?? '',
          'timestamp': DateTime.now().toIso8601String(),
          'isVideo': false,
          'type': 'image',
          'name': _userName,
          'register_number': _registerNumber,
          'location': _currentLocation?.address ?? '',
          'status': 'Pending',
          'ai_confidence': 0.85,
          'assignedTo': '',
          'notification_sent': true,
          'imageUrl': '',
        };
        
        if (mounted) {
          setState(() => _uploadHistory.insert(0, newEntry));
          _saveUploadHistory();

          _showSuccessDialog('Upload Successful!', 'AI Caption: $caption');
          
          // Navigate immediately after showing dialog, don't wait
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => HistoryPage(
                  name: _userName ?? 'Unknown',
                  registerNumber: _registerNumber ?? 'Unknown',
                )),
              );
            }
          });
        }
      } else {
        _showErrorDialog('Failed to upload photo.');
      }
    } catch (e) {
      print('Error uploading picture: $e');
      if (mounted) {
        _showErrorDialog('Error uploading picture: $e');
      }
    } finally {
      if (mounted) {
        setState(() { _isUploading = false; });
      }
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

  void _showSuccessDialog(String title, [String? message]) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message ?? 'Operation completed successfully.'),
        actions: <Widget>[
          TextButton(
            child: const Text('Ok'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
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

          // Top gradient for contrast
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

          // Location indicator
          if (_currentLocation != null)
            Positioned(
              top: 50,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'GPS',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom gradient for contrast
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 200,
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

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Recording timer (shown during recording)
                    if (_isRecording)
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_recordingSeconds ~/ 60}:${(_recordingSeconds % 60).toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Hint text just above shutter
                    if (!_isRecording)
                      Container(
                        margin: const EdgeInsets.only(bottom: 30),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          'Tap for photo • Hold for video',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    
                    // Main control row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Gallery/History button
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => HistoryPage(
                                  name: _userName ?? 'Unknown',
                                  registerNumber: _registerNumber ?? 'Unknown',
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                            ),
                            child: const Icon(
                              Icons.photo_library_outlined,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                        
                        // Main capture button (Snapchat-style with long press for video)
                        GestureDetector(
                          onTap: (_isUploading || _isRecording) ? null : _takePictureAndUpload,
                          onLongPressStart: (_) {
                            if (!_isUploading && !_isRecording) {
                              _startVideoRecording();
                            }
                          },
                          onLongPressEnd: (_) {
                            if (_isRecording) {
                              _stopVideoRecording();
                            }
                          },
                          child: Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isRecording ? Colors.red : Colors.white,
                                width: 4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isRecording ? Colors.red : Colors.black).withOpacity(0.3),
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
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      width: _isRecording ? 32 : 68,
                                      height: _isRecording ? 32 : 68,
                                      decoration: BoxDecoration(
                                        color: _isRecording ? Colors.red : Colors.white,
                                        borderRadius: _isRecording ? BorderRadius.circular(8) : null,
                                        shape: _isRecording ? BoxShape.rectangle : BoxShape.circle,
                                      ),
                                      child: _isRecording
                                          ? null
                                          : const Icon(Icons.camera_alt, color: Colors.black87),
                                    ),
                                  ),
                          ),
                        ),
                        
                        // Settings/Options placeholder
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}