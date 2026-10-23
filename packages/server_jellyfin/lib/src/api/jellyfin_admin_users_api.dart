import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

class JellyfinAdminUsersApi implements AdminUsersApi {
  final Dio _dio;

  JellyfinAdminUsersApi(this._dio);

  @override
  Future<List<ServerUser>> getUsers({bool? isDisabled, bool? isHidden}) async {
    final params = <String, dynamic>{};
    if (isDisabled != null) params['isDisabled'] = isDisabled;
    if (isHidden != null) params['isHidden'] = isHidden;
    final response = await _dio.get('/Users', queryParameters: params);
    return (response.data as List<dynamic>)
        .map((e) => ServerUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ServerUser> getUserById(String userId) async {
    final response = await _dio.get('/Users/$userId');
    return ServerUser.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<ServerUser> createUser(String name, String? password) async {
    final response = await _dio.post(
      '/Users/New',
      data: {
        'Name': name,
        'Password': ?password,
      },
    );
    return ServerUser.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> deleteUser(String userId) async {
    await _dio.delete('/Users/$userId');
  }

  @override
  Future<void> updateUser(String userId, Map<String, dynamic> user) =>
      _postWithLegacy('/Users', '/Users/$userId', userId, user);

  @override
  Future<void> updateUserPolicy(
    String userId,
    Map<String, dynamic> policy,
  ) async {
    await _dio.post('/Users/$userId/Policy', data: policy);
  }

  @override
  Future<void> updateUserPassword(
    String userId, {
    String? currentPassword,
    String? newPassword,
    bool resetPassword = false,
  }) =>
      _postWithLegacy('/Users/Password', '/Users/$userId/Password', userId, {
        'CurrentPw': ?currentPassword,
        'NewPw': ?newPassword,
        'ResetPassword': resetPassword,
      });

  @override
  Future<List<Map<String, dynamic>>> getChannels({
    bool? supportsMediaDeletion,
  }) async {
    final response = await _dio.get(
      '/Channels',
      queryParameters: {'supportsMediaDeletion': ?supportsMediaDeletion},
    );
    final items = (response.data as Map<String, dynamic>)['Items'] as List?;
    return [for (final item in items ?? const []) item as Map<String, dynamic>];
  }

  /// Posts to the `?userId=` route, falling back to the older `/Users/{id}`
  /// route for servers that only have that one.
  Future<void> _postWithLegacy(
    String path,
    String legacyPath,
    String userId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _dio.post(path, queryParameters: {'userId': userId}, data: data);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 400 || status == 404 || status == 405) {
        await _dio.post(legacyPath, data: data);
        return;
      }
      rethrow;
    }
  }
}
