import 'package:flutter/material.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';

/// The pictures attached to a feedback draft, in capture order.
///
/// Several shots of one screen are normal — mid-scroll, a menu open, an error
/// showing — so nothing is merged or deduplicated here: each is numbered and
/// labelled with the screen it was taken on. The strip scrolls sideways, so
/// it stays one row deep at phone width however many shots there are.
class FeedbackScreenshotStrip extends StatelessWidget {
  const FeedbackScreenshotStrip({
    required this.screenshots,
    required this.onRemove,
    required this.onCrop,
    required this.onCaptionChanged,
    this.enabled = true,
    super.key,
  });

  static const double thumbnailWidth = 132;
  static const double thumbnailHeight = 96;

  static Key thumbnailKey(int position) =>
      ValueKey<String>('feedback-screenshot-$position');

  static Key removeKey(int position) =>
      ValueKey<String>('feedback-screenshot-remove-$position');

  final List<FeedbackScreenshot> screenshots;
  final bool enabled;
  final void Function(int index) onRemove;
  final Future<void> Function(int index) onCrop;
  final void Function(int index, String caption) onCaptionChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;

    return SizedBox(
      height: thumbnailHeight + 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: screenshots.length,
        separatorBuilder: (_, _) => SizedBox(width: theme.spacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final FeedbackScreenshot screenshot = screenshots[index];
          final int position = index + 1;

          return SizedBox(
            width: thumbnailWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Stack(
                  children: <Widget>[
                    InkWell(
                      key: thumbnailKey(position),
                      onTap: enabled
                          ? () => _openPreview(context, index, position)
                          : null,
                      borderRadius: BorderRadius.circular(theme.radius.xs),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(theme.radius.xs),
                        child: Image.memory(
                          screenshot.bytes,
                          width: thumbnailWidth,
                          height: thumbnailHeight,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          semanticLabel: l10n.feedbackScreenshotPreviewTitle(
                            position,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        key: removeKey(position),
                        icon: const Icon(Icons.close),
                        iconSize: theme.appTokens.listIconSize,
                        tooltip: l10n.feedbackScreenshotRemoveLabel(position),
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: theme.colorScheme.surface.withValues(
                            alpha: 0.8,
                          ),
                        ),
                        onPressed: enabled ? () => onRemove(index) : null,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: theme.spacing.xs),
                Text(
                  '$position. ${screenshot.screen.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openPreview(
    BuildContext context,
    int index,
    int position,
  ) async {
    await showAppDialog<void>(
      context: context,
      builder: (_) => _FeedbackScreenshotPreviewDialog(
        screenshot: screenshots[index],
        position: position,
        onCrop: () => onCrop(index),
        onCaptionChanged: (String caption) => onCaptionChanged(index, caption),
        onRemove: () => onRemove(index),
      ),
    );
  }
}

/// One attached picture at full size, with the two things a reporter does to
/// it before sending: crop out what should not travel, and say what to look
/// at.
class _FeedbackScreenshotPreviewDialog extends StatefulWidget {
  const _FeedbackScreenshotPreviewDialog({
    required this.screenshot,
    required this.position,
    required this.onCrop,
    required this.onCaptionChanged,
    required this.onRemove,
  });

  final FeedbackScreenshot screenshot;
  final int position;
  final Future<void> Function() onCrop;
  final ValueChanged<String> onCaptionChanged;
  final VoidCallback onRemove;

  @override
  State<_FeedbackScreenshotPreviewDialog> createState() =>
      _FeedbackScreenshotPreviewDialogState();
}

class _FeedbackScreenshotPreviewDialogState
    extends State<_FeedbackScreenshotPreviewDialog> {
  late final TextEditingController _captionController =
      TextEditingController(text: widget.screenshot.caption ?? '');

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;

    return AppDialog(
      title: Text(l10n.feedbackScreenshotPreviewTitle(widget.position)),
      icon: const Icon(Icons.image_outlined),
      scrollable: true,
      sizeToContent: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            widget.screenshot.screen.label,
            style: theme.textTheme.labelLarge,
          ),
          SizedBox(height: theme.spacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(theme.radius.xs),
            child: Image.memory(widget.screenshot.bytes, fit: BoxFit.contain),
          ),
          SizedBox(height: theme.spacing.sm),
          AppTextField(
            controller: _captionController,
            labelText: l10n.feedbackScreenshotCaptionLabel,
            hintText: l10n.feedbackScreenshotCaptionHint,
            onChanged: widget.onCaptionChanged,
          ),
        ],
      ),
      actions: <Widget>[
        AppButton.secondary(
          label: l10n.feedbackScreenshotCropAction,
          leadingIcon: Icons.crop,
          onPressed: () async {
            Navigator.of(context).pop();
            await widget.onCrop();
          },
        ),
        AppButton.secondary(
          label: l10n.feedbackScreenshotRemoveLabel(widget.position),
          leadingIcon: AppActionIcons.delete,
          color: theme.colorScheme.error,
          onPressed: () {
            widget.onRemove();
            Navigator.of(context).pop();
          },
        ),
        AppButton.close(
          label: l10n.commonCloseActionLabel,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}
