import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/location_service.dart';
import 'task_detail_page.dart';
import 'image_viewer_page.dart';

class StaffDashboardPage extends StatefulWidget {
  const StaffDashboardPage({super.key});

  @override
  State<StaffDashboardPage> createState() => _StaffDashboardPageState();
}

class _StaffDashboardPageState extends State<StaffDashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _staffId;
  final LocationService _locationService = LocationService();
  StreamSubscription<LocationData>? _locationSubscription;
  LocationData? _staffLocation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStaffId();
    _subscribeToLocationUpdates();
  }

  void _subscribeToLocationUpdates() {
    _locationSubscription = _locationService.getLocationStream().listen((locationData) {
      if (mounted) {
        setState(() {
          _staffLocation = locationData;
        });
      }
    });
  }

  Future<void> _loadStaffId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _staffId = prefs.getString('staff_id') ?? 'staff1';
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _locationSubscription?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _prepareTaskDetails(Map<String, dynamic> taskData) {
    // Create a new map to avoid modifying the original
    Map<String, dynamic> preparedData = Map<String, dynamic>.from(taskData);
    
    // Handle location data properly
    if (preparedData.containsKey('location') && preparedData['location'] != null) {
      if (preparedData['location'] is Map) {
        // Already in the correct format
      } else if (preparedData['location'] is String) {
        // Convert string location to map format
        preparedData['location'] = {'address': preparedData['location']};
      }
    } else {
      preparedData['location'] = {'address': 'Unknown Location'};
    }
    
    return preparedData;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Dashboard'),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false, // Remove back button since we're using bottom navigation
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.pending_actions), text: 'Pending'),
            Tab(icon: Icon(Icons.check_circle), text: 'Completed'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Pending Tasks Tab
          _buildTaskList(status: 'pending'),
          // Completed Tasks Tab
          _buildTaskList(status: 'completed'),
        ],
      ),
    );
  }

  Widget _buildTaskList({required String status}) {
    if (_staffId == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return StreamBuilder<QuerySnapshot>(
      // Fetch tasks assigned to this staff member with matching status
      stream: FirebaseFirestore.instance
          .collection('tasks')
          .where('assignedTo', isEqualTo: _staffId)
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        // Show a loading indicator while waiting for data
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Show an error message if something goes wrong
        if (snapshot.hasError) {
          // Check if error is due to missing index
          if (snapshot.error.toString().contains('index')) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning, size: 48, color: Colors.orange),
                    const SizedBox(height: 16),
                    const Text(
                      'Database index needs to be created',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        // If there are no tasks, show a message
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  status == 'pending' ? Icons.inbox : Icons.check_circle_outline,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  status == 'pending' 
                    ? 'No pending tasks assigned to you'
                    : 'No completed tasks yet',
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  'Staff ID: $_staffId',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        // Once data is available, display it in a list
        final tasks = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final task = tasks[index];
            final taskData = task.data() as Map<String, dynamic>;

            String? distanceText;
            if (status == 'pending' && _staffLocation != null) {
              final gpsData = taskData['gpsData'] as Map<String, dynamic>?;
              if (gpsData != null) {
                final taskLatitude = gpsData['latitude'] as double?;
                final taskLongitude = gpsData['longitude'] as double?;

                if (taskLatitude != null && taskLongitude != null) {
                  final distance = _locationService.calculateDistance(
                    _staffLocation!.latitude,
                    _staffLocation!.longitude,
                    taskLatitude,
                    taskLongitude,
                  );
                  distanceText = '${distance.toStringAsFixed(2)} km away';
                }
              }
            }

            // Format timestamp
            String dateString = 'No Date';
            if (taskData['createdAt'] != null) {
              final timestamp = taskData['createdAt'] as Timestamp;
              final date = timestamp.toDate();
              dateString = '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
            }

            return Card(
              elevation: 3,
              margin: const EdgeInsets.symmetric(vertical: 8.0),
              child: ListTile(
                leading: status == 'completed' && taskData['completionImageUrl'] != null
                  ? GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ImageViewerPage(
                              imageUrl: taskData['completionImageUrl'] as String,
                              title: 'Completion Photo',
                              taskDetails: _prepareTaskDetails(taskData),
                              showThankYouMessage: false,
                              staffInfo: _staffId ?? 'Staff',
                              isLocalFile: false,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.green, width: 2),
                        ),
                        child: ClipOval(
                          child: Hero(
                            tag: 'completion_image_${task.id}',
                            child: Image.network(
                              taskData['completionImageUrl'] as String,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const CircleAvatar(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                child: Icon(Icons.check),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : CircleAvatar(
                      backgroundColor:
                          status == 'pending' ? Colors.orange : Colors.green,
                      foregroundColor: Colors.white,
                      child: Icon(
                        status == 'pending' ? Icons.hourglass_top : Icons.check,
                      ),
                    ),
                title: Text(
                  status == 'pending'
                    ? (taskData['aiCaption'] ?? taskData['studentCaption'] ?? 'No Caption')
                    : taskData['aiCaption'] ?? taskData['studentCaption'] ?? 'No Caption',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: status == 'pending' ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: status == 'pending'
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dateString,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          if (distanceText != null)
                            Text(
                              distanceText,
                              style: const TextStyle(fontSize: 12, color: Colors.blue),
                            ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (taskData['location'] ?? 'Unknown Location').toString(),
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            'From: ${taskData['studentName'] ?? 'Unknown'} (${taskData['registerNumber'] ?? 'N/A'})',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            dateString,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                isThreeLine: true,
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TaskDetailPage(task: task),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}