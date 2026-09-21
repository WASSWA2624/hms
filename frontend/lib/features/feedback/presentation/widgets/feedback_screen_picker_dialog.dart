import 'package:flutter/material.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_screen_catalog.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';

/// Picks the screens a report applies to.
///
/// Only screens this account can open are listed, so nobody files feedback
/// against a workspace they cannot reach, and each one shows its route below
/// its name: two screens can read alike in a list and be quite different.
Future<List<FeedbackScreenReference>?> showFeedbackScreenPickerDialog({
  required BuildContext context,
  required List<FeedbackScreenChoice> choices,
  required List<FeedbackScreenReference> selected,
}) {
  return showAppDialog<List<FeedbackScreenReference>>(
    context: context,
    builder: (_) =>
        FeedbackScreenPickerDialog(choices: choices, selected: selected),
  );
}

class FeedbackScreenPickerDialog extends StatefulWidget {
  const FeedbackScreenPickerDialog({
    required this.choices,
    required this.selected,
    super.key,
  });

  static const Key searchFieldKey = ValueKey<String>(
    'feedback-screen-picker-search',
  );

  static Key optionKey(String routeName) =>
      ValueKey<String>('feedback-screen-picker-$routeName');

  final List<FeedbackScreenChoice> choices;
  final List<FeedbackScreenReference> selected;

  @override
  State<FeedbackScreenPickerDialog> createState() =>
      _FeedbackScreenPickerDialogState();
}

class _FeedbackScreenPickerDialogState
    extends State<FeedbackScreenPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  late final Map<String, FeedbackScreenReference> _picked =
      <String, FeedbackScreenReference>{
        for (final FeedbackScreenReference screen in widget.selected)
          screen.key: screen,
      };
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FeedbackScreenChoice> get _matches {
    final String query = _search.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.choices;
    }
    return widget.choices
        .where(
          (FeedbackScreenChoice choice) =>
              choice.label.toLowerCase().contains(query) ||
              (choice.screen.routeName ?? '').toLowerCase().contains(query) ||
              (choice.screen.routePath ?? '').toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;
    final List<FeedbackScreenChoice> matches = _matches;

    return AppDialog(
      title: Text(l10n.feedbackScreenPickerTitle),
      icon: const Icon(Icons.checklist_outlined),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTextField(
            key: FeedbackScreenPickerDialog.searchFieldKey,
            controller: _searchController,
            labelText: l10n.feedbackScreenPickerSearchLabel,
            prefixIcon: const Icon(Icons.search),
            textInputAction: TextInputAction.search,
            onChanged: (String value) => setState(() => _search = value),
          ),
          SizedBox(height: theme.spacing.sm),
          Text(
            l10n.feedbackScreenPickerSelectedLabel(_picked.length),
            style: theme.textTheme.bodySmall,
          ),
          SizedBox(height: theme.spacing.xs),
          Flexible(
            child: matches.isEmpty
                ? Padding(
                    padding: EdgeInsets.symmetric(vertical: theme.spacing.lg),
                    child: Text(
                      l10n.feedbackScreenPickerEmptyMessage,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: matches.length,
                    itemBuilder: (BuildContext context, int index) {
                      final FeedbackScreenChoice choice = matches[index];
                      return AppCheckboxField(
                        key: FeedbackScreenPickerDialog.optionKey(
                          choice.screen.routeName ?? '$index',
                        ),
                        title: choice.label,
                        subtitle: choice.screen.routePath,
                        value: _picked.containsKey(choice.screen.key),
                        onChanged: (bool checked) => _toggle(choice, checked),
                      );
                    },
                  ),
          ),
        ],
      ),
      actions: <Widget>[
        AppButton.close(
          label: l10n.commonCancelActionLabel,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        AppButton.primary(
          label: l10n.commonSelectActionLabel,
          leadingIcon: Icons.check,
          onPressed: () => Navigator.of(
            context,
          ).pop(_picked.values.toList(growable: false)),
        ),
      ],
    );
  }

  void _toggle(FeedbackScreenChoice choice, bool checked) {
    setState(() {
      if (checked) {
        _picked[choice.screen.key] = choice.screen;
      } else {
        _picked.remove(choice.screen.key);
      }
    });
  }
}
