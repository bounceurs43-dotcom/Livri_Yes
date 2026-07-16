import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../firebase_options.dart';
import 'notification_service.dart';

const String backgroundTaskName = "com.salimstore.client.backgroundTask";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Ensure Firebase is initialized
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      // Initialize local notifications only
      await NotificationService.initializeLocalNotificationsOnly();

      // Check current user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return Future.value(true);
      }

      // Fetch user's active orders from database
      final DatabaseReference ref = FirebaseDatabase.instance.ref('orders');
      final event = await ref.once();
      if (!event.snapshot.exists) {
        return Future.value(true);
      }

      final prefs = await SharedPreferences.getInstance();
      
      // Load last known order statuses from SharedPreferences
      final String? cachedStatusesRaw = prefs.getString('cached_order_statuses');
      final Map<String, String> cachedStatuses = cachedStatusesRaw != null
          ? Map<String, String>.from(jsonDecode(cachedStatusesRaw))
          : {};

      final value = event.snapshot.value;
      final Map<String, String> newStatuses = {};

      void processOrder(dynamic id, dynamic orderData) {
        if (orderData != null && orderData is Map) {
          final orderMap = Map<String, dynamic>.from(orderData);
          if (orderMap['userId'] == user.uid) {
            final String orderId = (orderMap['orderId'] ?? id).toString();
            final String status = (orderMap['status'] ?? 'pending').toString();
            newStatuses[orderId] = status;

            final oldStatus = cachedStatuses[orderId];
            if (oldStatus != null && oldStatus != status) {
              // Trigger notification for status change
              NotificationService.notifyStatusChange(orderId, status);
            } else if (oldStatus == null) {
              // Order is new, notify as confirmed
              NotificationService.notifyStatusChange(orderId, status, isNew: true);
            }
          }
        }
      }

      if (value is Map) {
        value.forEach((id, orderData) {
          processOrder(id, orderData);
        });
      } else if (value is List) {
        for (int i = 0; i < value.length; i++) {
          processOrder(i, value[i]);
        }
      }

      // Update SharedPreferences cache
      await prefs.setString('cached_order_statuses', jsonEncode(newStatuses));
      return Future.value(true);
    } catch (e) {
      print('Error in background task: $e');
      return Future.value(false);
    }
  });
}

class BackgroundService {
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  static Future<void> registerBackgroundTask() async {
    // Registers a periodic background task that runs every 15 minutes (minimum allowed by iOS/Android)
    await Workmanager().registerPeriodicTask(
      "1",
      backgroundTaskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }
}
