import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'staff_main_navigation_page.dart';
import '../services/notification_service.dart';
import '../services/location_service.dart';
import '../utils/server_config.dart';

class StaffLoginPage extends StatefulWidget {
  const StaffLoginPage({super.key});

  @override
  State<StaffLoginPage> createState() => _StaffLoginPageState();
}

class _StaffLoginPageState extends State<StaffLoginPage> {
  final TextEditingController _staffIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _staffIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final staffId = _staffIdController.text.trim();
    final password = _passwordController.text.trim();

    if (staffId.isEmpty || password.isEmpty) {
      _showErrorSnackBar('Please enter both Staff ID and Password');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Authenticate with server
      final response = await _authenticateStaff(staffId, password);
      
      if (!response['success']) {
        setState(() {
          _isLoading = false;
        });
        _showErrorSnackBar(response['error'] ?? 'Login failed');
        return;
      }
      
      final staffData = response['data']['staff'];
      final staffName = staffData['name'] ?? 'Staff User';
      
      print('✅ Staff login: $staffId');

      // Save staff ID to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('staff_id', staffId);
      await prefs.setString('staff_name', staffName);
      
      // Initialize notification service for this staff member
      try {
        await NotificationService().initializeForStaff(staffId);
      } catch (e) {
        print('Error initializing notification service: $e');
        // Continue even if notification service fails
      }

      // ## NEW: Initialize LocationService after login ##
      final locationService = LocationService();
      await locationService.initialize();

      // Start sending location updates to the server
      locationService.startSendingLocationUpdates(
        userType: 'staff',
        userId: staffId,
      );
      
      // Check if the widget is still in the tree before navigating
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => StaffMainNavigationPage(
            staffId: staffId,
            userName: staffName,
          )),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Login failed: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> _authenticateStaff(String staffId, String password) async {
    try {
      final response = await http.post(
        Uri.parse('${ServerConfig.baseUrl}/auth/staff/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'staffId': staffId,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else if (response.statusCode == 403) {
        // Cross-login prevented or account deactivated
        return {'success': false, 'error': data['error']};
      } else if (response.statusCode == 404) {
        // Account not found
        return {'success': false, 'error': data['error']};
      } else if (response.statusCode == 401) {
        // Invalid password
        return {'success': false, 'error': data['error']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Authentication failed'};
      }
    } catch (e) {
      print('Authentication error: $e');
      return {'success': false, 'error': 'Network error. Please check your connection.'};
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Staff Login'),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 
                       MediaQuery.of(context).padding.top - 
                       MediaQuery.of(context).padding.bottom - 
                       kToolbarHeight - 48, // Account for SafeArea and AppBar
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              const Icon(Icons.engineering, size: 80, color: Colors.blueGrey),
              const SizedBox(height: 16),
              const Text(
                'Staff Portal',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Please enter your credentials to continue.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _staffIdController,
                decoration: const InputDecoration(
                  labelText: 'Staff ID',
                  hintText: 'Enter your staff ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  hintText: 'Enter your password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blueGrey,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Login', style: TextStyle(fontSize: 16)),
              ),
            ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}