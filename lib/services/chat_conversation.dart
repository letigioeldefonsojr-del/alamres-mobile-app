import 'package:flutter/foundation.dart';
import 'chat_service.dart';

/// The single, app-wide source of truth for the "Ask Almares 328"
/// conversation. Both the floating chat bubble on HomeScreen and the
/// full-screen ChatScreen read from (and write to) this same instance,
/// rather than each keeping its own separate copy of the messages.
///
/// Why this exists: the old design had each ChatPanel own its own message
/// list, and HomeScreen's "expand to full screen" button just copied a
/// one-time snapshot of the bubble's messages into a brand new ChatPanel.
/// That meant sending a message in the bubble and then immediately
/// expanding - before the reply came back - raced: the reply would land
/// in the now-hidden bubble's own copy once the network call finished,
/// never in the full-screen conversation the customer was actually
/// looking at, so it looked like the reply just never arrived. Routing
/// both views through one shared conversation makes that race impossible
/// - there's only ever one conversation for a reply to land in.
///
/// Still purely in-memory (same as before) - it resets when the app
/// process is fully closed/restarted, not just when a screen is closed.
class ChatConversation extends ChangeNotifier {
  ChatConversation._();
  static final ChatConversation instance = ChatConversation._();

  static const ChatMessage _greeting = ChatMessage(
    role: 'assistant',
    content:
        "Hi! I'm the Almares 328 assistant. Ask me anything about "
        "our products, policies, or how to shop with us.",
  );

  final List<ChatMessage> _messages = [_greeting];
  bool _isSending = false;

  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);
  bool get isSending => _isSending;

  /// Sends [rawText] as a new user message and waits for the assistant's
  /// reply, notifying listeners after the user message is added and again
  /// once the reply comes in - so UI watching this controller can show the
  /// user's message immediately and the typing indicator while it waits.
  Future<void> send(String rawText) async {
    final String text = rawText.trim();
    if (text.isEmpty || _isSending) return;

    _messages.add(ChatMessage(role: 'user', content: text));
    _isSending = true;
    notifyListeners();

    final String reply = await ChatService.instance.sendMessage(_messages);

    _messages.add(ChatMessage(role: 'assistant', content: reply));
    _isSending = false;
    notifyListeners();
  }

  /// Clears the conversation back to just the greeting - e.g. for a
  /// "New chat" button. Safe to call from anywhere; there's nothing
  /// widget-specific to reach into since this controller is the one
  /// shared source of truth.
  void startNewChat() {
    _messages
      ..clear()
      ..add(_greeting);
    _isSending = false;
    notifyListeners();
  }
}
