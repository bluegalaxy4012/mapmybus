import 'package:flutter/material.dart';
import 'package:mapmybus/utils.dart';

void showSimpleSnackbar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();

  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: snackBarDuration,
      showCloseIcon: true,
    ),
  );
}
