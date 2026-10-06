import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

/// One message in the chat, in the same {role, content} shape Claude's
/// Messages API expects ('user' or 'assistant').
class ChatMessage {
  final String role;
  final String content;

  const ChatMessage({required this.role, required this.content});

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// Talks to the Cloudflare Worker proxy (see /cloudflare-worker at the
/// project root). The Worker is the only thing that ever holds the real
/// Anthropic API key - this app only ever calls the Worker's URL, and only
/// while the user is logged in (it sends their Firebase ID token so the
/// Worker can reject requests from anyone who isn't an actual app user).
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  /// Sends the full conversation so far (including the newest user message)
  /// and returns the assistant's reply text. Never throws - any failure
  /// comes back as a plain-English string meant to be shown directly in
  /// the chat, so the UI never needs its own error-handling branch.
  Future<String> sendMessage(List<ChatMessage> conversation) async {
    if (kChatWorkerUrl.isEmpty || kChatWorkerUrl == 'REPLACE_WITH_WORKER_URL') {
      return "The chat assistant hasn't been connected yet - the backend "
          "URL still needs to be filled in (see SETUP_CHATBOT.md).";
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return 'Please log in to use the chat assistant.';
    }

    try {
      final idToken = await user.getIdToken();

      final response = await http
          .post(
            Uri.parse(kChatWorkerUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'messages': conversation.map((m) => m.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;

      if (data['ok'] == true) {
        return (data['reply'] as String?) ?? "Sorry, I didn't get a reply.";
      }

      return (data['error'] as String?) ??
          'The assistant is temporarily unavailable. Please try again later.';
    } catch (e) {
      return 'Could not reach the assistant. Check your connection and try again.';
    }
  }
}
