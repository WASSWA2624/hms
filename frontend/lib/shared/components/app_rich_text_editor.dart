import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/ai/ai_clinical_note_formatter.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/network/app_connectivity_status.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/app_field_label.dart';
import 'package:hosspi_hms/shared/components/app_form_information_banner.dart';
import 'package:hosspi_hms/shared/components/app_speech_ai.dart';
import 'package:hosspi_hms/shared/components/app_speech_to_text.dart';
import 'package:hosspi_hms/shared/forms/forms.dart';

/// Formatting tools exposed by [AppRichTextEditor].
enum AppRichTextTool { bold, italic, underline, bulletList, numberedList }

/// Lightweight markdown-ish rich text stored as plain [String].
///
/// Supports paragraphs/newlines, `**bold**`, `*italic*`, `__underline__`,
/// `- ` bullets, and `1. ` numbered lists. Prefer this over adding a
/// Delta/HTML dependency when the backend field is plain text.
abstract final class AppRichTextMarkup {
  static const String boldMarker = '**';
  static const String italicMarker = '*';
  static const String underlineMarker = '__';

  static const Set<AppRichTextTool> defaultTools = <AppRichTextTool>{
    AppRichTextTool.bold,
    AppRichTextTool.italic,
    AppRichTextTool.underline,
    AppRichTextTool.bulletList,
    AppRichTextTool.numberedList,
  };

  static void wrapSelection(
    TextEditingController controller, {
    required String prefix,
    required String suffix,
  }) {
    final TextSelection selection = controller.selection;
    final String text = controller.text;
    final int start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final int end = selection.isValid
        ? selection.end.clamp(0, text.length)
        : text.length;
    final int from = start <= end ? start : end;
    final int to = start <= end ? end : start;
    final String selected = text.substring(from, to);
    final String next =
        '${text.substring(0, from)}$prefix$selected$suffix${text.substring(to)}';
    final int cursor = from + prefix.length + selected.length + suffix.length;
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }

  static void toggleLinePrefix(
    TextEditingController controller, {
    required String prefix,
    bool numbered = false,
  }) {
    final TextSelection selection = controller.selection;
    final String text = controller.text;
    final int caret = selection.isValid
        ? selection.baseOffset.clamp(0, text.length)
        : text.length;
    final int lineStart = text.lastIndexOf('\n', caret - 1) + 1;
    int lineEnd = text.indexOf('\n', caret);
    if (lineEnd < 0) {
      lineEnd = text.length;
    }
    final String line = text.substring(lineStart, lineEnd);
    final String stripped = line
        .replaceFirst(RegExp(r'^(\d+\.\s+|[-*]\s+)'), '')
        .trimLeft();
    final bool alreadyPrefixed = numbered
        ? RegExp(r'^\d+\.\s+').hasMatch(line)
        : line.startsWith(prefix);
    final String replacement = alreadyPrefixed
        ? stripped
        : numbered
        ? '1. $stripped'
        : '$prefix$stripped';
    final String next =
        '${text.substring(0, lineStart)}$replacement${text.substring(lineEnd)}';
    final int cursor = lineStart + replacement.length;
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }

  static TextSpan toTextSpan(String source, TextStyle? baseStyle) {
    final TextStyle style = baseStyle ?? AppFontFamily.style();
    if (source.isEmpty) {
      return TextSpan(text: '', style: style);
    }

    final List<InlineSpan> children = <InlineSpan>[];
    final List<String> paragraphs = source.split('\n');
    for (var i = 0; i < paragraphs.length; i += 1) {
      if (i > 0) {
        children.add(TextSpan(text: '\n', style: style));
      }
      children.addAll(_parseInline(paragraphs[i], style));
    }
    return TextSpan(style: style, children: children);
  }

