import 'dart:async';

import 'package:dio/dio.dart';

import 'sipflix_4k_policy.dart';
import 'sipflix_servers.dart';

/// Safe support text for our servers. Never copies exception strings, response
/// bodies, request paths, credentials, or query parameters into the UI.
class SipflixErrorMessage {
  SipflixErrorMessage._();

  static String? describe(
    Object error, {
    String? serverRef,
    String operation = 'Request',
  }) {
    final requestUri = error is DioException ? error.requestOptions.uri : null;
    final explicit = _origin(serverRef) ?? serverRef;
    final requestOrigin = requestUri == null
        ? null
        : _origin(requestUri.toString());
    final server =
        (explicit == null ? null : SipflixServers.defForRef(explicit)) ??
        (requestOrigin == null
            ? null
            : SipflixServers.defForRef(requestOrigin));
    if (server == null) return null;
    final routeRef =
        requestOrigin != null &&
            SipflixServers.defForRef(requestOrigin)?.key == server.key
        ? requestOrigin
        : explicit;
    String route = 'saved route';
    for (final candidate in server.routes) {
      if (_origin(candidate.url) == routeRef) {
        route = candidate.label;
        break;
      }
    }
    const operations = {
      'Request',
      'Load library',
      'Load more titles',
      'Load favorites',
      'Search',
      'Load title',
      'Cast',
      'Download',
      'Sign in',
    };
    final action = operations.contains(operation) ? operation : 'Request';
    var code = 'UNKNOWN';
    var reason = 'could not complete';
    var next = 'Try again. If it keeps happening, message FlixBot.';
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status != null) {
        code = 'HTTP $status';
        reason = switch (status) {
          401 => 'needs a new sign-in',
          403 => 'was refused by the server',
          404 => 'could not find the requested item',
          429 => 'was rate limited',
          >= 500 => 'failed at the server',
          _ => 'was rejected by the server',
        };
        next = switch (status) {
          401 => 'Sign in again.',
          403 => 'Message FlixBot to check your access.',
          404 =>
            'Refresh and try again. If it is still missing, message FlixBot.',
          429 => 'Wait a moment, then try again.',
          >= 500 => 'Try again or switch connection route. If it persists, message FlixBot.',
          _ => next,
        };
      } else {
        switch (error.type) {
          case DioExceptionType.connectionTimeout:
          case DioExceptionType.sendTimeout:
          case DioExceptionType.receiveTimeout:
          case DioExceptionType.transformTimeout:
            code = 'TIMEOUT';
            reason = 'timed out';
            next = 'Try again or switch connection route.';
          case DioExceptionType.connectionError:
            code = 'NETWORK';
            reason = 'could not reach the server';
            next = 'Check your connection, then try again or switch route.';
          case DioExceptionType.badCertificate:
            code = 'TLS';
            reason = 'could not verify the secure connection';
            next = 'Check the device date and time. If it persists, message FlixBot.';
          case DioExceptionType.cancel:
            code = 'CANCELLED';
            reason = 'was cancelled';
            next = 'Try again.';
          case DioExceptionType.badResponse:
          case DioExceptionType.unknown:
            code = 'NETWORK';
            reason = 'could not complete the server request';
        }
      }
    } else if (error is TimeoutException) {
      code = 'TIMEOUT';
      reason = 'timed out';
      next = 'Try again or switch connection route.';
    } else if (error is FormatException) {
      code = 'INVALID_RESPONSE';
      reason = 'received an unreadable server response';
    } else if (error is StateError &&
        Sipflix4kPolicy.isRefusal(error.message.toString())) {
      code = 'VERSION_UNAVAILABLE';
      reason = 'cannot use this version';
      next = error.message.toString(); // Exact allowlisted policy strings only.
    }
    return '$action on ${server.name} via $route $reason ($code). $next';
  }

  static String? _origin(String? value) {
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
  }
}
