import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../services/chat_conversation.dart';
import '../services/chat_service.dart';

export '../services/chat_service.dart' show ChatMessage;

/// The actual chat conversation UI (message list + input bar) - shared
/// between the floating chat bubble on HomeScreen and the full-screen
/// ChatScreen so the conversation logic only lives in one place. Both
/// read from the same ChatConversation singleton (see that file for why),
/// so there's only ever one real conversation no matter which view is on
/// screen.
///
/// Pass a `GlobalKey<ChatPanelState>` as `key` to call [startNewChat] from
/// outside (e.g. the "New chat" buttons on ChatScreen and HomeScreen's
/// floating chat card).
class ChatPanel extends StatefulWidget {
  // Whether the input bar should reserve extra space for the device's
  // bottom system inset (gesture bar / home indicator) - true for
  // ChatScreen, which really does sit flush against the bottom of the
  // display. HomeScreen's floating chat card passes false: that card
  // already floats well above the bottom nav bar, so adding the system
  // inset on top of that was just extra blank space under the send
  // button for no reason.
  final bool bottomSafeArea;

  const ChatPanel({super.key, this.bottomSafeArea = true});

  @override
  State<ChatPanel> createState() => ChatPanelState();
}

class ChatPanelState extends State<ChatPanel> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final ChatConversation _conversation = ChatConversation.instance;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Scrolls THIS panel's own list to bottom whenever the shared
    // conversation changes - covers both "my own message just got sent"
    // and "a reply came back while I was looking at the other view".
    _conversation.addListener(_scrollToBottom);
  }

  @override
  void dispose() {
    _conversation.removeListener(_scrollToBottom);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Clears the conversation back to just the greeting - call this from
  /// outside via a GlobalKey to let the customer deliberately start over
  /// instead of always continuing whatever they asked before.
  void startNewChat() {
    _conversation.startNewChat();
    _controller.clear();
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
    if (text.isEmpty || _conversation.isSending) return;
    _controller.clear();
    // Fire-and-forget on purpose: awaiting here would tie the reply to
    // THIS widget's lifetime again, which is exactly the bug this
    // refactor removes - ChatConversation.send() already notifies its
    // listeners (any mounted ChatPanel, bubble or full-screen) once the
    // reply lands, whether or not this particular widget is still around.
    unawaited(_conversation.send(text));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _conversation,
      builder: (context, _) {
        final List<ChatMessage> messages = _conversation.messages;
        final bool isSending = _conversation.isSending;

        final Widget inputBar = Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                  onPressed: isSending ? null : _send,
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        );

        return Column(
          children: [
            Expanded(
              child: Container(
                color: const Color(0xFFF7F7F7),
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length + (isSending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return const ChatTypingBubble();
                    }
                    return ChatBubble(message: messages[index]);
                  },
                ),
              ),
            ),
            // Only reserve the device's bottom system-inset space when
            // this panel really does sit at the physical bottom of the
            // screen (see the `bottomSafeArea` doc comment on ChatPanel
            // above).
            widget.bottomSafeArea
                ? SafeArea(top: false, child: inputBar)
                : inputBar,
          ],
        );
      },
    );
  }
}

/// Styles Markdown in an assistant bubble to look like the plain Text it
/// replaced - same size/color as before, just with **bold** and "-" lists
/// actually rendered instead of shown as raw characters.
MarkdownStyleSheet _assistantMarkdownStyle(BuildContext context) {
  const baseStyle = TextStyle(color: Colors.black87, fontSize: 14);
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: baseStyle,
    strong: baseStyle.copyWith(fontWeight: FontWeight.bold),
    em: baseStyle.copyWith(fontStyle: FontStyle.italic),
    listBullet: baseStyle,
    blockquote: baseStyle,
    code: baseStyle.copyWith(fontFamily: 'monospace'),
    // MarkdownBody already sits inside the bubble's own padding - drop its
    // default extra margins around paragraphs/lists so it doesn't look
    // more spaced-out than the plain Text bubbles did.
    pPadding: EdgeInsets.zero,
  );
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
            // The assistant is told to reply in Markdown (see the Worker's
            // system prompt) so **bold** product names and "-" lists render
            // properly instead of showing raw asterisks/dashes. Whatever
            // the customer typed is shown as plain text instead - no
            // reason to interpret their own message as Markdown too.
            child: isUser
                ? Text(
                    message.content,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  )
                : MarkdownBody(
                    data: message.content,
                    styleSheet: _assistantMarkdownStyle(context),
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
