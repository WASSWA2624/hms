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

  /// One page of stored feedback matching [filters], newest first.
  /// Platform owners and platform admins only.
  Future<Result<AppPage<FeedbackRecord>>> fetchFeedbackPage({
    required FeedbackFilters filters,
    required AppPageRequest request,
  });

  /// Stored feedback as `.xlsx` bytes, with dates on [utcOffsetMinutes].
  /// Platform owners and platform admins only.
  Future<Result<Uint8List>> downloadFeedbackExport({
    required int utcOffsetMinutes,
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
