import 'package:flutter/widgets.dart';

/// Clears focus the way this app needs before navigating to a new screen,
/// opening a sheet/dialog, or otherwise moving away from a field that might
/// still have keyboard focus (search boxes, mainly).
///
/// A bare `FocusScope.of(context).unfocus()` only dismisses the keyboard
/// right now - Flutter's default `UnfocusDisposition.scope` deliberately
/// *keeps* the enclosing scope's memory of "this was the last focused
/// child", specifically so that scope can refocus it later. That's exactly
/// what was reopening the keyboard by itself: tap the search field, tap a
/// category (or the chat button) to navigate away, then come back - and
/// Flutter silently refocuses that same field, with nothing visibly focused
/// and no tap from the customer. Passing
/// `UnfocusDisposition.previouslyFocusedChild` clears that memory too, so
/// nothing reopens the keyboard until the customer deliberately taps a
/// field again.
void clearKeyboardFocus(BuildContext context) {
  FocusScope.of(
    context,
  ).unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
}
