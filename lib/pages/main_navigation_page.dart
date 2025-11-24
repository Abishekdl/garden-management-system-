import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'camera_page.dart';
import 'history_page.dart';
import 'profile_page.dart';
import 'role_selection_page.dart';
import '../widgets/custom_bottom_navigation.dart';

class MainNavigationPage extends StatefulWidget {
  final String userName;
  final String registerNumber;

  const MainNavigationPage({
    super.key,
    required this.userName,
    required this.registerNumber,
  });

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Get the list of pages
  List<Widget> get _pages => [
    const CameraPage(), // Index 0: Camera
    HistoryPage( // Index 1: History
      name: widget.userName,
      registerNumber: widget.registerNumber,
    ),
    ProfilePage( // Index 2: Profile
      userName: widget.userName,
      registerNumber: widget.registerNumber,
    ),
  ];

  void _onTabTapped(int index) {
    if (index == 3) {
      // Handle logout (index 3)
      _showLogoutDialog();
    } else {
      // Navigate to the selected page
      setState(() {
        _currentIndex = index;
      });
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      
      // Refresh profile page when switching to it
      if (index == 2) {
        // Small delay to ensure page is loaded
        Future.delayed(const Duration(milliseconds: 500), () {
          // Trigger profile refresh by calling setState on the profile page
          // This will be handled by the lifecycle observer
        });
      }
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.logout, color: Colors.red),
              SizedBox(width: 8),
              Text('Logout'),
            ],
          ),
          content: const Text(
            'Are you sure you want to logout?\n\nThis will clear your session and return you to the login page.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _performLogout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performLogout() async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
    );

    try {
      // Only clear user session data, preserve app data
      final prefs = await SharedPreferences.getInstance();
      
      // Preserve important app data
      final uploadHistory = prefs.getStringList('upload_history');
      final notifications = prefs.getStringList('notifications');
      final deviceId = prefs.getString('device_id');
      final profileImagePath = prefs.getString('profile_image_path');
      
      // Clear all data
      await prefs.clear();
      
      // Restore preserved app data
      if (uploadHistory != null) {
        await prefs.setStringList('upload_history', uploadHistory);
      }
      if (notifications != null) {
        await prefs.setStringList('notifications', notifications);
      }
      if (deviceId != null) {
        await prefs.setString('device_id', deviceId);
      }
      if (profileImagePath != null) {
        await prefs.setString('profile_image_path', profileImagePath);
      }

      // Small delay for better UX
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        // Close loading dialog and navigate to login
        Navigator.of(context).pop(); // Close loading dialog
        
        // Navigate to role selection page and clear navigation stack
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const RoleSelectionPage()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        
        // Show error dialog
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Logout Error'),
              content: Text('Failed to logout: $e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: _pages,
      ),
      bottomNavigationBar: CustomBottomNavigation(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        items: const [
          BottomNavigationItem(
            icon: Icons.camera_alt,
            label: 'Camera',
          ),
          BottomNavigationItem(
            icon: Icons.history,
            label: 'History',
          ),
          BottomNavigationItem(
            icon: Icons.person,
            label: 'Profile',
          ),
        ],
      ),
    );
  }


}