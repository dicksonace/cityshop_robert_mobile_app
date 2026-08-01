import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shell for form bottom sheets: the body scrolls and the action button is
/// pinned above the keyboard and the system navigation bar, so a submit button
/// can never end up clipped or hidden behind the nav bar on short screens.
class SheetShell extends StatelessWidget {
  const SheetShell({
    super.key,
    required this.children,
    this.action,
    this.maxHeightFactor = 0.9,
  });

  /// Scrollable sheet body.
  final List<Widget> children;

  /// Always-visible trailing action, usually the submit button.
  final Widget? action;

  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final navBar = MediaQuery.viewPaddingOf(context).bottom;
    // The keyboard already pushes the sheet up, so only reserve nav bar space
    // when it is closed. 12 keeps the button off the very edge either way.
    final actionBottom = 12 + (keyboard > 0 ? 0.0 : navBar);
    final maxHeight = (MediaQuery.sizeOf(context).height - keyboard) * maxHeightFactor;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            if (action != null)
              Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, actionBottom),
                child: action,
              ),
          ],
        ),
      ),
    );
  }
}

/// Opens [SheetShell] with the app's sheet chrome.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: builder,
  );
}
