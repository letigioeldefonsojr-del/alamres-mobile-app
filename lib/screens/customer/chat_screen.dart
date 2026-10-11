import 'package:flutter/material.dart';
import '../../widgets/chat_panel.dart';

/// Full-screen "Ask Almares 328" chat. This is just the shared ChatPanel
/// wrapped in a Scaffold + AppBar - the conversation UI itself lives in
/// ChatPanel, and both this and HomeScreen's floating bubble read from the
/// same ChatConversation singleton (see lib/services/chat_conversation.dart),
/// so switching between them never loses or duplicates a message.
class ChatScreen extends StatelessWidget {
  // Not `const` - this key is created once when this ChatScreen instance
  // is built (by whoever navigates to it) and stays tied to that same
  // ChatPanel for the screen's lifetime, so the "New chat" button below
  // can reach into it.
  final GlobalKey<ChatPanelState> _chatPanelKey = GlobalKey<ChatPanelState>();

  ChatScreen({super.key});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Ask Almares 328'),
        actions: [
          IconButton(
            tooltip: 'Start new chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () => _chatPanelKey.currentState?.startNewChat(),
          ),
        ],
      ),
      body: ChatPanel(key: _chatPanelKey),
    );
  }
}
