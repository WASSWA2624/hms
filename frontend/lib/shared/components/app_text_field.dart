import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/shared/components/app_button.dart';
import 'package:hosspi_hms/shared/components/app_field_label.dart';
import 'package:hosspi_hms/shared/components/app_speech_to_text.dart';

class AppTextField extends StatefulWidget {
  const AppTextField({
    this.controller,
    this.initialValue,
    this.labelText,
    this.hintText,
    this.helperText,
    this.errorText,
    this.semanticLabel,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.autofillHints,
    this.validator,
    this.onChanged,
    this.onSaved,
    this.onFieldSubmitted,
    this.onFocusChanged,
    this.focusNode,
    this.autovalidateMode,
    this.restorationId,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.readOnly = false,
    this.isRequired = false,
    this.isLoading = false,
    this.obscureText = false,
    this.enableObscureTextToggle = false,
    this.showObscuredTextLabel,
    this.hideObscuredTextLabel,
    this.autofocus = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.useFloatingLabel = true,
    this.isDense = false,
    this.allowClear = false,
    this.enableSpeechToText,
    this.style,
    this.tooltip,
    super.key,
  }) : assert(
         controller == null || initialValue == null,
         'Provide either controller or initialValue, not both.',
       ),
       assert(
         !enableObscureTextToggle || obscureText,
         'Obscured text toggles are only valid when obscureText is true.',
       ),
       assert(
         !enableObscureTextToggle ||
             (showObscuredTextLabel != null && hideObscuredTextLabel != null),
         'Provide localized show and hide labels for password visibility.',
       );

  final TextEditingController? controller;
  final String? initialValue;
  final String? labelText;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final String? semanticLabel;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final FormFieldSetter<String>? onSaved;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<bool>? onFocusChanged;
  final FocusNode? focusNode;
  final AutovalidateMode? autovalidateMode;
  final String? restorationId;
  final int? maxLines;
  final int? minLines;
  final bool enabled;
  final bool readOnly;
  final bool isRequired;
  final bool isLoading;
  final bool obscureText;
  final bool enableObscureTextToggle;
  final String? showObscuredTextLabel;
  final String? hideObscuredTextLabel;
  final bool autofocus;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool useFloatingLabel;

  /// When true, uses dense input padding so the field can align with compact
  /// toolbar actions.
  final bool isDense;

  /// When true and a [controller] has text, shows a clear (X) suffix action.
  final bool allowClear;

  /// When null, speech is shown for editable fields and hidden only for
  /// passwords/[obscureText]. Set false to force hide, true to force show
  /// (still never on [obscureText]).
  final bool? enableSpeechToText;

  /// Optional input text style. Merged over the default field style so callers
  /// can tint the value (for example lab result interpretation colors).
  final TextStyle? style;
  final String? tooltip;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  late bool _obscureText;
  TextEditingController? _ownedController;

  bool get _speechEnabled => appSpeechToTextEnabledForField(
    enableSpeechToText: widget.enableSpeechToText,
    obscureText: widget.obscureText,
    keyboardType: widget.keyboardType,
  );

  String Function(String transcript) get _speechTranscriptTransform =>
      appSpeechTranscriptTransformForKeyboard(widget.keyboardType);

