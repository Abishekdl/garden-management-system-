import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'local_notification_service.dart';
import 'notification_service.dart';

class NotificationManager {
  static final NotificationManager _instance = NotificationManager._internal();
  factory NotificationManager() => _instance;
  NotificationManager._internal();

  // Navigation callback for handling notification taps
  static Function(Map<String, dynamic>)? _navigationCallback;

  static void setNavigationCallback(Function(Map<String, dynamic>) callback) {
    _navigationCallback = callback;
  }

  // Initialize all notification services
  static Future<void> initialize() async {
    await LocalNotificationService.initialize();
    print('✅ Notification Manager initialized');
  }

  // Handle different types of notifications with enhanced system integration
  static Future<void> handleNotification({
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    NotificationPriority priority = NotificationPriority.normal,
  }) async {
    print('🎯 NotificationManager.handleNotification called');
    print('   Type: $type');
    print('   Title: $title');
    print('   Body: $body');
    print('   Data: $data');
    
    switch (type) {
      case 'task_completed':
        print('   📱 Routing to task completed handler');
        await _handleTaskCompletedNotification(title, body, data);
        break;
      case 'new_task':
        await _handleNewTaskNotification(title, body, data);
        break;
      case 'urgent':
        await _handleUrgentNotification(title, body, data);
        break;
      case 'reminder':
        await _handleReminderNotification(title, body, data);
        break;
      case 'system_update':
        await _handleSystemUpdateNotification(title, body, data);
        break;
      default:
        await _handleGeneralNotification(title, body, data);
    }
  }

  static Future<void> _handleTaskCompletedNotification(
    String title, 
    String body, 
    Map<String, dynamic>? data
  ) async {
    print('🎉 _handleTaskCompletedNotification called');
    print('   Title: $title');
    print('   Body: $body');
    print('   Data: $data');
    
    await LocalNotificationService.showTaskCompletedNotification(
      title: title,
      body: body,
      taskId: data?['taskId'] ?? '',
      imageUrl: data?['completedImageUrl'],
      staffName: data?['staffName'],
    );
  }

  static Future<void> _handleNewTaskNotification(
    String title, 
    String body, 
    Map<String, dynamic>? data
  ) async {
    await LocalNotificationService.showNewTaskNotification(
      title: title,
      body: body,
      taskId: data?['taskId'] ?? '',
      location: data?['location'],
      priority: data?['priority'],
    );
  }

  static Future<void> _handleUrgentNotification(
    String title, 
    String body, 
    Map<String, dynamic>? data
  ) async {
    await LocalNotificationService.showUrgentNotification(
      title: title,
      body: body,
      data: data,
    );
  }

  static Future<void> _handleReminderNotification(
    String title, 
    String body, 
    Map<String, dynamic>? data
  ) async {
    // For reminders, use general notification with specific styling
    await LocalNotificationService.showGeneralNotification(
      title: '⏰ $title',
      body: body,
      data: data,
    );
  }

  static Future<void> _handleSystemUpdateNotification(
    String title, 
    String body, 
    Map<String, dynamic>? data
  ) async {
    await LocalNotificationService.showGeneralNotification(
      title: '🔄 $title',
      body: body,
      data: data,
    );
  }

  static Future<void> _handleGeneralNotification(
    String title, 
    String body, 
    Map<String, dynamic>? data
  ) async {
    await LocalNotificationService.showGeneralNotification(
      title: title,
      body: body,
      data: data,
    );
  }

  // Handle FCM message routing
  static Future<void> handleFCMMessage(RemoteMessage message) async {
    print('🔔 NotificationManager.handleFCMMessage called');
    print('   Message data: ${message.data}');
    print('   Notification: ${message.notification?.title} - ${message.notification?.body}');
    
    final type = message.data['type'] ?? 'general';
    final title = message.notification?.title ?? 'Garden App';
    final body = message.notification?.body ?? 'You have a new notification';

    print('   Routing to handleNotification with type: $type');

    await handleNotification(
      type: type,
      title: title,
      body: body,
      data: message.data,
    );
  }

  // Schedule notification for later delivery
  static Future<void> scheduleNotification({
    required String type,
    required String title,
    required String body,
    required DateTime scheduledTime,
    Map<String, dynamic>? data,
  }) async {
    // This would integrate with flutter_local_notifications scheduling
    // For now, we'll implement basic scheduling logic
    final delay = scheduledTime.difference(DateTime.now());
    
    if (delay.isNegative) {
      // If scheduled time is in the past, show immediately
      await handleNotification(
        type: type,
        title: title,
        body: body,
        data: data,
      );
    } else {
      // Schedule for future delivery
      Future.delayed(delay, () async {
        await handleNotification(
          type: type,
          title: title,
          body: body,
          data: data,
        );
      });
    }
  }

  // Batch notification handling
  static Future<void> handleBatchNotifications(
    List<Map<String, dynamic>> notifications
  ) async {
    for (final notification in notifications) {
      await handleNotification(
        type: notification['type'] ?? 'general',
        title: notification['title'] ?? 'Notification',
        body: notification['body'] ?? '',
        data: notification['data'],
      );
      
      // Small delay between notifications to avoid overwhelming the user
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // Clear all notifications
  static Future<void> clearAllNotifications() async {
    await LocalNotificationService.cancelAllNotifications();
  }

  // Clear specific notification
  static Future<void> clearNotification(int id) async {
    await LocalNotificationService.cancelNotification(id);
  }

  // Get notification statistics
  static Future<Map<String, int>> getNotificationStats() async {
    final pending = await LocalNotificationService.getPendingNotifications();
    
    return {
      'pending': pending.length,
      'total_sent': 0, // This would be tracked in a real implementation
      'clicked': 0, // This would be tracked in a real implementation
    };
  }
}

enum NotificationPriority {
  low,
  normal,
  high,
  urgent,
}

// Notification appearance configuration
class NotificationAppearance {
  final String? iconPath;
  final Color? accentColor;
  final String? soundPath;
  final List<int>? vibrationPattern;
  final bool showBadge;
  final bool showLights;

  const NotificationAppearance({
    this.iconPath,
    this.accentColor,
    this.soundPath,
    this.vibrationPattern,
    this.showBadge = true,
    this.showLights = true,
  });

  // Predefined appearance configurations
  static const NotificationAppearance taskCompleted = NotificationAppearance(
    iconPath: '@mipmap/ic_launcher',
    accentColor: Colors.green,
    soundPath: 'notification_sound',
    vibrationPattern: [0, 1000, 500, 1000],
    showBadge: true,
    showLights: true,
  );

  static const NotificationAppearance newTask = NotificationAppearance(
    iconPath: '@mipmap/ic_launcher',
    accentColor: Colors.orange,
    soundPath: 'task_alert',
    vibrationPattern: [0, 500, 200, 500, 200, 500],
    showBadge: true,
    showLights: true,
  );

  static const NotificationAppearance urgent = NotificationAppearance(
    iconPath: '@mipmap/ic_launcher',
    accentColor: Colors.red,
    soundPath: 'urgent_alert',
    vibrationPattern: [0, 300, 100, 300, 100, 300, 100, 300],
    showBadge: true,
    showLights: true,
  );
}