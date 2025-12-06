import 'package:flutter/material.dart';
import 'package:mapmybus/core/utils.dart';

void showSimpleSnackbar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: Colors.white),
      ),
      duration: Constants.snackBarDuration,
      showCloseIcon: true,
    ),
  );
}