  TextEditingController? get _effectiveController =>
      widget.controller ?? _ownedController;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
    _attachFocusNode();
    _ensureSpeechController();
    _effectiveController?.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscureText != widget.obscureText) {
      _obscureText = widget.obscureText;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      _detachFocusNode();
      _attachFocusNode();
    }
    final TextEditingController? previous =
        oldWidget.controller ?? _ownedController;
    previous?.removeListener(_handleTextChanged);
    _ensureSpeechController();
    _effectiveController?.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    _effectiveController?.removeListener(_handleTextChanged);
    _ownedController?.dispose();
    _detachFocusNode();
    super.dispose();
  }

  void _ensureSpeechController() {
    if (widget.controller != null) {
      _ownedController?.dispose();
      _ownedController = null;
      return;
    }
    if (_speechEnabled && _ownedController == null) {
      _ownedController = TextEditingController(text: widget.initialValue);
    }
    if (!_speechEnabled && _ownedController != null) {
      _ownedController!.dispose();
      _ownedController = null;
    }
  }

  void _attachFocusNode() {
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  void _detachFocusNode() {
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
  }

  void _handleFocusChanged() {
    widget.onFocusChanged?.call(_focusNode.hasFocus);
  }

  void _handleTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _clearText() {
    final TextEditingController? controller = _effectiveController;
    if (controller == null) {
      return;
    }
    controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final InputDecorationThemeData inputTheme = theme.inputDecorationTheme;
    final bool canEdit =
        widget.enabled && !widget.isLoading && !widget.readOnly;
    final bool useRichLabel =
        !widget.useFloatingLabel &&
        AppFieldRequirementScope.shouldShowOptionalIndicator(context) &&
        !widget.isRequired &&
        (widget.labelText?.trim().isNotEmpty ?? false);
    final String? resolvedLabelText = widget.useFloatingLabel || useRichLabel
        ? null
        : appFieldLabel(widget.labelText, isRequired: widget.isRequired);
    final TextStyle fieldLabelStyle =
        inputTheme.labelStyle ??
        inputTheme.hintStyle ??
        theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: AppFontWeight.label,
        ) ??
        AppFontFamily.style(fontWeight: AppFontWeight.label);
    final TextStyle placeholderLabelStyle = fieldLabelStyle.copyWith(
      color:
          fieldLabelStyle.color ??
          inputTheme.hintStyle?.color ??
          theme.colorScheme.onSurfaceVariant,
      fontWeight: AppFontWeight.label,
    );
    final Widget? floatingLabel = widget.useFloatingLabel
        ? appFieldLabelWidget(
            context,
            widget.labelText,
            isRequired: widget.isRequired,
            style: placeholderLabelStyle,
          )
        : null;
    final TextEditingController? controller = _effectiveController;
    final Widget field = TextFormField(
      key: controller == null ? ValueKey<String?>(widget.initialValue) : null,
      controller: controller,
      initialValue: controller == null ? widget.initialValue : null,
      enabled: widget.enabled && !widget.isLoading,
      readOnly: widget.readOnly,
      obscureText: _obscureText,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      inputFormatters: widget.inputFormatters,
      autofillHints: widget.autofillHints,
      validator: widget.validator,
      forceErrorText: widget.errorText,
      onChanged: widget.onChanged,
      onSaved: widget.onSaved,
      onFieldSubmitted: widget.onFieldSubmitted,
      focusNode: _focusNode,
      autovalidateMode: widget.autovalidateMode,
      restorationId: widget.restorationId,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      minLines: widget.minLines,
      autofocus: widget.autofocus,
      autocorrect: widget.obscureText ? false : widget.autocorrect,
      enableSuggestions: widget.obscureText ? false : widget.enableSuggestions,
      style: theme.textTheme.bodyLarge
          ?.copyWith(
            color: canEdit
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withValues(alpha: 0.62),
            fontWeight: AppFontWeight.regular,
            fontSize: 16,
            height: 1.5,
          )
          .merge(widget.style),
      decoration: InputDecoration(
        isDense: widget.isDense,
        contentPadding: widget.isDense
            ? EdgeInsets.symmetric(
                horizontal: theme.spacing.sm,
                vertical: 10,
              )
            : null,
        // minHeight keeps dense fields aligned; avoid a fixed max height so
        // helper/error text can expand without crushing the input.
        constraints: widget.isDense
            ? const BoxConstraints(minHeight: 40)
            : null,
        label: floatingLabel,
        labelText: floatingLabel == null ? resolvedLabelText : null,
        floatingLabelBehavior: widget.useFloatingLabel
            ? FloatingLabelBehavior.auto
            : FloatingLabelBehavior.never,
        hintText: widget.hintText,
        helperText: widget.helperText,
        prefixIcon: widget.prefixIcon,
        suffixIcon: _buildSuffixIcon(context, canEdit, controller),
      ),
    );

    Widget result = field;
    if (widget.semanticLabel != null) {
      result = Semantics(
        textField: true,
        enabled: canEdit,
        label: widget.semanticLabel,
        child: field,
      );
    }

    final Widget? externalLabel = widget.useFloatingLabel
        ? null
        : useRichLabel
        ? appFieldLabelWidget(
            context,
            widget.labelText,
            isRequired: widget.isRequired,
            style: placeholderLabelStyle,
          )
        : resolvedLabelText == null
        ? null
        : Text(
            resolvedLabelText,
            style: placeholderLabelStyle.copyWith(
              fontSize: 14,
              height: 1.2,
            ),
          );

    final Widget content = externalLabel == null
        ? result
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              externalLabel,
              SizedBox(height: theme.spacing.xs),
              result,
            ],
          );

    final String? resolvedTooltip = widget.tooltip;
    if (resolvedTooltip == null) {
      return content;
    }

    return Tooltip(message: resolvedTooltip, child: content);
  }

  Widget? _buildSuffixIcon(
    BuildContext context,
    bool canEdit,
    TextEditingController? controller,
  ) {
    final ThemeData theme = Theme.of(context);

    if (widget.isLoading) {
      return Padding(
        padding: EdgeInsets.all(theme.spacing.sm),
        child: SizedBox.square(
          dimension: theme.appTokens.listIconSize,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final bool showClear =
        widget.allowClear &&
        canEdit &&
        controller != null &&
        controller.text.isNotEmpty;
    final Widget? clearButton = showClear
        ? AppButton(
            key: const ValueKey<String>('app-text-field-clear'),
            iconOnly: true,
            dense: widget.isDense,
            leadingIcon: Icons.close,
            label: MaterialLocalizations.of(context).clearButtonTooltip,
            semanticLabel: MaterialLocalizations.of(
              context,
            ).clearButtonTooltip,
            tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
            onPressed: _clearText,
          )
        : null;

    // Keyed: the clear action appears as soon as dictation writes the first
    // word, and an unkeyed list would rebuild the speech button's element at
    // the new index, tearing down the in-flight listen session.
    final Widget? speechButton = _speechEnabled && controller != null
        ? AppSpeechToTextButton(
            key: const ValueKey<String>('app-text-field-speech'),
            controller: controller,
            enabled: canEdit,
            dense: widget.isDense,
            onChanged: widget.onChanged,
            transcriptTransform: _speechTranscriptTransform,
            aiFormatMode: appSpeechAiFormatModeForKeyboard(widget.keyboardType),
            longForm:
                widget.keyboardType == TextInputType.multiline ||
                (widget.maxLines ?? 2) > 1,
          )
        : null;

    final List<Widget> trailing = <Widget>[
      ?clearButton,
      ?speechButton,
    ];

    if (widget.enableObscureTextToggle) {
      final String label = _obscureText
          ? widget.showObscuredTextLabel!
          : widget.hideObscuredTextLabel!;
      final Widget toggle = AppButton(
        iconOnly: true,
        dense: widget.isDense,
        label: label,
        semanticLabel: label,
        tooltip: label,
        onPressed: canEdit
            ? () {
                setState(() {
                  _obscureText = !_obscureText;
                });
              }
            : null,
        icon: _obscureText
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
      );
      trailing.add(toggle);
    } else if (widget.suffixIcon != null) {
      trailing.add(widget.suffixIcon!);
    }

    if (trailing.isEmpty) {
      return null;
    }
    if (trailing.length == 1) {
      return trailing.first;
    }
    return Row(mainAxisSize: MainAxisSize.min, children: trailing);
  }
}
