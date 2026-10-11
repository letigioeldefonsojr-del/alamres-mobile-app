import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/banner_helpers.dart';
import 'product_image.dart';

/// Home-screen promo carousel. Replaces the old single-banner
/// `StreamBuilder` that used to live inline in `home_tab.dart`.
///
/// Data sources (in priority order):
///   1. The new `storeBanners/{id}` collection - any number of promos,
///      each with its own schedule window, shown in `sortOrder`.
///   2. If that collection is empty, falls back to the legacy single
///      `settings/storeBanner` document so stores that haven't moved to
///      the new collection yet keep seeing their existing banner exactly
///      as before.
///
/// Behaviour:
///   - 0 live promos: renders nothing (`SizedBox.shrink`), same as the
///     old banner did when there was no valid banner.
///   - Exactly 1 live promo: a single static card - no auto-scroll, no
///     swiping, no dot indicators.
///   - 2+ live promos: a swipeable, infinitely-looping `PageView` that
///     auto-advances every ~4s, pauses while the user is touching or
///     dragging it (resuming ~4s after they let go), pauses while the
///     app is backgrounded, and shows dot indicators.
///
/// Both streams are re-checked every 60s on a timer (in addition to
/// whenever Firestore pushes a new snapshot) so a promo whose schedule
/// starts or ends while the app is sitting open on the home screen
/// appears/disappears on its own, without needing a new write.
class PromoBannerCarousel extends StatefulWidget {
  const PromoBannerCarousel({super.key});

  @override
  State<PromoBannerCarousel> createState() => _PromoBannerCarouselState();
}

