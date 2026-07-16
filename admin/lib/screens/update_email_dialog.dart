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
    
    final htmlContent = '''
      <div style="font-family: sans-serif; text-align: center; padding: 20px;">
        <h2 style="color: #FF3B30;">⚠️ Mise à jour requise</h2>
        <p>Bonjour,</p>
        <p>Votre application LivriYes nécessite une mise à jour importante pour continuer à fonctionner correctement et afficher les nouveaux produits.</p>
        <p>Veuillez cliquer sur le bouton ci-dessous pour mettre à jour l'application :</p>
        <a href="https://livriyes-seven.vercel.app/#/update" style="display: inline-block; padding: 12px 24px; background-color: #34C759; color: white; text-decoration: none; border-radius: 8px; font-weight: bold; margin-top: 20px;">Mettre à jour maintenant</a>
        <p style="margin-top: 30px; font-size: 12px; color: #888;">Si le bouton ne fonctionne pas, copiez ce lien : https://livriyes-seven.vercel.app/#/update</p>
      </div>
    ''';

    for (final email in _selectedEmails) {
      try {
        final success = await NotificationService.sendEmailNotification(
          email: email,
          subject: 'Action requise : Mettez à jour votre application LivriYes',
          htmlContent: htmlContent,
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
