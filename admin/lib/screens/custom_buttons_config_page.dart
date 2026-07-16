import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme/app_theme.dart';

class CustomButtonsConfigPage extends StatefulWidget {
  const CustomButtonsConfigPage({super.key});

  @override
  State<CustomButtonsConfigPage> createState() => _CustomButtonsConfigPageState();
}

class _CustomButtonsConfigPageState extends State<CustomButtonsConfigPage> {
  final List<Map<String, String>> _buttons = [];
  bool _loading = true;

  // Controllers for adding a new button
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _contentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseDatabase.instance.ref('settings').child('customButtons').get();
      _buttons.clear();
      if (snap.exists) {
        final val = snap.value;
        if (val is List) {
          for (final item in val) {
            if (item is Map) {
              _buttons.add({
                'title': item['title']?.toString() ?? '',
                'description': item['description']?.toString() ?? '',
                'linkOrContent': item['linkOrContent']?.toString() ?? '',
              });
            }
          }
        } else if (val is Map) {
          val.forEach((k, v) {
            if (v is Map) {
              _buttons.add({
                'title': v['title']?.toString() ?? '',
                'description': v['description']?.toString() ?? '',
                'linkOrContent': v['linkOrContent']?.toString() ?? '',
              });
            }
          });
        }
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      print('Error loading custom buttons: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      await FirebaseDatabase.instance.ref('settings').child('customButtons').set(_buttons);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Boutons dynamiques enregistrés avec succès ! ✅')),
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

  void _addButton() {
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final content = _contentCtrl.text.trim();

    if (title.isEmpty || desc.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez remplir tous les champs pour le nouveau bouton.')),
      );
      return;
    }

    setState(() {
      _buttons.add({
        'title': title,
        'description': desc,
        'linkOrContent': content,
      });
      _titleCtrl.clear();
      _descCtrl.clear();
      _contentCtrl.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bouton ajouté à la liste. N\'oubliez pas d\'enregistrer !')),
    );
  }

  void _deleteButton(int index) {
    setState(() {
      _buttons.removeAt(index);
    });
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
                            Icon(Icons.link_rounded, color: Colors.white, size: 28),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Boutons & Documents',
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
                  'Gestion des Liens & CGU',
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
                          // Introduction Banner
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
                              'Configurez ici les liens ou documents textuels qui apparaîtront dynamiquement dans l\'onglet profil du client. Si vous mettez un lien web (ex: https://...), il s\'ouvrira dans un navigateur. Sinon, le texte brut s\'affichera dans un dialogue sécurisé.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                                height: 1.4,
                              ),
                            ),
                          ).animate().fadeIn(duration: 350.ms),
                          const SizedBox(height: 20),

                          // Dynamic list of buttons
                          Text(
                            'Boutons Actuels (${_buttons.length})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 10),

                          if (_buttons.isEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 30),
                              child: const Center(
                                child: Text(
                                  'Aucun bouton configuré. Le client affichera les "Conditions d\'utilisation" par défaut.',
                                  style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _buttons.length,
                              itemBuilder: (context, index) {
                                final btn = _buttons[index];
                                final isLink = btn['linkOrContent']!.startsWith('http');
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                    border: Border.all(
                                      color: Colors.grey.withOpacity(0.15),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: isLink
                                              ? Colors.blue.withOpacity(0.1)
                                              : Colors.purple.withOpacity(0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isLink ? Icons.open_in_browser : Icons.description_outlined,
                                          color: isLink ? Colors.blue : Colors.purple,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              btn['title']!,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              btn['description']!,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              isLink ? 'Lien : ${btn['linkOrContent']}' : 'Contenu textuel',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isLink ? Colors.blue : Colors.purple,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                                        onPressed: () => _deleteButton(index),
                                      ),
                                    ],
                                  ),
                                ).animate().slideY(begin: 0.1, duration: 250.ms);
                              },
                            ),

                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),

                          // Add a button form
                          const Text(
                            'Ajouter un nouveau bouton',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),
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
                                  controller: _titleCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Titre du bouton (ex: Conditions Générales)',
                                    prefixIcon: Icon(Icons.title_rounded),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _descCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Description (ex: Consulter nos CGU)',
                                    prefixIcon: Icon(Icons.description_outlined),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _contentCtrl,
                                  minLines: 3,
                                  maxLines: 6,
                                  decoration: const InputDecoration(
                                    labelText: 'Lien Web (https://...) OU Contenu textuel complet',
                                    prefixIcon: Icon(Icons.link_rounded),
                                    alignLabelWithHint: true,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: _addButton,
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Ajouter ce bouton à la liste'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _save,
                              icon: const Icon(Icons.save),
                              label: const Text('Enregistrer et publier les modifications'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
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
