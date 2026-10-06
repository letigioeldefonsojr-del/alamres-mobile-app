import 'package:flutter/material.dart';

/// Shared anchor point for the "fly to cart" add-to-cart animation.
///
/// The one real cart icon in the app (the header button on the Home tab)
/// attaches this key to itself, so the animation can look up its current
/// on-screen position from wherever "Add to Cart" was actually tapped -
/// which may be a completely different screen/route. When that icon isn't
/// currently mounted (e.g. adding from a screen with no cart icon of its
/// own, such as the category/search/all-products listings), the animation
/// falls back to a generic top-right target instead of failing silently.
final GlobalKey cartIconKey = GlobalKey();
