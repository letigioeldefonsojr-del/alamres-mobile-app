import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'categories_tab.dart';
import 'chat_screen.dart';
import 'home_tab.dart';
import 'orders_tab.dart';
import 'profile_tab.dart';
import 'add_mobile_number_screen.dart';
import 'edit_profile_screen.dart';
import 'order_details_screen.dart';
import '../../widgets/chat_panel.dart';
import '../../services/engagement_reminder_service.dart';

class HomeScreen extends StatefulWidget {
  // Which bottom-nav tab to land on when this screen first appears - 0
  // (Home) unless a caller asks for a specific one, e.g. the push
  // notification click handler jumping straight to Orders (index 2).
  final int initialTabIndex;

  // Set by the push notification click handler when the tapped
  // notification was about one specific order - once this screen is up,
  // it opens straight into that order's details. Deliberately handled
  // here, as part of this screen's own first-frame setup (same pattern as
  // the mobile-number check below), rather than as a second, separately
  // timed Navigator call from the click handler itself - that two-call
  // approach left a gap where this screen could still be mid-setup when
  // the second push landed.
  final String? openOrderId;

  const HomeScreen({
    super.key,
    this.initialTabIndex = 0,
    this.openOrderId,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  int _selectedIndex = 0;
  bool _isChatOpen = false;
  final GlobalKey<ChatPanelState> _chatPanelKey = GlobalKey<ChatPanelState>();

  final List<Widget> _tabs = const [
    HomeTab(),
    CategoriesPlaceholderTab(),
    OrdersPlaceholderTab(),
    ProfileTab(),
  ];

  final List<String> _tabLabels = const [
    'Home',
    'Categories',
    'Orders',
    'Profile',
  ];

  final List<IconData> _tabIcons = const [
    Icons.home_outlined,
    Icons.grid_view_outlined,
    Icons.receipt_long_outlined,
    Icons.person_outline,
  ];

  final List<IconData> _tabIconsFilled = const [
    Icons.home,
    Icons.grid_view,
    Icons.receipt_long,
    Icons.person,
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex;
    // Accounts created via Google Sign-In start out with no mobile number
    // on file. Check for that right after landing on the home screen and,
    // if missing, force the customer through a mandatory add-number gate
    // before they can use the rest of the app.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkMobileNumber();
      await _openOrderIfRequested();
    });
  }

