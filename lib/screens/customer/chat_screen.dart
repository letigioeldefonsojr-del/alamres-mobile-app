import 'package:flutter/material.dart';
import '../../widgets/chat_panel.dart';

/// Full-screen "Ask Almares 328" chat. This is just the shared ChatPanel
/// wrapped in a Scaffold + AppBar - the conversation UI itself lives in
/// ChatPanel so it's identical whether you're here or in the floating
/// bubble on HomeScreen.
///
/// [initialMessages] lets HomeScreen hand over whatever was already typed
/// in the floating bubble when the user taps "expand," so the conversation
/// continues instead of restarting.
class ChatScreen extends StatelessWidget {
  final List<ChatMessage>? initialMessages;

  const ChatScreen({super.key, this.initialMessages});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Ask Almares 328'),
      ),
      body: ChatPanel(initialMessages: initialMessages),
    );
  }
}
