import 'package:flutter/material.dart';
import 'package:tasks_example/nodus.g.dart';

/// Keeps Material feedback at the presentation boundary while Nodus owns the
/// generic busy/error lifecycle for the action itself.
EntityActionBinding useEntityActionFeedback(
  BuildContext context, {
  String failureMessage = 'Action failed',
}) => useEntityAction(
  onError: (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$failureMessage: $error')));
  },
);