  // Runs after the mobile-number gate (if any) has resolved, so a push
  // notification arriving on a Google account that hasn't added a mobile
  // number yet still shows that mandatory screen first, instead of two
  // screens racing to push on top of each other at once.
  Future<void> _openOrderIfRequested() async {
    final String? orderId = widget.openOrderId;
    if (orderId == null || orderId.trim().isEmpty) return;
    if (!mounted) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .get();
      final orderData = doc.data();
      if (orderData == null) return;
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrderDetailsScreen(orderId: orderId, data: orderData),
        ),
      );
    } catch (_) {
      // Non-critical - the customer still lands on their Orders tab
      // either way, they'd just have to tap the order themselves.
    }
  }

  Future<void> _checkMobileNumber() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final String mobileNumber = (doc.data()?['mobileNumber'] as String?) ?? '';
      if (mobileNumber.trim().isEmpty) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddMobileNumberScreen()),
        );
      }

      if (!mounted) return;
      final String address = (doc.data()?['address'] as String?) ?? '';
      _checkAddressReminder(address);

      // "Tops up" the on-device Shop Reminders queue every time the
      // customer lands on Home, so it never actually runs dry on a
      // customer who opens the app regularly - see
      // EngagementReminderService for why this needs refreshing at all
      // rather than being scheduled once.
      final prefs = doc.data()?['notificationPrefs'] as Map<String, dynamic>?;
      final bool shopRemindersEnabled = prefs?['shopReminders'] ?? false;
      unawaited(
        EngagementReminderService.instance.applyPreference(
          shopRemindersEnabled,
        ),
      );
    } catch (_) {
      // Non-blocking - if the lookup itself fails (e.g. no connection),
      // don't lock the customer out of the app over it.
    }
  }

  // A soft, dismissible reminder - not a mandatory gate like the mobile
  // number check above - nudging the customer to add a delivery address if
  // they haven't yet. Applies to both email/password and Google accounts:
  // email registration requires an address up front, so this mainly fires
  // if it was cleared later in Edit Profile - but a Google sign-in never
  // collects one at all, so this is the main real-world case it catches.
  void _checkAddressReminder(String address) {
    if (address.trim().isNotEmpty) return;
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Add a delivery address so we know where to send your orders.'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Add',
          textColor: Colors.white,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
            );
          },
        ),
      ),
    );
  }

  void _expandChat() {
    // Grab whatever's been typed in the floating bubble so far, then hand
    // it to the full-screen ChatScreen so the conversation continues
    // instead of starting over.
    final List<ChatMessage> conversation =
        _chatPanelKey.currentState?.messages ?? const [];
    setState(() => _isChatOpen = false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(initialMessages: conversation),
      ),
    );
  }

  Widget _buildFloatingChatCard(BuildContext context, double keyboardInset) {
    final Size screenSize = MediaQuery.of(context).size;
    final double panelWidth = screenSize.width < 420
        ? screenSize.width - 32
        : 360.0;

    // Preferred height when there's plenty of room (keyboard closed).
    final double preferredHeight = (screenSize.height * 0.65)
        .clamp(360.0, 560.0)
        .toDouble();
    // How much vertical space is actually left once the keyboard (if any)
    // and the card's bottom anchor (see `bottom: 150 + keyboardInset` in
    // build()) are accounted for, keeping a small 40px margin from the
    // top of the screen so the card can never get pushed off-screen.
    final double maxAvailableHeight =
        (screenSize.height - keyboardInset - 150 - 40)
            .clamp(200.0, double.infinity)
            .toDouble();
    final double panelHeight = preferredHeight < maxAvailableHeight
        ? preferredHeight
        : maxAvailableHeight;

    return Material(
      key: const ValueKey('chat-open'),
      elevation: 12,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: SizedBox(
        width: panelWidth,
        height: panelHeight,
        child: Column(
          children: [
            Container(
              color: primaryGreen,
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.smart_toy_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Ask Almares 328',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open full chat',
                    icon: const Icon(
                      Icons.open_in_full,
                      color: Colors.white,
                      size: 18,
                    ),
                    onPressed: _expandChat,
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _isChatOpen = false),
                  ),
                ],
              ),
            ),
            Expanded(child: ChatPanel(key: _chatPanelKey)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Height of the on-screen keyboard, 0 when it's closed. Used to lift
    // the floating chat card above the keyboard instead of letting it get
    // covered - see AnimatedPositioned's `bottom` below.
    final double keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Stack(
      children: [
        _buildHomeScaffold(context),
        // Dims and blurs everything behind the floating chat card while
        // it's open, so a tap meant for the chat can't land on a product
        // underneath it. Tapping the dimmed area closes the chat, same as
        // the card's own close button.
        Positioned.fill(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: _isChatOpen ? 1.0 : 0.0,
            curve: Curves.easeOut,
            child: IgnorePointer(
              ignoring: !_isChatOpen,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _isChatOpen = false),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(color: Colors.black.withValues(alpha: 0.15)),
                ),
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          right: 16,
          bottom: 150 + keyboardInset,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              alignment: Alignment.bottomRight,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: _isChatOpen
                ? _buildFloatingChatCard(context, keyboardInset)
                : const SizedBox.shrink(key: ValueKey('chat-closed')),
          ),
        ),
      ],
    );
  }

  Widget _buildHomeScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: IndexedStack(index: _selectedIndex, children: _tabs),
      ),
      // Floating chat entry point - stays visible on every tab since it
      // lives on this shared Scaffold rather than inside an individual tab.
      // Tapping it toggles a small floating chat bubble open/closed (see
      // the Positioned card built in build() below); the bubble itself has
      // an "expand" button that carries the conversation over to the
      // full-screen ChatScreen.
      floatingActionButton: Tooltip(
        message: _isChatOpen ? 'Close chat' : 'Chat with Almares 328',
        child: FloatingActionButton(
          heroTag: 'chatAssistantFab',
          backgroundColor: primaryGreen,
          onPressed: () => setState(() => _isChatOpen = !_isChatOpen),
          child: Icon(
            _isChatOpen ? Icons.close : Icons.smart_toy_outlined,
            color: Colors.white,
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_tabLabels.length, (index) {
                final bool isSelected = _selectedIndex == index;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIndex = index),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected ? _tabIconsFilled[index] : _tabIcons[index],
                        color: isSelected ? primaryGreen : Colors.grey,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _tabLabels[index],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected ? primaryGreen : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
