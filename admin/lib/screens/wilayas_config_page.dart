import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme/app_theme.dart';

class WilayasConfigPage extends StatefulWidget {
  const WilayasConfigPage({super.key});

  @override
  State<WilayasConfigPage> createState() => _WilayasConfigPageState();
}

class _WilayasConfigPageState extends State<WilayasConfigPage> {
  bool _loading = false;
  List<String> _allowedWilayas = [];

  final Map<String, String> _allWilayas = {
    '01': 'Adrar',
    '02': 'Chlef',
    '03': 'Laghouat',
    '04': 'Oum El Bouaghi',
    '05': 'Batna',
    '06': 'Béjaïa',
    '07': 'Biskra',
    '08': 'Béchar',
    '09': 'Blida',
    '10': 'Bouira',
    '11': 'Tamanrasset',
    '12': 'Tébessa',
    '13': 'Tlemcen',
    '14': 'Tiaret',
    '15': 'Tizi Ouzou',
    '16': 'Alger',
    '17': 'Djelfa',
    '18': 'Jijel',
    '19': 'Sétif',
    '20': 'Saïda',
    '21': 'Skikda',
    '22': 'Sidi Bel Abbès',
    '23': 'Annaba',
    '24': 'Guelma',
    '25': 'Constantine',
    '26': 'Médéa',
    '27': 'Mostaganem',
    '28': 'M\'Sila',
    '29': 'Mascara',
    '30': 'Ouargla',
    '31': 'Oran',
    '32': 'El Bayadh',
    '33': 'Illizi',
    '34': 'Bordj Bou Arreridj',
    '35': 'Boumerdès',
    '36': 'El Tarf',
    '37': 'Tindouf',
    '38': 'Tissemsilt',
    '39': 'El Oued',
    '40': 'Khenchela',
    '41': 'Souk Ahras',
    '42': 'Tipaza',
    '43': 'Mila',
    '44': 'Aïn Defla',
    '45': 'Naâma',
    '46': 'Aïn Témouchent',
    '47': 'Ghardaïa',
    '48': 'Relizane',
    '49': 'Timimoun',
    '50': 'Bordj Badji Mokhtar',
    '51': 'Ouled Djellal',
    '52': 'Béni Abbès',
    '53': 'In Salah',
    '54': 'In Guezzam',
    '55': 'Touggourt',
    '56': 'Djanet',
    '57': 'El M\'Ghair',
    '58': 'El Meniaa'
  };

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() => _loading = true);
    try {
      final DatabaseReference ref = FirebaseDatabase.instance.ref().child('settings/allowedWilayas');
      final snapshot = await ref.get();

      if (snapshot.exists) {
        if (snapshot.value is List) {
          final list = snapshot.value as List;
          _allowedWilayas = list.whereType<String>().toList();
        } else if (snapshot.value is Map) {
          // In case it's saved as a map with indices or keys
          final map = snapshot.value as Map;
          _allowedWilayas = map.values.whereType<String>().toList();
        }
      } else {
        // Fallback default wilayas if none exist yet
        _allowedWilayas = ['06', '15', '18', '19', '34'];
      }
    } catch (e) {
      debugPrint('Error loading allowed wilayas: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _loading = true);
    try {
      final DatabaseReference ref = FirebaseDatabase.instance.ref().child('settings/allowedWilayas');
      await ref.set(_allowedWilayas);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuration enregistrée avec succès.'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wilayas de livraison'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Sélectionnez les wilayas où la livraison est disponible. Cochez les wilayas autorisées.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _allWilayas.length,
                    itemBuilder: (context, index) {
                      final code = _allWilayas.keys.elementAt(index);
                      final name = _allWilayas.values.elementAt(index);
                      final isAllowed = _allowedWilayas.contains(code);

                      return CheckboxListTile(
                        title: Text('$code - $name'),
                        value: isAllowed,
                        activeColor: AppTheme.primaryColor,
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              if (!_allowedWilayas.contains(code)) {
                                _allowedWilayas.add(code);
                              }
                            } else {
                              _allowedWilayas.remove(code);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saveConfig,
                      icon: const Icon(Icons.save),
                      label: const Text('Enregistrer la configuration'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
