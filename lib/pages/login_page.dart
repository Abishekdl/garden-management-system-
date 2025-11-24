import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main_navigation_page.dart';
import '../services/notification_service.dart';
import '../services/location_service.dart';
import '../utils/server_config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _registerNumberController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _registerNumberController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final name = _nameController.text.trim();
    final registerNumber = _registerNumberController.text.trim();
    
    if (name.isEmpty || registerNumber.isEmpty) {
      _showErrorDialog('Please enter both name and register number');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Authenticate with server
      final response = await _authenticateStudent(name, registerNumber);
      
      if (!response['success']) {
        setState(() {
          _isLoading = false;
        });
        _showErrorDialog(response['error'] ?? 'Login failed');
        return;
      }
      
      print('✅ Student login: $name ($registerNumber)');

      // ## FIXED: Called the correct method for students ##
      await NotificationService().initializeForStudent();
      
      // Force refresh FCM token immediately after login to ensure it's valid
      try {
        print('🔄 Force refreshing FCM token after student login...');
        await NotificationService.forceRefreshStudentToken();
        print('✅ FCM token refreshed after login');
      } catch (e) {
        print('⚠️ Error refreshing FCM token after login: $e');
      }

      // ## NEW: Initialize LocationService after login ##
      final locationService = LocationService();
      await locationService.initialize();

      // Start sending location updates to the server
      locationService.startSendingLocationUpdates(
        userType: 'student',
        userId: registerNumber.toUpperCase(),
      );

      if (!mounted) return; // Check if the widget is still in the tree

      // Save user data for profile page
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', name);
      await prefs.setString('register_number', registerNumber);

      // Navigate to main navigation page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MainNavigationPage(
            userName: name,
            registerNumber: registerNumber,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorDialog('Login failed: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> _authenticateStudent(String name, String registerNumber) async {
    try {
      final response = await http.post(
        Uri.parse('${ServerConfig.baseUrl}/auth/student/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'registerNumber': registerNumber,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else if (response.statusCode == 403) {
        // Cross-login prevented
        return {'success': false, 'error': data['error']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Authentication failed'};
      }
    } catch (e) {
      print('Authentication error: $e');
      return {'success': false, 'error': 'Network error. Please check your connection.'};
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 
                       MediaQuery.of(context).padding.top - 
                       MediaQuery.of(context).padding.bottom - 48, // Account for SafeArea
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Icon(
                Icons.eco,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Garden App',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Please enter your details to continue.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Enter your full name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _registerNumberController,
                decoration: const InputDecoration(
                  labelText: 'Register Number',
                  hintText: 'Enter your register number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Signing in...'),
                        ],
                      )
                    : const Text(
                        'Continue to Profile',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  // ## FIXED: Replaced deprecated withOpacity ##
                  color: Colors.green.withAlpha(26), // 0.1 opacity
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withAlpha(77)), // 0.3 opacity
                ),
                child: const Column(
                  children: [
                    Text(
                      'Garden Monitoring',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Capture photos and videos of garden areas for monitoring',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
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