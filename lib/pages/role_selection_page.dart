import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart'; // Your existing student login page
import 'staff_login_page.dart'; // The staff login page we will create next
import 'server_connection_page.dart';
import '../utils/server_config.dart';

class RoleSelectionPage extends StatefulWidget {
  const RoleSelectionPage({super.key});

  @override
  State<RoleSelectionPage> createState() => _RoleSelectionPageState();
}

class _RoleSelectionPageState extends State<RoleSelectionPage> {
  String _currentServerUrl = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentServerUrl();
  }

  Future<void> _loadCurrentServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('server_url') ?? ServerConfig.baseUrl;
    setState(() {
      _currentServerUrl = serverUrl;
    });
  }

  void _changeServer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ServerConnectionPage(),
      ),
    ).then((_) {
      // Refresh the server URL when returning from server connection page
      _loadCurrentServerUrl();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green[50], // Lighter green background
      body: SafeArea(
        // Ensures content is not under system bars
        child: Column(
          children: [
            // Top Green Leaf Section - More compact
            Container(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              width: double.infinity,
              color: Colors.green, // Darker green for the top section
              child: Column(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.eco, size: 40, color: Colors.green),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Choose Your Role',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select your role to get started with Campus Green Watch',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ],
              ),
            ),

            // Role Selection Cards - Made scrollable to prevent overflow
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    // Student Card
                    _buildRoleCard(
                      context: context,
                      icon: Icons.school,
                      iconColor: Colors.blueAccent,
                      title: 'Student',
                      subtitle: 'Report issues and view personal history',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LoginPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // Worker Card
                    _buildRoleCard(
                      context: context,
                      icon: Icons.engineering,
                      iconColor: Colors.orange,
                      title: 'Worker',
                      subtitle:
                          'View assigned tasks and capture completion proof',
                      onTap: () {
                        // This will navigate to the staff login page we are creating
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const StaffLoginPage(),
                          ),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Server Info Card - Compact design
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.cloud, color: Colors.green[600], size: 18),
                                const SizedBox(width: 6),
                                const Text(
                                  'Connected Server:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.green[200]!),
                              ),
                              child: Text(
                                _currentServerUrl.isNotEmpty ? _currentServerUrl : 'No server configured',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green[700],
                                  fontFamily: 'monospace',
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _changeServer,
                                icon: const Icon(Icons.settings, size: 16),
                                label: const Text('Change Server', style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.green[600],
                                  side: BorderSide(color: Colors.green[300]!),
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Add some bottom padding for better scrolling experience
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        // Use InkWell for tap feedback
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
            child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 26, color: iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
