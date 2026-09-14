import 'dart:typed_data';

import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';

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

  /// Counts stored feedback. Platform owners and platform admins only.
  Future<Result<FeedbackSummary>> fetchFeedbackSummary();

  /// Stored feedback as `.xlsx` bytes, with dates on [utcOffsetMinutes].
  /// Platform owners and platform admins only.
  Future<Result<Uint8List>> downloadFeedbackExport({
    required int utcOffsetMinutes,
  });

  /// Clears stored feedback. Platform owners and platform admins only.
  Future<Result<FeedbackClearResult>> clearFeedback();
}
