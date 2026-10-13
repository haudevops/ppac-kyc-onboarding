import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

/// rxdart-based event transformers (same semantics as bloc_concurrency, plus debounce).

/// Ignore new events while one is being processed (e.g. double-tap on "Submit").
EventTransformer<E> droppable<E>() => (events, mapper) => events.exhaustMap(mapper);

/// Cancel the in-flight handler when a new event arrives (e.g. restart status polling).
EventTransformer<E> restartable<E>() => (events, mapper) => events.switchMap(mapper);

/// Wait until events stop for [duration], then handle only the latest (autosave while typing).
EventTransformer<E> debounceRestartable<E>(Duration duration) =>
    (events, mapper) => events.debounceTime(duration).switchMap(mapper);
