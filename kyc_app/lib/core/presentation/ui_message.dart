import 'package:equatable/equatable.dart';

/// One-shot message for a SnackBar. Every instance gets a unique [id] so that showing
/// the same text twice still triggers `BlocListener`.
class UiMessage extends Equatable {
  UiMessage.info(this.text)
      : isError = false,
        id = _nextId++;

  UiMessage.error(this.text)
      : isError = true,
        id = _nextId++;

  static int _nextId = 0;

  final int id;
  final String text;
  final bool isError;

  @override
  List<Object?> get props => [id, text, isError];
}
