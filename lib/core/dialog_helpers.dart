import 'dart:async';
import 'package:flutter/material.dart';

Future<String?> promptPasswordConfirmation(BuildContext context) async {
  final passwordController = TextEditingController();
  bool obscure = true;

  return showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Confirm Your Password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'For your security, please enter your password to continue.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passwordController,
                  obscureText: obscure,
                  // Some IMEs render a character's "composing" preview even
                  // while obscureText is true, and that preview can get
                  // stuck showing after toggling the eye icon. Turning off
                  // autocorrect/suggestions stops the keyboard from
                  // composing at all, which is the standard fix for that.
                  autocorrect: false,
                  enableSuggestions: false,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: Colors.grey,
                      ),
                      onPressed: () => setDialogState(() => obscure = !obscure),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () {
                  if (passwordController.text.isEmpty) return;
                  Navigator.pop(context, passwordController.text);
                },
                child: const Text(
                  'Confirm',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
