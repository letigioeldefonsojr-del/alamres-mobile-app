import 'package:flutter/foundation.dart';
import 'chat_service.dart';

/// Pool of FAQ-style quick questions offered as tappable "ready to send"
/// buttons on a brand-new chat (see chat_panel.dart's quick-reply row) -
/// two are picked at random from here each time a chat starts, so a
/// returning customer doesn't see the exact same two every time. This is
/// pure local list-shuffling - it never touches the network or Claude, so
/// randomizing it costs nothing extra (these are just button labels until
/// one is actually tapped and sent as a real message).
const List<String> _kQuickReplyPool = [
  'How do I place an order?',
  'How does wholesale pricing work?',
  "What's in stock right now?",
  'What are your best sellers?',
  'How do I check my order status?',
  'Can I pick up my order instead of delivery?',
  'How is the delivery fee calculated?',
  'Do you have ongoing discounts or promos?',
  'How do I pick a flavor or variant for a product?',
  'Where can I see my past orders?',
];

/// Always the third quick-reply button, never randomized out - the
/// Worker's system prompt (cloudflare-worker/src/index.js's
/// `CLIENT_CONTACT_NUMBER` / `contactGuidance`) is told to answer this
/// directly, and to fall back to it whenever it genuinely can't answer
/// something else.
const String kContactQuickReply =
    "What's your contact number for real-time inquiries?";

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
  List<String> _quickReplyQuestions = _pickQuickReplies();

  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);
  bool get isSending => _isSending;

  /// The 3 quick-reply buttons for the CURRENT chat - 2 random picks from
  /// `_kQuickReplyPool` plus `kContactQuickReply` fixed last. Stays the
  /// same for as long as this chat does (so the buttons don't shuffle out
  /// from under the customer while they're still looking at them) and is
  /// only re-rolled by `startNewChat()`.
  List<String> get quickReplyQuestions =>
      List<String>.unmodifiable(_quickReplyQuestions);

  static List<String> _pickQuickReplies() {
    final List<String> shuffled = List<String>.of(_kQuickReplyPool)
      ..shuffle();
    return [...shuffled.take(2), kContactQuickReply];
  }

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
    _quickReplyQuestions = _pickQuickReplies();
    notifyListeners();
  }
}
