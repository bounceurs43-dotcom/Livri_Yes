import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

class UpdateEmailDialog extends StatefulWidget {
  const UpdateEmailDialog({super.key});

  @override
  State<UpdateEmailDialog> createState() => _UpdateEmailDialogState();
}

class _UpdateEmailDialogState extends State<UpdateEmailDialog> {
  bool _loading = true;
  bool _sending = false;
  List<Map<String, String>> _users = [];
  Set<String> _selectedEmails = {};
  String _searchQuery = '';
  String _emailTemplate = 'announcement'; // 'announcement' or 'update'
  String _playStoreUrl = 'https://play.google.com/store/apps/details?id=com.livriyes.Livriyes';

  String _announcementSubject = "Mise à jour importante de l'application Livriyes";
  String _announcementBody = "Afin de vous offrir une expérience toujours meilleure, nous réalisons actuellement une importante mise à jour de l'application Livriyes.\n\nCette évolution est le fruit de vos retours d'expérience et de vos précieux conseils recueillis au cours des 10 premiers jours suivant notre lancement.\n\nCette mise à jour devrait durer au maximum 4 à 5 jours. Nous mettons tout en œuvre pour qu'elle soit déployée dans les meilleurs délais.\n\nNous vous remercions sincèrement pour votre confiance et votre participation à l'amélioration de Livriyes.\n\nNotre équipe reste à votre écoute pour toute question ou suggestion :";

  String _updateSubject = "Action requise : Mettez à jour votre application Livriyes";
  String _updateBody = "Votre application LivriYes nécessite une mise à jour importante pour continuer à fonctionner correctement et afficher les nouveaux produits.\n\nVeuillez cliquer sur le bouton ci-dessous pour mettre à jour l'application :";

