import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/force_update_screen.dart';

class AppVersionService {
  static Future<void> checkVersion(BuildContext context) async {
    try {
      final snap = await FirebaseDatabase.instance.ref('settings/appVersion').get();
      if (!snap.exists) return;
      final val = snap.value as Map<dynamic, dynamic>;
      
      final minBuildNumber = int.tryParse(val['minBuildNumber']?.toString() ?? '0') ?? 0;
      final latestBuildNumber = int.tryParse(val['latestBuildNumber']?.toString() ?? '0') ?? 0;
      final playStoreUrl = val['playStoreUrl']?.toString() ?? '';

      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      if (!context.mounted) return;

      if (currentBuildNumber < minBuildNumber) {
        forceShowUpdateDialog(context, playStoreUrl);
      } else if (currentBuildNumber < latestBuildNumber) {
        _showUpdateDialog(context, false, playStoreUrl);
      }
    } catch (e) {
      print('Version check error: $e');
    }
  }

  static void forceShowUpdateDialog(BuildContext context, [String url = '']) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => ForceUpdateScreen(playStoreUrl: url),
      ),
      (route) => false,
    );
  }

  static void listenForForceUpdate(BuildContext context) {
    FirebaseDatabase.instance.ref('settings/forceUpdatePopup').onValue.listen((event) {
      if (event.snapshot.value == true && context.mounted) {
        forceShowUpdateDialog(context);
      }
    });
  }

  static void _showUpdateDialog(BuildContext context, bool isForced, String url) {
    showDialog(
      context: context,
      barrierDismissible: !isForced,
      builder: (context) {
        return PopScope(
          canPop: !isForced,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.system_update_rounded, color: isForced ? Colors.red : Colors.blue),
                const SizedBox(width: 10),
                const Text('Mise à jour disponible'),
              ],
            ),
            content: Text(
              isForced 
                  ? 'Une mise à jour est nécessaire pour continuer.' 
                  : 'Veuillez mettre à jour l\'application pour profiter de toutes ces nouvelles fonctionnalités.',
              style: const TextStyle(fontSize: 15),
            ),
            actions: [
              if (!isForced)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Plus tard', style: TextStyle(color: Colors.grey)),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isForced ? Colors.red : Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text('Mettre à jour'),
              ),
            ],
          ),
        );
      },
    );
  }
}
