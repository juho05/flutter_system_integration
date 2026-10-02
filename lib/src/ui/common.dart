import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

/// Displays a short message to the user, e.g. as a toast or snack bar.
typedef ShowMessageCallback =
    void Function(BuildContext context, String message);

void showSnackBarMessage(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

class AdaptiveDialogAction extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;

  const AdaptiveDialogAction({super.key, this.onPressed, required this.child});

  @override
  Widget build(BuildContext context) {
    switch (Theme.of(context).platform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return CupertinoDialogAction(onPressed: onPressed, child: child);
      default:
        return TextButton(onPressed: onPressed, child: child);
    }
  }
}

class InfoText extends StatelessWidget {
  final String text;

  const InfoText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface.withAlpha(180);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Icon(Icons.info_outline, color: color, size: 18),
        Text(
          text,
          style: theme.textTheme.bodyMedium!.copyWith(
            color: color,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