  List<Map<String, String>> get _filteredUsers {
    if (_searchQuery.isEmpty) return _users;
    final query = _searchQuery.toLowerCase();
    return _users.where((user) {
      final name = user['name']!.toLowerCase();
      final email = user['email']!.toLowerCase();
      return name.contains(query) || email.contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final configSnap = await FirebaseDatabase.instance.ref('settings/appVersion/playStoreUrl').get();
      if (configSnap.exists) {
        _playStoreUrl = configSnap.value?.toString() ?? _playStoreUrl;
      }

      final snap = await FirebaseDatabase.instance.ref('users').get();
      final List<Map<String, String>> loadedUsers = [];
      if (snap.exists) {
        final data = snap.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          if (value == null) return;
          final user = value as Map<dynamic, dynamic>;
          final email = user['email']?.toString() ?? '';
          final name = user['name']?.toString() ?? 'Utilisateur';
          if (email.isNotEmpty && email.contains('@')) {
            loadedUsers.add({'email': email, 'name': name});
          }
        });
      }
      if (mounted) {
        setState(() {
          _users = loadedUsers;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading users: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendEmails() async {
    if (_selectedEmails.isEmpty) return;
    setState(() => _sending = true);
    int successCount = 0;
    
    String subject;
    String htmlContent;
     if (_emailTemplate == 'announcement') {
      subject = _announcementSubject;
      final formattedBody = _announcementBody.replaceAll('\n', '<br>');
      htmlContent = '''
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #ffffff; box-shadow: 0 4px 6px rgba(0,0,0,0.05);">
          <div style="text-align: center; margin-bottom: 20px;">
            <h2 style="color: #34C759; margin: 0; font-size: 24px;">Livriyes</h2>
            <p style="color: #6b7280; font-size: 14px; margin-top: 5px;">Mise à jour de l'application</p>
          </div>
          <div style="line-height: 1.6; color: #374151; font-size: 15px;">
            <p>Bonjour,</p>
            <p>$formattedBody</p>
            <ul style="padding-left: 20px; color: #4b5563;">
              <li><strong>E-mail :</strong> support@livriyes.app</li>
              <li><strong>Téléphone :</strong> +213 778 02 99 65</li>
            </ul>
            <p style="margin-top: 25px;">À très bientôt,</p>
            <p><strong>L'équipe Livriyes</strong></p>
          </div>
          <div style="border-top: 1px solid #f3f4f6; margin-top: 30px; padding-top: 15px; text-align: center; font-size: 12px; color: #9ca3af;">
            <p style="margin: 0;">Cet e-mail automatique a été envoyé à [email] car vous êtes inscrit sur l'application LivriYes.</p>
            <p style="margin: 5px 0 0 0;">LivriYes, Béjaïa, Algérie • <a href="mailto:support@livriyes.app" style="color: #34C759; text-decoration: none;">support@livriyes.app</a></p>
          </div>
        </div>
      ''';
    } else {
      subject = _updateSubject;
      final formattedBody = _updateBody.replaceAll('\n', '<br>');
      htmlContent = '''
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #ffffff; box-shadow: 0 4px 6px rgba(0,0,0,0.05);">
          <div style="text-align: center; margin-bottom: 20px;">
            <h2 style="color: #FF3B30; margin: 0; font-size: 24px;">⚠️ Mise à jour requise</h2>
          </div>
          <div style="line-height: 1.6; color: #374151; font-size: 15px; text-align: center;">
            <p>Bonjour,</p>
            <p>$formattedBody</p>
            <div style="margin: 25px 0;">
              <a href="$_playStoreUrl" style="display: inline-block; padding: 14px 28px; background-color: #34C759; color: white; text-decoration: none; border-radius: 8px; font-weight: bold; font-size: 16px; box-shadow: 0 4px 6px rgba(52,199,89,0.2);">Mettre à jour maintenant</a>
            </div>
            <p style="font-size: 12px; color: #6b7280; margin-top: 30px;">Si le bouton ne fonctionne pas, copiez ce lien :<br><a href="$_playStoreUrl" style="color: #34C759;">$_playStoreUrl</a></p>
          </div>
          <div style="border-top: 1px solid #f3f4f6; margin-top: 30px; padding-top: 15px; text-align: center; font-size: 12px; color: #9ca3af;">
            <p style="margin: 0;">Cet e-mail automatique a été envoyé à [email] car vous êtes inscrit sur l'application LivriYes.</p>
            <p style="margin: 5px 0 0 0;">LivriYes, Béjaïa, Algérie • <a href="mailto:support@livriyes.app" style="color: #34C759; text-decoration: none;">support@livriyes.app</a></p>
          </div>
        </div>
      ''';
    }

    for (final email in _selectedEmails) {
      try {
        final success = await NotificationService.sendEmailNotification(
          email: email,
          subject: subject,
          htmlContent: htmlContent.replaceAll('[email]', email),
        );
        if (success) successCount++;
      } catch (e) {
        debugPrint('Error sending to $email: $e');
      }
    }

    if (mounted) {
      setState(() => _sending = false);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$successCount emails envoyés avec succès ! ✅')),
      );
    }
  }

  void _openEditTemplateModal() {
    final isAnn = _emailTemplate == 'announcement';
    final subjectCtrl = TextEditingController(text: isAnn ? _announcementSubject : _updateSubject);
    final bodyCtrl = TextEditingController(text: isAnn ? _announcementBody : _updateBody);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isAnn ? 'Modifier le modèle : Annonce' : 'Modifier le modèle : Mise à jour'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: subjectCtrl,
                  decoration: const InputDecoration(
                    labelText: "Sujet de l'email",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyCtrl,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: "Corps du message",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  if (isAnn) {
                    _announcementSubject = subjectCtrl.text.trim();
                    _announcementBody = bodyCtrl.text.trim();
                  } else {
                    _updateSubject = subjectCtrl.text.trim();
                    _updateBody = bodyCtrl.text.trim();
                  }
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Modèle d\'email mis à jour pour cette session ✅')),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
              child: const Text('Valider'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Envoyer une alerte de mise à jour'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _users.isEmpty
                ? const Center(child: Text('Aucun utilisateur avec email trouvé.'))
                : Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${_selectedEmails.length} sélectionnés sur ${_filteredUsers.length}'),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                if (_selectedEmails.length == _filteredUsers.length) {
                                  // Deselect all currently filtered users
                                  _selectedEmails.removeAll(_filteredUsers.map((e) => e['email']!));
                                } else {
                                  // Select all currently filtered users
                                  _selectedEmails.addAll(_filteredUsers.map((e) => e['email']!));
                                }
                              });
                            },
                            child: Text(_selectedEmails.length == _filteredUsers.length && _filteredUsers.isNotEmpty ? 'Désélectionner tout' : 'Sélectionner tout'),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _emailTemplate,
                              decoration: InputDecoration(
                                labelText: "Type d'email / Alerte",
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'announcement',
                                  child: Text('Mise à jour en cours (Annonce)'),
                                ),
                                DropdownMenuItem(
                                  value: 'update',
                                  child: Text('Nouvelle version disponible (Mise à jour)'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _emailTemplate = val;
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _openEditTemplateModal,
                            icon: const Icon(Icons.edit, color: AppTheme.primaryColor),
                            tooltip: 'Modifier ce modèle',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Rechercher un utilisateur ou un email...',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                        ),
                      ),
                      const Divider(),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _filteredUsers.length,
                          itemBuilder: (context, index) {
                            final user = _filteredUsers[index];
                            final email = user['email']!;
                            final name = user['name']!;
                            final isSelected = _selectedEmails.contains(email);
                            return CheckboxListTile(
                              title: Text(name),
                              subtitle: Text(email),
                              value: isSelected,
                              onChanged: (bool? val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedEmails.add(email);
                                  } else {
                                    _selectedEmails.remove(email);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton.icon(
          onPressed: _sending || _selectedEmails.isEmpty ? null : _sendEmails,
          icon: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
          label: Text(_sending ? 'Envoi...' : 'Envoyer (${_selectedEmails.length})'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
        ),
      ],
    );
  }
}
