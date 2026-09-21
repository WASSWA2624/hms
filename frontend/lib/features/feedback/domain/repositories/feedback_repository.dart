import 'dart:typed_data';

import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/shared/data/app_pagination.dart';

abstract interface class FeedbackRepository {
  /// Records feedback from any screen.
  ///
  /// With [signedIn] the session travels with the request, so the server
  /// attaches the submitter's account, tenant, facility, subscription, and
  /// roles. Without it the feedback is recorded anonymously.
  Future<Result<FeedbackReceipt>> submitFeedback(
    FeedbackSubmission submission, {
    required bool signedIn,
  });

  /// One page of stored feedback matching [filters], in [sort] order.
  /// Platform owners and platform admins only.
  Future<Result<AppPage<FeedbackRecord>>> fetchFeedbackPage({
    required FeedbackFilters filters,
    required AppPageRequest request,
    FeedbackSort sort,
  });

  /// Every value each filter can take under [filters], with record counts.
  /// Platform owners and platform admins only.
  Future<Result<FeedbackFacets>> fetchFeedbackFacets({
    required FeedbackFilters filters,
  });

  /// Stored feedback as `.zip` bytes — the workbook, the screenshots it
  /// describes, and the prompts generator — with dates on [utcOffsetMinutes].
  ///
  /// With [referenceIds] only those records are exported; without them every
  /// record matching [filters]. Platform owners and platform admins only.
  Future<Result<Uint8List>> downloadFeedbackExport({
    required int utcOffsetMinutes,
    Set<String> referenceIds,
    FeedbackFilters filters,
  });

  /// The screenshots attached to one record, oldest first, without their
  /// bytes. Platform owners and platform admins only.
  Future<Result<List<FeedbackStoredScreenshot>>> fetchFeedbackScreenshots({
    required String referenceId,
  });

  /// One stored screenshot's bytes, for review in the app. Never cached and
  /// never public. Platform owners and platform admins only.
  Future<Result<Uint8List>> fetchFeedbackScreenshotImage({
    required String referenceId,
    required String screenshotId,
  });

  /// Permanently deletes the feedback with these [referenceIds].
  /// Platform owners and platform admins only.
  Future<Result<FeedbackDeleteResult>> deleteFeedback({
    required Set<String> referenceIds,
  });

  /// Permanently deletes every stored feedback record matching [filters].
  /// Platform owners and platform admins only.
  Future<Result<FeedbackDeleteResult>> deleteMatchingFeedback({
    required FeedbackFilters filters,
  });
}
