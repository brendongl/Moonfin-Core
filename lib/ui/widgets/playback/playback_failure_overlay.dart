import 'package:flutter/material.dart';

/// Keep failures visible until the viewer retries or leaves the player.
/// A short snackbar is easily missed while a TV is showing a black frame.
class PlaybackFailureOverlay extends StatelessWidget {
  const PlaybackFailureOverlay({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onBack,
    this.onChangeConnection,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final VoidCallback? onChangeConnection;

  @override
  Widget build(BuildContext context) => FocusScope(
    autofocus: true,
    child: ColoredBox(
      color: Colors.black87,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Playback could not start',
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    FilledButton(
                      autofocus: true,
                      onPressed: onRetry,
                      child: const Text('Try again'),
                    ),
                    if (onChangeConnection != null) ...[
                      OutlinedButton(
                        onPressed: onChangeConnection,
                        child: const Text('Change connection'),
                      ),
                    ],
                    OutlinedButton(
                      onPressed: onBack,
                      child: const Text('Go back'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
