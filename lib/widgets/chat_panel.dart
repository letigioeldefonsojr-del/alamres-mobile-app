import 'package:flutter/material.dart';
import '../services/chat_service.dart';

export '../services/chat_service.dart' show ChatMessage;

/// The actual chat conversation UI (message list + input bar) - shared
/// between the floating chat bubble on HomeScreen and the full-screen
/// ChatScreen so the conversation logic only lives in one place.
///
/// Pass a `GlobalKey<ChatPanelState>` as `key` to read the live
/// conversation from outside (e.g. HomeScreen uses this to hand the
/// current messages over to ChatScreen when "expanding" the floating
/// bubble to a full screen).
class ChatPanel extends StatefulWidget {
  final List<ChatMessage>? initialMessages;

  const ChatPanel({super.key, this.initialMessages});

  @override
  State<ChatPanel> createState() => ChatPanelState();
}

class ChatPanelState extends State<ChatPanel> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  late final List<ChatMessage> _messages =
      (widget.initialMessages != null && widget.initialMessages!.isNotEmpty)
      ? List<ChatMessage>.from(widget.initialMessages!)
      : [
          const ChatMessage(
            role: 'assistant',
            content:
                "Hi! I'm the Almares 328 assistant. Ask me anything about "
                "our products, policies, or how to shop with us.",
          ),
        ];

  /// The conversation so far. Read this from outside via a GlobalKey to
  /// carry it over when switching between the floating and full-screen
  /// views of the chat.
  List<ChatMessage> get messages => List<ChatMessage>.from(_messages);

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final String text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _messages.add(ChatMessage(role: 'user', content: text));
      _isSending = true;
      _controller.clear();
    });
    _scrollToBottom();

    final String reply = await ChatService.instance.sendMessage(_messages);

    if (!mounted) return;
    setState(() {
      _messages.add(ChatMessage(role: 'assistant', content: reply));
      _isSending = false;
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            color: const Color(0xFFF7F7F7),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isSending ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const ChatTypingBubble();
                }
                return ChatBubble(message: _messages[index]);
              },
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Type your question...',
                      filled: true,
                      fillColor: const Color(0xFFF7F7F7),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(
                    color: primaryGreen,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _isSending ? null : _send,
                    icon: const Icon(
                      Icons.send,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const ChatBubble({super.key, required this.message});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == 'user';
    // LayoutBuilder (not MediaQuery) so the bubble's max width is relative
    // to whatever it's actually placed inside - the full screen width on
    // ChatScreen, or the narrower floating bubble on HomeScreen.
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.8),
            decoration: BoxDecoration(
              color: isUser ? primaryGreen : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              message.content,
              style: TextStyle(
                color: isUser ? Colors.white : Colors.black87,
                fontSize: 14,
              ),
            ),
          ),
        );
      },
    );
  }
}

class ChatTypingBubble extends StatelessWidget {
  const ChatTypingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
