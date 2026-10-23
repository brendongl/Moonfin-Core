import '../models/server_models.dart';

abstract class AdminUsersApi {
  Future<List<ServerUser>> getUsers({bool? isDisabled, bool? isHidden});
  Future<ServerUser> getUserById(String userId);
  Future<ServerUser> createUser(String name, String? password);
  Future<void> deleteUser(String userId);

  /// Posts [user], the whole UserDto as fetched with only edited keys changed.
  /// The server rewrites the user's Configuration from it.
  Future<void> updateUser(String userId, Map<String, dynamic> user);
  Future<void> updateUserPolicy(String userId, Map<String, dynamic> policy);

  /// [currentPassword] is checked when an admin changes their own password.
  Future<void> updateUserPassword(
    String userId, {
    String? currentPassword,
    String? newPassword,
    bool resetPassword = false,
  });

  /// The `/Channels` items (`Id`, `Name`, ...) for the access lists.
  Future<List<Map<String, dynamic>>> getChannels({bool? supportsMediaDeletion});
}
