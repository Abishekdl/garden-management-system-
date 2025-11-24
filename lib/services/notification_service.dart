import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/server_config.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // --- For Students ---
  Future<void> initializeForStudent() async {
    print('🔔 Initializing FCM for student...');
    
    // Request permissions with all necessary settings for background notifications
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    
    print('Notification permission status: ${settings.authorizationStatus}');
    
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ Student notification permissions granted');
    } else {
      print('⚠️ Student notification permissions not fully granted: ${settings.authorizationStatus}');
    }
    
    // Force refresh token to ensure it's valid
    await _refreshAndUpdateStudentToken();

    // CRITICAL: Listen for token refreshes and update server immediately
    _firebaseMessaging.onTokenRefresh.listen((newToken) async {
      print('🔄 FCM Token refreshed for student: $newToken');
      await _saveStudentTokenToFirestore(newToken);
      await _sendTokenToServer(newToken, 'student');
    });
    
    print('✅ Student FCM initialization complete');
  }

  // Force refresh FCM token for student
  Future<void> _refreshAndUpdateStudentToken() async {
    try {
      // Delete the current token to force refresh
      await _firebaseMessaging.deleteToken();
      print('🗑️ Old FCM token deleted for student');
      
      // Wait a moment for the deletion to process
      await Future.delayed(const Duration(seconds: 2));
      
      // Get a fresh token
      final String? newToken = await _firebaseMessaging.getToken();
      print('🆕 Fresh FCM Token (Student): ${newToken?.substring(0, 20)}...');

      if (newToken != null) {
        await _saveStudentTokenToFirestore(newToken);
        await _sendTokenToServer(newToken, 'student');
        print('✅ Fresh FCM token registered successfully for student');
      } else {
        print('❌ Failed to get fresh FCM token for student');
      }
    } catch (e) {
      print('❌ Error refreshing FCM token for student: $e');
      // Fallback to getting current token
      final String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        await _saveStudentTokenToFirestore(token);
        await _sendTokenToServer(token, 'student');
      }
    }
  }

  // Process any pending token updates
  Future<void> processPendingTokenUpdates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingToken = prefs.getString('pending_fcm_token');
      final pendingUserType = prefs.getString('pending_fcm_user_type');
      final pendingUserId = prefs.getString('pending_fcm_user_id');
      
      if (pendingToken != null && pendingUserType != null) {
        print('📋 Processing pending FCM token update...');
        await _sendTokenToServer(pendingToken, pendingUserType, pendingUserId);
        
        // Clear pending data after successful update
        await prefs.remove('pending_fcm_token');
        await prefs.remove('pending_fcm_user_type');
        await prefs.remove('pending_fcm_user_id');
      }
    } catch (e) {
      print('❌ Error processing pending token updates: $e');
    }
  }

  Future<void> _saveStudentTokenToFirestore(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final studentId = prefs.getString('register_number');
    if (studentId == null || studentId.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('students').doc(studentId).set({
        'fcmToken': token,
        'lastUpdated': FieldValue.serverTimestamp(),
        'tokenRefreshedAt': DateTime.now().toIso8601String(),
        'appVersion': '1.0.0',
        'deviceType': 'mobile',
      }, SetOptions(merge: true));
      
      print('✅ Student FCM token saved to Firestore: $studentId');
    } catch (e) {
      print('❌ Error saving student FCM token to Firestore: $e');
    }
  }

  // ## --- NEW: For Staff --- ##
  Future<void> initializeForStaff(String staffId) async {
    print('🔔 Initializing FCM for staff: $staffId');
    
    // Request permissions with all necessary settings for background notifications
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    
    print('Notification permission status: ${settings.authorizationStatus}');
    
    // Force refresh token to ensure it's valid
    await _refreshAndUpdateStaffToken(staffId);

    // CRITICAL: Listen for token refreshes and update server immediately
    _firebaseMessaging.onTokenRefresh.listen((newToken) async {
      print('🔄 FCM Token refreshed for staff $staffId: $newToken');
      await _saveStaffTokenToFirestore(newToken, staffId);
      await _sendTokenToServer(newToken, 'staff', staffId);
    });
  }

  // Force refresh FCM token for staff
  Future<void> _refreshAndUpdateStaffToken(String staffId) async {
    try {
      // Delete the current token to force refresh
      await _firebaseMessaging.deleteToken();
      print('🗑️ Old FCM token deleted for staff');
      
      // Get a fresh token
      final String? newToken = await _firebaseMessaging.getToken();
      print('🆕 Fresh FCM Token (Staff $staffId): ${newToken?.substring(0, 20)}...');

      if (newToken != null) {
        await _saveStaffTokenToFirestore(newToken, staffId);
        await _sendTokenToServer(newToken, 'staff', staffId);
        print('✅ Fresh FCM token registered successfully for staff');
      } else {
        print('❌ Failed to get fresh FCM token for staff');
      }
    } catch (e) {
      print('❌ Error refreshing FCM token for staff: $e');
      // Fallback to getting current token
      final String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        await _saveStaffTokenToFirestore(token, staffId);
        await _sendTokenToServer(token, 'staff', staffId);
      }
    }
  }

  Future<void> _saveStaffTokenToFirestore(String token, String staffId) async {
    if (staffId.isEmpty) return;
    
    try {
      // Save token to a new 'staff' collection
      await FirebaseFirestore.instance.collection('staff').doc(staffId).set({
        'fcmToken': token,
        'lastUpdated': FieldValue.serverTimestamp(),
        'tokenRefreshedAt': DateTime.now().toIso8601String(),
        'appVersion': '1.0.0',
        'deviceType': 'mobile',
      }, SetOptions(merge: true));
      
      print('✅ Staff FCM token saved to Firestore: $staffId');
    } catch (e) {
      print('❌ Error saving staff FCM token to Firestore: $e');
    }
  }

  // Send FCM token to server for registration/update
  Future<void> _sendTokenToServer(String token, String userType, [String? userId]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final registerNumber = prefs.getString('register_number');
      final staffId = userId ?? prefs.getString('staff_id');
      final actualUserId = userType == 'student' ? registerNumber : staffId;
      
      if (actualUserId == null || actualUserId.isEmpty) {
        print('⚠️ No user ID found for $userType, skipping server update');
        return;
      }
      
      print('📤 Sending FCM token to server for $userType: $actualUserId');
      
      final response = await http.post(
        Uri.parse('${ServerConfig.baseUrl}/update_fcm_token'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'token': token,
          'userType': userType,
          'userId': actualUserId,
          'timestamp': DateTime.now().toIso8601String(),
          'tokenLength': token.length,
          'deviceInfo': 'Flutter App',
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('✅ FCM token updated on server for $userType: $actualUserId');
        print('   Server response: ${responseData['message']}');
      } else {
        print('⚠️ Failed to update FCM token on server: ${response.statusCode}');
        print('   Response: ${response.body}');
        
        // Retry once after a short delay
        await Future.delayed(const Duration(seconds: 2));
        await _retryTokenUpdate(token, userType, actualUserId);
      }
    } catch (e) {
      print('❌ Error sending FCM token to server: $e');
      
      // Store token locally for retry later
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_fcm_token', token);
      await prefs.setString('pending_fcm_user_type', userType);
      if (userId != null) {
        await prefs.setString('pending_fcm_user_id', userId);
      }
    }
  }

  // Retry token update with exponential backoff
  Future<void> _retryTokenUpdate(String token, String userType, String userId) async {
    try {
      print('🔄 Retrying FCM token update for $userType: $userId');
      
      final response = await http.post(
        Uri.parse('${ServerConfig.baseUrl}/update_fcm_token'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'token': token,
          'userType': userType,
          'userId': userId,
          'timestamp': DateTime.now().toIso8601String(),
          'retry': true,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        print('✅ FCM token retry successful for $userType: $userId');
      } else {
        print('❌ FCM token retry failed: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ FCM token retry error: $e');
    }
  }

  // Static method to handle background notifications
  static Future<void> handleBackgroundNotification(RemoteMessage message) async {
    print('🔔 Background notification received: ${message.messageId}');
    print('Title: ${message.notification?.title}');
    print('Body: ${message.notification?.body}');
    print('Data: ${message.data}');
    
    // Store notification in local storage for when app opens
    final prefs = await SharedPreferences.getInstance();
    final notifications = prefs.getStringList('pending_notifications') ?? [];
    
    final notificationData = {
      'id': message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'title': message.notification?.title ?? 'Notification',
      'body': message.notification?.body ?? '',
      'data': message.data,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    notifications.add(json.encode(notificationData));
    await prefs.setStringList('pending_notifications', notifications);
    
    print('✅ Background notification stored for later processing');
  }

  // Manual token refresh for troubleshooting
  static Future<void> refreshFCMToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      
      // Delete current token
      await messaging.deleteToken();
      print('🗑️ Current FCM token deleted');
      
      // Get fresh token
      final String? newToken = await messaging.getToken();
      print('🆕 New FCM Token: ${newToken?.substring(0, 20)}...');
      
      if (newToken != null) {
        // Update both student and staff tokens based on current user
        final prefs = await SharedPreferences.getInstance();
        final registerNumber = prefs.getString('register_number');
        final staffId = prefs.getString('staff_id');
        
        final notificationService = NotificationService();
        
        if (registerNumber != null) {
          await notificationService._saveStudentTokenToFirestore(newToken);
          await notificationService._sendTokenToServer(newToken, 'student');
          print('✅ Student FCM token refreshed');
        }
        
        if (staffId != null) {
          await notificationService._saveStaffTokenToFirestore(newToken, staffId);
          await notificationService._sendTokenToServer(newToken, 'staff', staffId);
          print('✅ Staff FCM token refreshed');
        }
      }
    } catch (e) {
      print('❌ Error manually refreshing FCM token: $e');
    }
  }

  // Automatic token refresh without deleting current token (gentler approach)
  static Future<void> ensureFreshFCMToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final prefs = await SharedPreferences.getInstance();
      
      // Get current token
      final String? currentToken = await messaging.getToken();
      print('🔍 Current FCM Token: ${currentToken?.substring(0, 20)}...');
      
      if (currentToken != null) {
        // Update tokens based on current user
        final registerNumber = prefs.getString('register_number');
        final staffId = prefs.getString('staff_id');
        
        final notificationService = NotificationService();
        
        if (registerNumber != null) {
          await notificationService._saveStudentTokenToFirestore(currentToken);
          await notificationService._sendTokenToServer(currentToken, 'student');
          print('✅ Student FCM token ensured fresh');
        }
        
        if (staffId != null) {
          await notificationService._saveStaffTokenToFirestore(currentToken, staffId);
          await notificationService._sendTokenToServer(currentToken, 'staff', staffId);
          print('✅ Staff FCM token ensured fresh');
        }
      }
    } catch (e) {
      print('❌ Error ensuring fresh FCM token: $e');
      // If gentle refresh fails, try force refresh
      await refreshFCMToken();
    }
  }

  // Force refresh FCM token when validation fails
  static Future<void> forceRefreshFCMToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final prefs = await SharedPreferences.getInstance();
      
      print('🔄 Force refreshing FCM token due to validation failure...');
      
      // Delete current invalid token
      await messaging.deleteToken();
      print('🗑️ Invalid FCM token deleted');
      
      // Wait a moment for the deletion to process
      await Future.delayed(const Duration(seconds: 3));
      
      // Get fresh token
      final String? newToken = await messaging.getToken();
      print('🆕 New FCM Token: ${newToken?.substring(0, 20)}...');
      
      if (newToken != null) {
        // Update tokens based on current user
        final registerNumber = prefs.getString('register_number');
        final staffId = prefs.getString('staff_id');
        
        final notificationService = NotificationService();
        
        if (registerNumber != null) {
          await notificationService._saveStudentTokenToFirestore(newToken);
          await notificationService._sendTokenToServer(newToken, 'student');
          print('✅ Student FCM token force refreshed');
        }
        
        if (staffId != null) {
          await notificationService._saveStaffTokenToFirestore(newToken, staffId);
          await notificationService._sendTokenToServer(newToken, 'staff', staffId);
          print('✅ Staff FCM token force refreshed');
        }
      }
    } catch (e) {
      print('❌ Error force refreshing FCM token: $e');
    }
  }

  // Dedicated student token refresh method (matches staff pattern)
  static Future<void> forceRefreshStudentToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final prefs = await SharedPreferences.getInstance();
      final registerNumber = prefs.getString('register_number');
      
      if (registerNumber == null) {
        print('❌ No student register number found');
        return;
      }
      
      print('🔄 Force refreshing FCM token for student $registerNumber...');
      
      // Delete current invalid token
      await messaging.deleteToken();
      print('🗑️ Invalid FCM token deleted for student');
      
      // Wait for deletion to process
      await Future.delayed(const Duration(seconds: 3));
      
      // Get fresh token
      final String? newToken = await messaging.getToken();
      print('🆕 New FCM Token for student: ${newToken?.substring(0, 20)}...');
      
      if (newToken != null) {
        final notificationService = NotificationService();
        await notificationService._saveStudentTokenToFirestore(newToken);
        await notificationService._sendTokenToServer(newToken, 'student');
        print('✅ Student FCM token force refreshed successfully');
      } else {
        print('❌ Failed to get new FCM token for student');
      }
    } catch (e) {
      print('❌ Error force refreshing student FCM token: $e');
    }
  }

  // Test notification for students
  static Future<void> sendTestNotificationToStudent(String studentId) async {
    try {
      final response = await http.post(
        Uri.parse('${ServerConfig.baseUrl}/test_student_notification'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'studentId': studentId,
          'title': 'Test Notification',
          'body': 'This is a test notification to verify your notifications are working!',
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('✅ Test notification sent to student: $studentId');
      } else {
        print('⚠️ Failed to send test notification: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error sending test notification: $e');
    }
  }

  static Future<void> sendThankYouNotification({
    required String studentId,
    required String taskId,
    required String staffId,
  }) async {
    // Note: The server already sends the notification with image URL when completing the task
    // via the /complete_task endpoint, so no additional API call is needed here.
    print('Thank you notification will be sent by server when task is completed');
    print('Student: $studentId, Task: $taskId, Staff: $staffId');
  }

  Future<void> sendNotificationToStudent(
    String studentId,
    String title,
    String body,
    Map<String, String> data,
  ) async {
    try {
      final studentDoc = await FirebaseFirestore.instance.collection('students').doc(studentId).get();
      final studentToken = studentDoc.data()?['fcmToken'];

      if (studentToken != null) {
        final response = await http.post(
          Uri.parse('${ServerConfig.SERVER_URL}/send_notification'),
          headers: <String, String>{
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: jsonEncode(<String, dynamic>{
            'token': studentToken,
            'title': title,
            'body': body,
            'data': data,
          }),
        );

        if (response.statusCode == 200) {
          print('Notification sent to student $studentId successfully');
        } else {
          print('Failed to send notification to student $studentId: ${response.body}');
        }
      } else {
        print('No FCM token found for student $studentId');
      }
    } catch (e) {
      print('Error sending notification to student $studentId: $e');
    }
  }
}