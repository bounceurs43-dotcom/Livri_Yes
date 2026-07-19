import 'package:flutter/material.dart';
import '../services/realtime_database_service.dart';

class DeliveryPricesDialog {
  static void show(BuildContext context) async {
    final prices = await RealtimeDatabaseService.getDeliveryPrices();
    final bejaiaController = TextEditingController(
      text: (prices['bejaiaCityFee'] ?? 3.49).toString(),
    );
    final otherController = TextEditingController(
      text: (prices['otherWilayaFee'] ?? 8.99).toString(),
    );
    final bejaiaElectroController = TextEditingController(
      text: (prices['bejaiaElectroFee'] ?? 14.99).toString(),
    );
    final otherElectroController = TextEditingController(
      text: (prices['otherWilayaElectroFee'] ?? 24.99).toString(),
    );

    if (!context.mounted) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'DeliveryPrices',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) =>
          const SizedBox.shrink(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return Transform.translate(
          offset: Offset(0, 100 * (1 - animation.value)),
          child: Opacity(
            opacity: animation.value,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.local_shipping_rounded, color: Colors.red),
                  SizedBox(width: 10),
                  Text('Prix de livraison'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Livraison Standard :',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: bejaiaController,
                      decoration: const InputDecoration(
                        labelText: 'Prix Béjaïa',
                        suffixText: 'DA',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: otherController,
                      decoration: const InputDecoration(
                        labelText: 'Prix Hors Béjaïa',
                        suffixText: 'DA',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Livraison Électroménager :',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepOrange),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: bejaiaElectroController,
                      decoration: const InputDecoration(
                        labelText: 'Prix Béjaïa Électroménager',
                        suffixText: 'DA',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: otherElectroController,
                      decoration: const InputDecoration(
                        labelText: 'Prix Hors Béjaïa Électroménager',
                        suffixText: 'DA',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
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
                  onPressed: () async {
                    final bejaiaFee = double.tryParse(bejaiaController.text);
                    final otherFee = double.tryParse(otherController.text);
                    final bejaiaElectroFee = double.tryParse(bejaiaElectroController.text) ?? 14.99;
                    final otherElectroFee = double.tryParse(otherElectroController.text) ?? 24.99;

                    if (bejaiaFee != null && otherFee != null) {
                      await RealtimeDatabaseService.updateDeliveryPrices(
                        bejaiaFee,
                        otherFee,
                        bejaiaElectroFee: bejaiaElectroFee,
                        otherWilayaElectroFee: otherElectroFee,
                      );
                      if (context.mounted) Navigator.pop(context);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✓ Prix mis à jour avec succès !'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Enregistrer les modifications'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
