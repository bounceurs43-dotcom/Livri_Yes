import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateLandingPage extends StatelessWidget {
  const UpdateLandingPage({super.key});

  Future<void> _openPlayStore() async {
    final url = Uri.parse('https://play.google.com/store/apps/details?id=com.livriyes.Livriyes');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.system_update_rounded, size: 60, color: Colors.red),
              ),
              const SizedBox(height: 32),
              const Text(
                'Mise à jour requise',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1C1C1E),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Votre version de LivriYes est obsolète.\nPour continuer à utiliser nos services et découvrir nos nouveaux produits, veuillez télécharger la dernière version.',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF8E8E93),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openPlayStore,
                  icon: const Icon(Icons.shop, size: 24),
                  label: const Text(
                    'Mettre à jour depuis Play Store',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF34C759),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
