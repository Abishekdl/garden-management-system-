import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'server_connection_page.dart';
import 'role_selection_page.dart';
import '../utils/server_config.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  String _statusMessage = 'Loading...';

  @override
  void initState() {
    super.initState();
    _checkStoredUrl();
  }

  Future<void> _checkStoredUrl() async {
    // Minimal delay for smooth UX transition
    await Future.delayed(const Duration(milliseconds: 200));

    setState(() {
      _statusMessage = 'Checking server configuration...';
    });

    // Check if server URL has been saved previously
    final prefs = await SharedPreferences.getInstance();
    final savedServerUrl = prefs.getString('server_url');
    
    if (mounted) {
      if (savedServerUrl != null && savedServerUrl.isNotEmpty) {
        // Server URL exists, set it in ServerConfig and go directly to role selection
        ServerConfig.setBaseUrl(savedServerUrl);
        print('✅ Using saved server URL: $savedServerUrl');
        
        setState(() {
          _statusMessage = 'Loading app...';
        });
        
        // Skip server test for faster startup - trust the saved URL
        // Server connectivity will be tested when actually needed
        await Future.delayed(const Duration(milliseconds: 300));
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const RoleSelectionPage(),
          ),
        );
      } else {
        // No server URL saved, go to server connection page
        print('ℹ️ No server URL saved, redirecting to server connection page');
        setState(() {
          _statusMessage = 'Setting up server connection...';
        });
        
        await Future.delayed(const Duration(milliseconds: 500));
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const ServerConnectionPage(),
          ),
        );
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.eco,
              size: 100,
              color: Colors.white,
            ),
            const SizedBox(height: 24),
            const Text(
              'Garden App',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              _statusMessage,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}