  static String plainText(String source) {
    return source
        .replaceAllMapped(
          RegExp(r'\*\*(.+?)\*\*', dotAll: true),
          (Match match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'__(.+?)__', dotAll: true),
          (Match match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\*(.+?)\*', dotAll: true),
          (Match match) => match.group(1) ?? '',
        );
  }

  static List<InlineSpan> _parseInline(String line, TextStyle base) {
    final List<InlineSpan> spans = <InlineSpan>[];
    final RegExp pattern = RegExp(
      r'(\*\*(.+?)\*\*)|(__(.+?)__)|(\*(.+?)\*)',
      dotAll: true,
    );
    var index = 0;
    for (final RegExpMatch match in pattern.allMatches(line)) {
      if (match.start > index) {
        spans.add(
          TextSpan(text: line.substring(index, match.start), style: base),
        );
      }
      if (match.group(2) != null) {
        spans.add(
          TextSpan(
            text: match.group(2),
            style: base.copyWith(fontWeight: AppFontWeight.strong),
          ),
        );
      } else if (match.group(4) != null) {
        spans.add(
          TextSpan(
            text: match.group(4),
            style: base.copyWith(decoration: TextDecoration.underline),
          ),
        );
      } else if (match.group(6) != null) {
        spans.add(
          TextSpan(
            text: match.group(6),
            style: base.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      }
      index = match.end;
    }
    if (index < line.length) {
      spans.add(TextSpan(text: line.substring(index), style: base));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: line, style: base));
    }
    return spans;
  }
}

/// Read-only rich text body for notes, comments, and similar content.
class AppRichTextView extends StatelessWidget {
  const AppRichTextView({
    required this.text,
    this.style,
    this.selectable = true,
    super.key,
  });

  final String text;
  final TextStyle? style;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle resolved =
        style ??
        theme.textTheme.bodyMedium?.copyWith(fontWeight: AppFontWeight.emphasis) ??
        AppFontFamily.style();
    final TextSpan span = AppRichTextMarkup.toTextSpan(text, resolved);
    if (selectable) {
      return SelectableText.rich(span);
    }
    return Text.rich(span);
  }
}

/// Global reusable rich text editor with an optional formatting toolbar.
///
/// Stores content as plain markdown-ish text via [AppRichTextMarkup], so it
/// works with existing `TEXT` / string API fields without schema changes.
class AppRichTextEditor extends ConsumerStatefulWidget {
  const AppRichTextEditor({
    required this.controller,
    this.labelText,
    this.hintText,
    this.helperText,
    this.errorText,
    this.minLines = 6,
    this.maxLines = 12,
    this.enabled = true,
    this.isRequired = false,
    this.autofocus = false,
    this.showToolbar = true,
    this.enableSpeechToText = true,
    this.enableAiFormat = true,
    this.aiFormatter,
    this.aiFormatHint,
    this.tools = AppRichTextMarkup.defaultTools,
    this.validator,
    this.onChanged,
    this.focusNode,
    super.key,
  });

  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final int minLines;
  final int maxLines;
  final bool enabled;
  final bool isRequired;
  final bool autofocus;
  final bool showToolbar;

  /// When true (default), shows the shared speech-to-text control.
  final bool enableSpeechToText;

  /// When true (default), shows the AI professional-format control.
  final bool enableAiFormat;

  /// Test override. Production reads [aiClinicalNoteFormatterProvider].
  final AppClinicalNoteAiFormatter? aiFormatter;

  /// Optional format hint sent to the backend task (e.g. SOAP).
  final String? aiFormatHint;
  final Set<AppRichTextTool> tools;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  @override
  ConsumerState<AppRichTextEditor> createState() => _AppRichTextEditorState();
}

class _AppRichTextEditorState extends ConsumerState<AppRichTextEditor> {
  FocusNode? _ownedFocusNode;
  late FocusNode _focusNode;
  AppSpeechAiAbort? _aiAbort;
  bool _aiFormatting = false;
  String? _aiFeedbackTitle;
  String? _aiFeedback;
  AppFormInformationVariant _aiFeedbackVariant =
      AppFormInformationVariant.warning;
  late String _lastKnownText;

