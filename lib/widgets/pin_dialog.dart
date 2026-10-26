import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/kids_pin_service.dart';
import '../theme/app_theme.dart';

Future<String?> _askPin(
  BuildContext context, {
  required String title,
  required String message,
  String? error,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, letterSpacing: 16),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(counterText: '', errorText: error),
            onSubmitted: (v) {
              if (v.length == 4) Navigator.pop(ctx, v);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annulla'),
        ),
        ElevatedButton(
          onPressed: () {
            if (controller.text.length == 4) {
              Navigator.pop(ctx, controller.text);
            }
          },
          child: const Text('Conferma'),
        ),
      ],
    ),
  );
}

/// Asks for the kids PIN. Returns true only after the stored PIN matches.
/// A missing PIN never authorizes the action: the parent must create one
/// and then enter it.
Future<bool> verifyKidsPin(BuildContext context) async {
  var pin = await KidsPinService.get();
  if (pin == null) {
    if (!context.mounted) return false;
    final created = await ensureKidsPin(context);
    if (!created || !context.mounted) return false;
    pin = await KidsPinService.get();
    if (pin == null) return false;
  }
  String? error;
  for (var i = 0; i < 5; i++) {
    if (!context.mounted) return false;
    final v = await _askPin(
      context,
      title: 'Inserisci il PIN',
      message: 'Serve il PIN a 4 cifre per uscire dal profilo bambini.',
      error: error,
    );
    if (v == null) return false;
    if (v == pin) return true;
    error = 'PIN errato';
  }
  return false;
}

/// Makes sure a PIN exists before a kids profile is saved.
Future<bool> ensureKidsPin(BuildContext context) async {
  if (await KidsPinService.get() != null) return true;
  if (!context.mounted) return false;
  final first = await _askPin(
    context,
    title: 'Crea un PIN',
    message: 'Scegli un PIN a 4 cifre: servirà per passare dal profilo bambini a un profilo adulto.',
  );
  if (first == null || !context.mounted) return false;
  final second = await _askPin(
    context,
    title: 'Conferma il PIN',
    message: 'Inserisci di nuovo lo stesso PIN.',
  );
  if (second != first) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('I PIN non coincidono, riprova.'),
        ),
      );
    }
    return false;
  }
  await KidsPinService.set(first);
  return true;
}
