import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Notification channels for different types
  static const String _taskCompletedChannelId = 'task_completed_channel';
  static const String _newTaskChannelId = 'new_task_channel';
  static const String _generalChannelId = 'general_channel';
  static const String _urgentChannelId = 'urgent_channel';
  static const String _defaultChannelId = 'garden_app_notifications';

  static Future<void> initialize() async {
    print('🔔 Initializing LocalNotificationService...');
    
    // Android initialization settings with custom notification icon
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/notification_icon');

    // iOS initialization settings
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    try {
      await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      print('   ✅ Flutter local notifications plugin initialized');
    } catch (e) {
      print('   ❌ Error initializing flutter local notifications: $e');
    }

    // Create notification channels for Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }

    // Request permissions for iOS
    if (Platform.isIOS) {
      await _requestIOSPermissions();
    }
  }

  static Future<void> _createNotificationChannels() async {
    // Task Completed Channel - High importance with default sound
    final AndroidNotificationChannel taskCompletedChannel =
        AndroidNotificationChannel(
      _taskCompletedChannelId,
      'Task Completed',
      description: 'Notifications when your reported tasks are completed',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
      enableLights: true,
      ledColor: const Color.fromARGB(255, 76, 175, 80), // Green color
    );

    // New Task Channel - High importance for staff
    final AndroidNotificationChannel newTaskChannel =
        AndroidNotificationChannel(
      _newTaskChannelId,
      'New Tasks',
      description: 'Notifications for new tasks assigned to staff',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
      enableLights: true,
      ledColor: const Color.fromARGB(255, 255, 152, 0), // Orange color
    );

    // General Channel - Default importance
    final AndroidNotificationChannel generalChannel =
        AndroidNotificationChannel(
      _generalChannelId,
      'General Notifications',
      description: 'General app notifications and updates',
      importance: Importance.defaultImportance,
      enableVibration: true,
      enableLights: true,
      ledColor: const Color.fromARGB(255, 33, 150, 243), // Blue color
    );

    // Urgent Channel - Max importance for critical notifications
    final AndroidNotificationChannel urgentChannel =
        AndroidNotificationChannel(
      _urgentChannelId,
      'Urgent Notifications',
      description: 'Critical and urgent notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 300, 100, 300, 100, 300, 100, 300]),
      enableLights: true,
      ledColor: const Color.fromARGB(255, 244, 67, 54), // Red color
    );

    // Create the channels
    print('📱 Creating notification channels...');
    
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(taskCompletedChannel);
    print('   ✅ Task completed channel created: $_taskCompletedChannelId');

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(newTaskChannel);
    print('   ✅ New task channel created: $_newTaskChannelId');

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(generalChannel);
    print('   ✅ General channel created: $_generalChannelId');

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(urgentChannel);
    print('   ✅ Urgent channel created: $_urgentChannelId');

    // Default channel - matches AndroidManifest.xml default_notification_channel_id
    final AndroidNotificationChannel defaultChannel =
        AndroidNotificationChannel(
      _defaultChannelId,
      'Garden App Notifications',
      description: 'Default notifications for Garden App',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: const Color.fromARGB(255, 76, 175, 80), // Green color
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(defaultChannel);
    print('   ✅ Default channel created: $_defaultChannelId');
  }

  static Future<void> _requestIOSPermissions() async {
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  // Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
    
    if (response.payload != null) {
      try {
        final data = json.decode(response.payload!);
        // Handle navigation based on notification type
        _handleNotificationNavigation(data);
      } catch (e) {
        print('Error parsing notification payload: $e');
      }
    }
  }

  static void _handleNotificationNavigation(Map<String, dynamic> data) {
    // This will be handled by the main app's navigation system
    // For now, we'll store the navigation data for the app to pick up
    print('Navigation data: $data');
  }

  // Show task completed notification
  static Future<void> showTaskCompletedNotification({
    required String title,
    required String body,
    required String taskId,
    String? imageUrl,
    String? staffName,
  }) async {
    print('🎉 showTaskCompletedNotification called');
    print('   Title: $title');
    print('   Body: $body');
    print('   TaskId: $taskId');
    print('   ImageUrl: $imageUrl');
    print('   StaffName: $staffName');
    
    final payload = json.encode({
      'type': 'task_completed',
      'taskId': taskId,
      'imageUrl': imageUrl,
      'staffName': staffName,
    });

    // Create Android notification details with custom garden icon
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _taskCompletedChannelId,
      'Task Completed',
      channelDescription: 'Notifications when your reported tasks are completed',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/notification_icon',
      styleInformation: BigTextStyleInformation(
        body,
        summaryText: imageUrl != null && imageUrl.isNotEmpty 
            ? 'Tap to view completion photo' 
            : 'Task completed by $staffName',
      ),
      // Removed action buttons temporarily to avoid drawable issues
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'notification_sound.aiff',
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    print('   📱 About to show task completed notification with ID: $notificationId');
    print('   📱 Using channel: $_taskCompletedChannelId');
    
    try {
      await _notificationsPlugin.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
      print('   ✅ Task completed notification shown successfully');
    } catch (e) {
      print('   ❌ Error showing task completed notification: $e');
    }
  }

  // Show new task notification for staff
  static Future<void> showNewTaskNotification({
    required String title,
    required String body,
    required String taskId,
    String? location,
    String? priority,
  }) async {
    final payload = json.encode({
      'type': 'new_task',
      'taskId': taskId,
      'location': location,
      'priority': priority,
    });

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _newTaskChannelId,
      'New Tasks',
      channelDescription: 'Notifications for new tasks assigned to staff',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/notification_icon',
      styleInformation: BigTextStyleInformation(
        body,
        summaryText: location != null ? 'Location: $location' : null,
      ),
      // Removed action buttons temporarily to avoid drawable issues
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'task_alert.aiff',
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  // Show general notification
  static Future<void> showGeneralNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final payload = json.encode({
      'type': 'general',
      'data': data ?? {},
    });

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _generalChannelId,
      'General Notifications',
      channelDescription: 'General app notifications and updates',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@drawable/notification_icon',
      styleInformation: DefaultStyleInformation(true, true),
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  // Show urgent notification
  static Future<void> showUrgentNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final payload = json.encode({
      'type': 'urgent',
      'data': data ?? {},
    });

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _urgentChannelId,
      'Urgent Notifications',
      channelDescription: 'Critical and urgent notifications',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@drawable/notification_icon',
      largeIcon: const DrawableResourceAndroidBitmap('@drawable/notification_icon'),
      styleInformation: BigTextStyleInformation(
        body,
        summaryText: '⚠️ URGENT - Immediate attention required',
      ),
      fullScreenIntent: true, // Shows as heads-up notification
      category: AndroidNotificationCategory.alarm,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'urgent_alert.aiff',
      interruptionLevel: InterruptionLevel.critical,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  // Handle FCM message and show appropriate local notification
  static Future<void> handleFCMMessage(RemoteMessage message) async {
    print('🔔 LocalNotificationService.handleFCMMessage called');
    print('   Message data: ${message.data}');
    print('   Notification title: ${message.notification?.title}');
    print('   Notification body: ${message.notification?.body}');
    
    final notificationType = message.data['type'] ?? 'general';
    final title = message.notification?.title ?? 'Garden App';
    final body = message.notification?.body ?? 'You have a new notification';

    print('   Notification type: $notificationType');

    switch (notificationType) {
      case 'task_completed':
        print('   📱 Showing task completed notification');
        await showTaskCompletedNotification(
          title: title,
          body: body,
          taskId: message.data['taskId'] ?? '',
          imageUrl: message.data['completedImageUrl'],
          staffName: message.data['staffName'],
        );
        break;
      case 'new_task':
        await showNewTaskNotification(
          title: title,
          body: body,
          taskId: message.data['taskId'] ?? '',
          location: message.data['location'],
          priority: message.data['priority'],
        );
        break;
      case 'urgent':
        await showUrgentNotification(
          title: title,
          body: body,
          data: message.data,
        );
        break;
      default:
        await showGeneralNotification(
          title: title,
          body: body,
          data: message.data,
        );
    }
  }

  // Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }

  // Cancel specific notification
  static Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  // Get pending notifications
  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notificationsPlugin.pendingNotificationRequests();
  }
}