  @override
  void initState() {
    super.initState();
    _attachFocusNode();
    _lastKnownText = widget.controller.text;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AppRichTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _detachOwnedFocusNode();
      _attachFocusNode();
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      _lastKnownText = widget.controller.text;
      widget.controller.addListener(_handleControllerChanged);
      _cancelAiFormat();
      _aiFormatting = false;
    }
  }

  @override
  void dispose() {
    _cancelAiFormat();
    widget.controller.removeListener(_handleControllerChanged);
    _detachOwnedFocusNode();
    super.dispose();
  }

  void _attachFocusNode() {
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
      return;
    }
    _ownedFocusNode = FocusNode();
    _focusNode = _ownedFocusNode!;
  }

  void _detachOwnedFocusNode() {
    _ownedFocusNode?.dispose();
    _ownedFocusNode = null;
  }

  void _handleControllerChanged() {
    final String next = widget.controller.text;
    final bool textChanged = next != _lastKnownText;
    _lastKnownText = next;
    if (!textChanged) {
      return;
    }
    // Do not cancel in-flight AI format on text notifications. Spurious
    // controller updates during toolbar rebuilds were aborting requests; the
    // completion path already refuses to overwrite when baseline changed.
    if (!_aiFormatting && mounted) {
      setState(() {});
    }
  }

  void _cancelAiFormat() {
    _aiAbort?.abort();
    _aiAbort = null;
  }

  void _applyWrap({required String prefix, required String suffix}) {
    AppRichTextMarkup.wrapSelection(
      widget.controller,
      prefix: prefix,
      suffix: suffix,
    );
    widget.onChanged?.call(widget.controller.text);
    _focusNode.requestFocus();
    setState(() {});
  }

  void _applyLinePrefix(String prefix, {bool numbered = false}) {
    AppRichTextMarkup.toggleLinePrefix(
      widget.controller,
      prefix: prefix,
      numbered: numbered,
    );
    widget.onChanged?.call(widget.controller.text);
    _focusNode.requestFocus();
    setState(() {});
  }

  Future<void> _formatWithAi() async {
    final AppLocalizations l10n = context.l10n;
    final String source = widget.controller.text.trim();
    if (!widget.enabled || _aiFormatting || source.isEmpty) {
      return;
    }

    final AsyncValue<AppConnectivityStatus> connectivity = ref.read(
      appConnectivityStatusProvider,
    );
    final bool online = connectivity.maybeWhen(
      data: (AppConnectivityStatus status) => status.isOnline,
      orElse: () => true,
    );
    if (!online) {
      setState(() {
        _aiFeedbackTitle = l10n.commonAiFormatOfflineTitle;
        _aiFeedback = l10n.commonAiFormatOfflineMessage;
        _aiFeedbackVariant = AppFormInformationVariant.warning;
      });
      return;
    }

    final AppClinicalNoteAiFormatter? formatter =
        widget.aiFormatter ?? ref.read(aiClinicalNoteFormatterProvider);
    if (formatter == null) {
      setState(() {
        _aiFeedbackTitle = l10n.commonAiFormatUnavailableTitle;
        _aiFeedback = l10n.commonAiFormatUnavailableMessage;
        _aiFeedbackVariant = AppFormInformationVariant.warning;
      });
      return;
    }

    final String baseline = widget.controller.text;
    final AppSpeechAiAbort abort = AppSpeechAiAbort();
    _cancelAiFormat();
    _aiAbort = abort;
    setState(() {
      _aiFormatting = true;
      _aiFeedbackTitle = null;
      _aiFeedback = null;
    });

    final AppClinicalNoteAiFormatResult outcome = await formatter(
      text: source,
      abort: abort,
      hint: widget.aiFormatHint ?? l10n.commonAiFormatHint,
    );

    if (!mounted) {
      return;
    }

    final bool stillOwned = identical(_aiAbort, abort);
    setState(() {
      if (stillOwned) {
        _aiFormatting = false;
        _aiAbort = null;
      }
    });

    final String? formatted = outcome.text;
    if (!stillOwned || formatted == null || formatted.trim().isEmpty) {
      if (stillOwned) {
        final AppFailure? failure = outcome.failure;
        setState(() {
          if (failure != null) {
            _aiFeedbackTitle = l10n.failureTitle(failure);
            _aiFeedback = l10n.failureMessage(failure);
            _aiFeedbackVariant = failure.category == AppFailureCategory.timeout
                ? AppFormInformationVariant.error
                : AppFormInformationVariant.warning;
          } else {
            _aiFeedbackTitle = l10n.commonAiFormatUnavailableTitle;
            _aiFeedback = l10n.commonAiFormatUnavailableMessage;
            _aiFeedbackVariant = AppFormInformationVariant.warning;
          }
        });
      }
      return;
    }

    // Do not overwrite if the user edited while the request was in flight.
    if (widget.controller.text != baseline) {
      return;
    }

    final String next = formatted.trim();
    _lastKnownText = next;
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    widget.onChanged?.call(next);
    setState(() {
      _aiFeedbackTitle = l10n.commonAiFormatSuccessTitle;
      _aiFeedback = l10n.commonAiFormatSuccessMessage;
      _aiFeedbackVariant = AppFormInformationVariant.success;
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Widget? label = appFieldLabelWidget(
      context,
      widget.labelText,
      isRequired: widget.isRequired,
      style: theme.textTheme.labelLarge,
    );
    final bool showToolbar =
        widget.showToolbar && widget.tools.isNotEmpty && widget.enabled;
    final Color borderColor = widget.errorText != null
        ? colors.error
        : theme.borders.inputIdle;
    final OutlineInputBorder fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: theme.borders.side(color: borderColor),
    );
    final List<Widget> toolbarItems = <Widget>[
      if (widget.tools.contains(AppRichTextTool.bold))
        _RichTextToolButton(
          tooltip: l10n.commonFormatBoldLabel,
          icon: Icons.format_bold,
          enabled: widget.enabled,
          onPressed: () => _applyWrap(
            prefix: AppRichTextMarkup.boldMarker,
            suffix: AppRichTextMarkup.boldMarker,
          ),
        ),
      if (widget.tools.contains(AppRichTextTool.italic))
        _RichTextToolButton(
          tooltip: l10n.commonFormatItalicLabel,
          icon: Icons.format_italic,
          enabled: widget.enabled,
          onPressed: () => _applyWrap(
            prefix: AppRichTextMarkup.italicMarker,
            suffix: AppRichTextMarkup.italicMarker,
          ),
        ),
      if (widget.tools.contains(AppRichTextTool.underline))
        _RichTextToolButton(
          tooltip: l10n.commonFormatUnderlineLabel,
          icon: Icons.format_underline,
          enabled: widget.enabled,
          onPressed: () => _applyWrap(
            prefix: AppRichTextMarkup.underlineMarker,
            suffix: AppRichTextMarkup.underlineMarker,
          ),
        ),
      if (widget.tools.contains(AppRichTextTool.bulletList) ||
          widget.tools.contains(AppRichTextTool.numberedList))
        SizedBox(
          height: 24,
          child: VerticalDivider(
            width: theme.spacing.md,
            color: theme.borders.faint,
          ),
        ),
      if (widget.tools.contains(AppRichTextTool.bulletList))
        _RichTextToolButton(
          tooltip: l10n.commonFormatBulletListLabel,
          icon: Icons.format_list_bulleted,
          enabled: widget.enabled,
          onPressed: () => _applyLinePrefix('- '),
        ),
      if (widget.tools.contains(AppRichTextTool.numberedList))
        _RichTextToolButton(
          tooltip: l10n.commonFormatNumberedListLabel,
          icon: Icons.format_list_numbered,
          enabled: widget.enabled,
          onPressed: () => _applyLinePrefix('1. ', numbered: true),
        ),
    ];
    final bool showSpeech = widget.enableSpeechToText;
    final bool showAiFormat = widget.enableAiFormat;
    final bool showToolbarRow = showToolbar || showSpeech || showAiFormat;
    final bool hasNoteText = widget.controller.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (label != null) ...<Widget>[
          label,
          SizedBox(height: theme.spacing.xs),
        ],
        if (showToolbarRow) ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(
                    horizontal: theme.spacing.xs,
                    vertical: theme.spacing.xs / 2,
                  ),
                  child: Row(children: toolbarItems),
                ),
              ),
              if (showAiFormat)
                _RichTextToolButton(
                  tooltip: _aiFormatting
                      ? l10n.commonAiFormatBusyTooltip
                      : l10n.commonAiFormatTooltip,
                  icon: Icons.auto_awesome,
                  enabled:
                      widget.enabled && !_aiFormatting && hasNoteText,
                  busy: _aiFormatting,
                  onPressed: _formatWithAi,
                ),
              if (showSpeech)
                AppSpeechToTextButton(
                  controller: widget.controller,
                  enabled: widget.enabled && !_aiFormatting,
                  dense: true,
                  transcriptTransform: appSpeechTextTranscript,
                  aiFormatMode: 'text',
                  longForm: true,
                  onChanged: widget.onChanged,
                ),
            ],
          ),
          Divider(height: 1, color: theme.borders.faint),
          SizedBox(height: theme.spacing.xs),
        ],
        if (_aiFormatting ||
            (_aiFeedback != null && _aiFeedback!.trim().isNotEmpty)) ...<
          Widget
        >[
          AppFormInformationBanner(
            title: _aiFormatting
                ? l10n.commonAiFormatBusyTitle
                : (_aiFeedbackTitle ?? l10n.commonAiFormatUnavailableTitle),
            message: _aiFormatting
                ? l10n.commonAiFormatBusyMessage
                : _aiFeedback!,
            variant: _aiFormatting
                ? AppFormInformationVariant.info
                : _aiFeedbackVariant,
            icon: _aiFormatting ? Icons.auto_awesome : null,
            borderRadius: BorderRadius.zero,
          ),
          SizedBox(height: theme.spacing.sm),
        ],
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colors.onSurface,
            fontWeight: AppFontWeight.regular,
            fontSize: 16,
            height: 1.5,
          ),
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            isDense: true,
            filled: false,
            contentPadding: EdgeInsets.symmetric(
              horizontal: theme.spacing.sm,
              vertical: theme.spacing.sm,
            ),
            hintText: widget.hintText,
            hintStyle: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: AppFontWeight.label,
              fontSize: 16,
              height: 1.5,
            ),
            border: fieldBorder,
            enabledBorder: fieldBorder,
            disabledBorder: fieldBorder.copyWith(
              borderSide: theme.borders.side(tone: AppBorderTone.disabled),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: theme.borders.side(
                tone: widget.errorText != null
                    ? AppBorderTone.error
                    : AppBorderTone.focused,
                weight: AppBorderWeight.medium,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: theme.borders.side(color: colors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: theme.borders.side(
                tone: AppBorderTone.error,
                weight: AppBorderWeight.medium,
              ),
            ),
          ),
          validator:
              widget.validator ??
              (widget.isRequired
                  ? AppValidators.requiredText(l10n.validationRequired)
                  : null),
        ),
        if (widget.errorText != null && widget.errorText!.trim().isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: theme.spacing.xs),
            child: Text(
              widget.errorText!,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          )
        else if (widget.helperText != null &&
            widget.helperText!.trim().isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: theme.spacing.xs),
            child: Text(
              widget.helperText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _RichTextToolButton extends StatelessWidget {
  const _RichTextToolButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.busy = false,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return IconButton(
      tooltip: tooltip,
      icon: busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            )
          : Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
      onPressed: enabled && !busy ? onPressed : null,
    );
  }
}
