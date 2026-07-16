import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme/app_theme.dart';
import 'update_email_dialog.dart';

class AppVersionConfigPage extends StatefulWidget {
  const AppVersionConfigPage({super.key});

  @override
  State<AppVersionConfigPage> createState() => _AppVersionConfigPageState();
}

class _AppVersionConfigPageState extends State<AppVersionConfigPage> {
  bool _loading = true;

  final TextEditingController _minVersionCtrl = TextEditingController();
  final TextEditingController _latestVersionCtrl = TextEditingController();
  final TextEditingController _playStoreUrlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _minVersionCtrl.dispose();
    _latestVersionCtrl.dispose();
    _playStoreUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseDatabase.instance.ref('settings/appVersion').get();
      if (snap.exists) {
        final val = snap.value as Map<dynamic, dynamic>;
        _minVersionCtrl.text = val['minBuildNumber']?.toString() ?? '';
        _latestVersionCtrl.text = val['latestBuildNumber']?.toString() ?? '';
        _playStoreUrlCtrl.text = val['playStoreUrl']?.toString() ?? '';
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      print('Error loading app version config: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      await FirebaseDatabase.instance.ref('settings/appVersion').set({
        'minBuildNumber': int.tryParse(_minVersionCtrl.text.trim()) ?? 0,
        'latestBuildNumber': int.tryParse(_latestVersionCtrl.text.trim()) ?? 0,
        'playStoreUrl': _playStoreUrlCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration enregistrée avec succès ! ✅')),
      );
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur d\'enregistrement : $e')),
      );
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 160,
              backgroundColor: AppTheme.primaryColor,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -50,
                        top: -30,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                        child: Row(
                          children: const [
                            Icon(Icons.system_update_rounded, color: Colors.white, size: 28),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Version de l\'application',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                title: const Text(
                  'Force Update Config',
                  style: TextStyle(color: Colors.white),
                ),
                centerTitle: false,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: AppTheme.primaryColor.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: const Text(
                              'Configurez ici les versions minimales et récentes de votre application. Utilisez le "Build Number" (ex: 13, 14, 15). Si le client a une version inférieure à la version minimale, il sera forcé de mettre à jour. Si elle est inférieure à la version récente, une mise à jour lui sera recommandée.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                                height: 1.4,
                              ),
                            ),
                          ).animate().fadeIn(duration: 350.ms),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _minVersionCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Version minimale requise (Build Number, ex: 13)',
                                    prefixIcon: Icon(Icons.warning_rounded, color: Colors.redAccent),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _latestVersionCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Dernière version (Build Number, ex: 14)',
                                    prefixIcon: Icon(Icons.info_outline_rounded, color: Colors.blueAccent),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _playStoreUrlCtrl,
                                  keyboardType: TextInputType.url,
                                  decoration: const InputDecoration(
                                    labelText: 'Lien Play Store',
                                    prefixIcon: Icon(Icons.shop_rounded, color: Colors.green),
                                  ),
                                ),
                              ],
                            ),
                          ).animate().slideY(begin: 0.1, duration: 250.ms),
                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _save,
                              icon: const Icon(Icons.save),
                              label: const Text('Enregistrer et appliquer'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => const UpdateEmailDialog(),
                                );
                              },
                              icon: const Icon(Icons.email),
                              label: const Text('Envoyer un email de mise à jour aux utilisateurs'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                backgroundColor: Colors.amber.shade700,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
