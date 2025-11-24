import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'staff_dashboard_page.dart';
import 'staff_profile_page.dart';
import 'role_selection_page.dart';
import '../widgets/custom_bottom_navigation.dart';

class StaffMainNavigationPage extends StatefulWidget {
  final String staffId;
  final String userName;

  const StaffMainNavigationPage({
    super.key,
    required this.staffId,
    required this.userName,
  });

  @override
  State<StaffMainNavigationPage> createState() => _StaffMainNavigationPageState();
}

class _StaffMainNavigationPageState extends State<StaffMainNavigationPage> {
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
    const StaffDashboardPage(), // Index 0: Dashboard
    StaffProfilePage(
      staffId: widget.staffId,
      userName: widget.userName,
    ), // Index 1: Profile
  ];

  void _onTabTapped(int index) {
    if (index == 2) {
      // Handle logout (index 2)
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
            'Are you sure you want to logout?\n\nThis will end your staff session and return you to the role selection page.',
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
        // Close loading dialog and navigate to role selection
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
            icon: Icons.dashboard,
            label: 'Dashboard',
            color: Colors.blueGrey,
          ),
          BottomNavigationItem(
            icon: Icons.person,
            label: 'Profile',
            color: Colors.blueGrey,
          ),
        ],
      ),
    );
  }


}