import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'role_selection_page.dart';
import '../utils/server_config.dart'; // Import the ServerConfig class

class ServerConnectionPage extends StatefulWidget {
  const ServerConnectionPage({super.key});

  @override
  State<ServerConnectionPage> createState() => _ServerConnectionPageState();
}

class _ServerConnectionPageState extends State<ServerConnectionPage> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Clear old login data and load the last used server URL
    _clearLoginData();
    _loadLastServerUrl();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
  
  // ✅ New function to load and set the last successful URL
  Future<void> _loadLastServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('server_url');
    if (savedUrl != null) {
      setState(() {
        _urlController.text = savedUrl;
      });
      // Also set it in the global config for immediate use
      ServerConfig.setBaseUrl(savedUrl);
    }
  }

  Future<void> _clearLoginData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('has_logged_in');
    await prefs.remove('user_name');
    await prefs.remove('register_number');
  }

  Future<void> _sendDataToServer(String url) async {
    if (url.trim().isEmpty) {
      _showErrorDialog('Please enter a server URL');
      return;
    }

    print('🔗 Attempting to connect to server: $url');
    
    setState(() {
      _isLoading = true;
    });

    try {
      String cleanUrl = url.trim();
      if (cleanUrl.endsWith('/')) {
        cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
      }

      print('🌐 Testing connection to: $cleanUrl/health');
      
      final response = await http.get(
        Uri.parse('$cleanUrl/health'),
      ).timeout(const Duration(seconds: 15));
      
      print('📡 Server response: ${response.statusCode}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Save the URL for next time AND set it for the current session
        await _saveServerUrl(cleanUrl);
        ServerConfig.setBaseUrl(cleanUrl);
        
        print('✅ Server connection successful: $cleanUrl');

        if (mounted) {
          // Show success message and navigate immediately
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Server connected! Redirecting...'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ),
          );
          
          // Navigate immediately after showing success message
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              // Check if we can pop back (came from role selection page)
              if (Navigator.canPop(context)) {
                print('🔙 Returning to role selection page');
                Navigator.pop(context);
              } else {
                print('🚀 First time setup - navigating to role selection');
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RoleSelectionPage(),
                  ),
                );
              }
            }
          });
        }
      } else {
        print('❌ Server error: ${response.statusCode}');
        _showErrorDialog('Server responded with an error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Connection failed: $e');
      _showErrorDialog('Failed to connect to the server. Please check the URL and your network connection.\n\nError: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Connection Error'),
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



  // This function fills in the default server URL
  void _useGardenServer() {
    // Use the configured server URL from ServerConfig
    setState(() {
      _urlController.text = ServerConfig.baseUrl;
    });
    print('🌱 Using default Garden Server URL: ${ServerConfig.baseUrl}');
  }

  Future<void> _saveServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Connection'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Show back button if we can pop (came from role selection page)
        automaticallyImplyLeading: Navigator.canPop(context),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter Server URL',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://192.168.0.102:5000',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () => _sendDataToServer(_urlController.text),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                        SizedBox(width: 12),
                        Text('Connecting...'),
                      ],
                    )
                  : const Text('Connect to Server', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 16),
            // ✅ UPDATED this button to be disabled during loading
            OutlinedButton(
              onPressed: _isLoading ? null : _useGardenServer,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Use Garden Server (Test URL)', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 24),
            // ✅ UPDATED the descriptive text to be more helpful
            const Text(
              'Enter the local IP address of the machine running the server, or use the temporary VS Code Tunnel URL.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}