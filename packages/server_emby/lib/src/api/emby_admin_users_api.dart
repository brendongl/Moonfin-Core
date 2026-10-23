import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

class EmbyAdminUsersApi implements AdminUsersApi {
  final Dio _dio;

  EmbyAdminUsersApi(this._dio);

  @override
  Future<List<ServerUser>> getUsers({bool? isDisabled, bool? isHidden}) async {
    final response = await _dio.get(
      '/Users/Query',
      queryParameters: {'IsDisabled': ?isDisabled, 'IsHidden': ?isHidden},
    );
    final items = (response.data as Map<String, dynamic>)['Items'] as List?;
    return [
      for (final e in items ?? const [])
        ServerUser.fromJson(e as Map<String, dynamic>),
    ];
  }

  @override
  Future<ServerUser> getUserById(String userId) async {
    final response = await _dio.get('/Users/$userId');
    return ServerUser.fromJson(response.data as Map<String, dynamic>);
  }

  /// Emby creates the user without a password, so it's set afterwards.
  @override
  Future<ServerUser> createUser(String name, String? password) async {
    final response = await _dio.post('/Users/New', data: {'Name': name});
    final user = ServerUser.fromJson(response.data as Map<String, dynamic>);
    if (password == null || password.isEmpty) return user;
    await updateUserPassword(user.id, newPassword: password);
    return getUserById(user.id);
  }

  @override
  Future<void> deleteUser(String userId) async {
    await _dio.delete('/Users/$userId');
  }

  @override
  Future<void> updateUser(String userId, Map<String, dynamic> user) async {
    await _dio.post('/Users/$userId', data: user);
  }

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
  }) async {
    await _dio.post(
      '/Users/$userId/Password',
      data: {
        'CurrentPw': ?currentPassword,
        'NewPw': ?newPassword,
        'ResetPassword': resetPassword,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getChannels({
    bool? supportsMediaDeletion,
  }) async {
    final response = await _dio.get(
      '/Channels',
      queryParameters: {'SupportsMediaDeletion': ?supportsMediaDeletion},
    );
    final items = (response.data as Map<String, dynamic>)['Items'] as List?;
    return [for (final item in items ?? const []) item as Map<String, dynamic>];
  }
}
