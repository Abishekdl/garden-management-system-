import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'firebase_options.dart';
import 'pages/splash_page.dart';
import 'pages/notification_detail_page.dart'; // Import the detail page
import 'utils/server_config.dart';
import 'services/notification_service.dart';
import 'services/local_notification_service.dart';
import 'services/notification_manager.dart';

// ## NEW: Function to handle background notifications ##
// This function must be a top-level function (outside of any class)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("🔔 Handling a background message: ${message.messageId}");
  
  // Initialize local notifications for background handling
  await LocalNotificationService.initialize();
  
  // Show system notification
  await LocalNotificationService.handleFCMMessage(message);
  
  // Handle the background notification storage
  await NotificationService.handleBackgroundNotification(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize notification system
  await NotificationManager.initialize();
  
  // Set the background messaging handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Auto-configure server connectivity
  print('🚀 Starting server auto-configuration...');
  await ServerConfig.autoConfigureServer();

  // Process any pending FCM token updates
  final notificationService = NotificationService();
  await notificationService.processPendingTokenUpdates();
  
  // Ensure FCM token is fresh on app startup
  await NotificationService.ensureFreshFCMToken();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _setupFirebaseMessaging();
    _processPendingNotifications();
    _setupNotificationNavigation();
  }
  
  // Initialize notification system for the app
  Future<void> _initializeNotifications() async {
    try {
      await LocalNotificationService.initialize();
      print('✅ Local notification service initialized in main app');
    } catch (e) {
      print('❌ Error initializing local notification service: $e');
    }
  }
  
  void _setupNotificationNavigation() {
    NotificationManager.setNavigationCallback((data) {
      _handleNotificationNavigation(data, null);
    });
  }

  // Enhanced Firebase Messaging setup with proper notification handling
  void _setupFirebaseMessaging() {
    // Request notification permissions
    _requestNotificationPermissions();
    
    // 1. Handles messages that arrive when the app is in the foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Received foreground notification!');
      print('Title: ${message.notification?.title}');
      print('Body: ${message.notification?.body}');
      print('Data: ${message.data}');

      if (message.notification != null) {
        // Show system notification even when app is in foreground
        NotificationManager.handleFCMMessage(message);
        
        // Also show in-app notification banner
        _showInAppNotification(message);
      }
    });

    // 2. Handles the user tapping on a notification when the app is terminated or in the background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('User tapped on notification!');
      _handleNotificationNavigation(message.data, message.notification);
    });
    
    // 3. Check if app was opened from a terminated state via notification
    _checkForInitialMessage();
  }
  
  // Request notification permissions (required for iOS)
  Future<void> _requestNotificationPermissions() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    
    print('Notification permission granted: ${settings.authorizationStatus}');
  }
  
  // Check if app was opened from terminated state via notification
  Future<void> _checkForInitialMessage() async {
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    
    if (initialMessage != null) {
      print('App opened from terminated state via notification');
      _handleNotificationNavigation(initialMessage.data, initialMessage.notification);
    }
  }
  
  // Show in-app notification banner
  void _showInAppNotification(RemoteMessage message) {
    if (navigatorKey.currentContext != null) {
      ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.notification!.title ?? 'Notification',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(message.notification!.body ?? ''),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () {
              _handleNotificationNavigation(message.data, message.notification);
            },
          ),
        ),
      );
    }
  }
  
  // Enhanced notification navigation handling
  void _handleNotificationNavigation(Map<String, dynamic> data, RemoteNotification? notification) {
    print('Navigating based on notification data: $data');
    
    // Delay navigation to ensure the app is fully loaded
    Future.delayed(const Duration(milliseconds: 500), () {
      if (navigatorKey.currentState != null) {
        // Check notification type and navigate accordingly
        String? notificationType = data['type'];
        
        switch (notificationType) {
          case 'task_completed':
            _handleTaskCompletedNotification(data, notification);
            break;
          case 'new_task':
            _handleNewTaskNotification(data, notification);
            break;
          default:
            _handleGeneralNotification(data, notification);
        }
      }
    });
  }
  
  // Handle task completion notification (for students)
  void _handleTaskCompletedNotification(Map<String, dynamic> data, RemoteNotification? notification) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => NotificationDetailPage(
          notification: {
            'id': data['taskId'] ?? 'unknown',
            'title': notification?.title ?? 'Task Completed!',
            'message': notification?.body ?? 'Your reported issue has been resolved.',
            'imageUrl': data['completedImageUrl'],
            'timestamp': DateTime.now().toIso8601String(),
            'sender': 'Garden Staff',
            'read': true,
            'type': 'task_completed',
          },
        ),
      ),
    );
  }
  
  // Handle new task notification (for staff)
  void _handleNewTaskNotification(Map<String, dynamic> data, RemoteNotification? notification) {
    // For now, just show a general notification
    // In the future, this could navigate directly to the staff dashboard
    _handleGeneralNotification(data, notification);
  }
  
  // Handle general notifications
  void _handleGeneralNotification(Map<String, dynamic> data, RemoteNotification? notification) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => NotificationDetailPage(
          notification: {
            'id': data['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
            'title': notification?.title ?? 'Notification',
            'message': notification?.body ?? 'You have a new notification.',
            'timestamp': DateTime.now().toIso8601String(),
            'sender': 'Garden App',
            'read': true,
            'type': 'general',
          },
        ),
      ),
    );
  }
  
  // Process notifications that arrived while app was closed
  Future<void> _processPendingNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notifications = prefs.getStringList('pending_notifications') ?? [];
      
      if (notifications.isNotEmpty) {
        print('📱 Processing ${notifications.length} pending notifications');
        
        // Clear the pending notifications
        await prefs.remove('pending_notifications');
        
        // Show the most recent notification if any
        if (notifications.isNotEmpty) {
          final latestNotification = json.decode(notifications.last);
          
          // Delay to ensure app is fully loaded
          Future.delayed(const Duration(seconds: 2), () {
            if (navigatorKey.currentContext != null) {
              ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
                SnackBar(
                  content: Text('You have ${notifications.length} new notification(s)'),
                  backgroundColor: Colors.blue,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          });
        }
      }
    } catch (e) {
      print('Error processing pending notifications: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Add the navigatorKey here
      navigatorKey: navigatorKey,
      title: 'Garden App',
      debugShowCheckedModeBanner: false, // Remove debug banner
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const SplashPage(),
    );
  }
}