class _PromoBannerCarouselState extends State<PromoBannerCarousel>
    with WidgetsBindingObserver {
  static const Color _primaryGreen = Color(0xFF2E6B3E);

  // How far past a clean multiple of the live-promo count the controller's
  // initialPage starts - gives plenty of room to swipe backwards before
  // ever hitting page 0, which is what actually makes the loop feel
  // infinite in both directions.
  static const int _pageMultiplier = 5000;

  StreamSubscription<List<PromoBanner>>? _newBannersSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _legacySub;
  Timer? _recheckTimer;
  Timer? _autoScrollTimer;
  Timer? _resumeTimer;

  List<PromoBanner> _newBanners = [];
  DocumentSnapshot<Map<String, dynamic>>? _legacyDoc;
  bool _newBannersLoaded = false;
  bool _legacyLoaded = false;

  List<PromoBanner> _liveBanners = const [];
  PageController? _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _newBannersSub = storeBannersStream().listen((banners) {
      _newBanners = banners;
      _newBannersLoaded = true;
      _recomputeLiveBanners();
    });

    _legacySub = storeBannerStream().listen((doc) {
      _legacyDoc = doc;
      _legacyLoaded = true;
      _recomputeLiveBanners();
    });

    // Belt-and-suspenders re-check for schedule windows opening/closing
    // while nothing has written to Firestore in the meantime.
    _recheckTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _recomputeLiveBanners(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _newBannersSub?.cancel();
    _legacySub?.cancel();
    _recheckTimer?.cancel();
    _autoScrollTimer?.cancel();
    _resumeTimer?.cancel();
    _pageController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAutoScroll();
    } else {
      _autoScrollTimer?.cancel();
      _resumeTimer?.cancel();
    }
  }

  // --- Data -----------------------------------------------------------

  void _recomputeLiveBanners() {
    // Wait until at least one stream has actually emitted once, so we
    // don't flash an empty carousel for a frame before Firestore replies.
    if (!_newBannersLoaded && !_legacyLoaded) return;

    List<PromoBanner> live;
    if (_newBanners.isNotEmpty) {
      live = _newBanners.where((b) => b.isCurrentlyLive).toList();
    } else {
      final data = _legacyDoc?.data();
      if (data != null && isBannerCurrentlyValid(data)) {
        live = [PromoBanner.fromMap('legacy', data)];
      } else {
        live = const [];
        // Same cleanup the old single-banner code did: once a scheduled
        // banner's end date has passed, delete the doc instead of
        // leaving a dead banner behind forever.
        if (data != null && (data['scheduleEnd'] as Timestamp?) != null) {
          deleteStoreBanner();
        }
      }
    }

    if (_bannersEqual(live, _liveBanners)) return;

    // Try to keep showing whatever banner is currently on screen (by id,
    // not index) across the rebuild, so an admin editing an unrelated
    // promo elsewhere in the list doesn't yank the customer back to the
    // first slide.
    String? keepBannerId;
    if (_liveBanners.isNotEmpty) {
      final oldRealIndex = _realIndexOf(_currentPage, _liveBanners.length);
      keepBannerId = _liveBanners[oldRealIndex].id;
    }

    setState(() {
      _liveBanners = live;
      _rebuildController(keepBannerId: keepBannerId);
    });
  }

  bool _bannersEqual(List<PromoBanner> a, List<PromoBanner> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final pa = a[i];
      final pb = b[i];
      if (pa.id != pb.id ||
          pa.offer != pb.offer ||
          pa.description != pb.description ||
          pa.imageUrl != pb.imageUrl ||
          pa.scheduleStart != pb.scheduleStart ||
          pa.scheduleEnd != pb.scheduleEnd) {
        return false;
      }
    }
    return true;
  }

  int _realIndexOf(int page, int length) {
    if (length == 0) return 0;
    final int mod = page % length;
    // Dart's % can return a value with the sign of the dividend for
    // negative numbers in some edge cases; normalize just in case.
    return mod < 0 ? mod + length : mod;
  }

  // --- Carousel controller / auto-scroll -------------------------------

  void _rebuildController({String? keepBannerId}) {
    final oldController = _pageController;
    final int length = _liveBanners.length;

    _autoScrollTimer?.cancel();
    _resumeTimer?.cancel();

    if (length <= 1) {
      oldController?.dispose();
      _pageController = null;
      return;
    }

    int realIndex = 0;
    if (keepBannerId != null) {
      final idx = _liveBanners.indexWhere((b) => b.id == keepBannerId);
      if (idx != -1) realIndex = idx;
    }

    final int initialPage = (_pageMultiplier * length) + realIndex;
    oldController?.dispose();
    _pageController = PageController(initialPage: initialPage);
    _currentPage = initialPage;

    _startAutoScroll();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    if (_liveBanners.length < 2 || _pageController == null) return;
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _pageController?.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  void _onInteractionStart() {
    _autoScrollTimer?.cancel();
    _resumeTimer?.cancel();
  }

  void _onInteractionEnd() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 4), _startAutoScroll);
  }

  // --- UI ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_liveBanners.isEmpty) {
      return const SizedBox.shrink();
    }

    final bool multi = _liveBanners.length > 1;

    Widget bannerArea;
    if (multi) {
      bannerArea = Listener(
        onPointerDown: (_) => _onInteractionStart(),
        onPointerUp: (_) => _onInteractionEnd(),
        onPointerCancel: (_) => _onInteractionEnd(),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification) {
              _onInteractionStart();
            } else if (notification is ScrollEndNotification) {
              _onInteractionEnd();
            }
            return false;
          },
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (page) => setState(() => _currentPage = page),
            itemBuilder: (context, index) {
              final banner = _liveBanners[index % _liveBanners.length];
              return _PromoCard(banner: banner);
            },
          ),
        ),
      );
    } else {
      bannerArea = _PromoCard(banner: _liveBanners.first);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(height: 130, child: bannerArea),
        ),
        if (multi) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_liveBanners.length, (index) {
              final bool active =
                  _realIndexOf(_currentPage, _liveBanners.length) == index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active
                      ? _primaryGreen
                      : _primaryGreen.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

/// One promo slide. Visually identical to the old single-banner card:
/// image (or a placeholder gradient when there isn't one yet) with a
/// dark gradient overlay, "SPECIAL OFFER" label, offer headline,
/// optional description line. `ProductImage` already handles a broken
/// image URL gracefully (shows a broken-image icon instead of crashing),
/// so there's nothing extra to do for that here.
class _PromoCard extends StatelessWidget {
  final PromoBanner banner;
  const _PromoCard({required this.banner});

  // Extra insurance on top of the scrim for the image case - a small dark
  // blur right behind the glyphs themselves, so the caption stays legible
  // even over a photo with bright colors right where the text sits.
  static const List<Shadow> _captionShadow = [
    Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    final String? bannerImage = banner.imageUrl;
    final bool hasImage = bannerImage != null && bannerImage.trim().isNotEmpty;

    return Container(
      height: 130,
      width: double.infinity,
      decoration: BoxDecoration(
        color: hasImage ? const Color(0xFFDCEBDD) : null,
        gradient: hasImage
            ? null
            : LinearGradient(
                // Seeded by the banner's own id (instead of a fresh
                // random pick every build) so it doesn't flicker to a
                // different color every time the carousel rebuilds.
                colors: placeholderGradientFor(banner.id),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: hasImage
                ? ProductImage(
                    imageUrl: bannerImage,
                    iconSize: 40,
                    borderRadius: BorderRadius.circular(18),
                  )
                : const SizedBox.shrink(),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              // A real uploaded photo can be busy or brightly colored (and
              // sometimes already has its own text baked into it), so it
              // needs a much stronger, bottom-anchored scrim than the flat
              // placeholder gradient ever did - otherwise the caption text
              // below fights with whatever's in the picture. The
              // placeholder case (no image yet) keeps its original subtle
              // corner scrim since there's no competing imagery to wash out.
              gradient: hasImage
                  ? const LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black45,
                        Colors.black87,
                      ],
                      stops: [0.0, 0.55, 1.0],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    )
                  : LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.45),
                        Colors.transparent,
                      ],
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                    ),
            ),
          ),
          Positioned(
            left: 18,
            bottom: 16,
            right: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPECIAL OFFER',
                  style: TextStyle(
                    color: Colors.greenAccent.shade100,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    shadows: hasImage ? _captionShadow : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  banner.offer,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                    shadows: hasImage ? _captionShadow : null,
                  ),
                ),
                if (banner.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    banner.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      shadows: hasImage ? _captionShadow : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
