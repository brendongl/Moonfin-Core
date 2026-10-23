abstract class AdminEnvironmentApi {
  Future<List<Map<String, dynamic>>> getDirectoryContents(
    String path, {
    bool? includeFiles,
    bool? includeDirectories,
  });
  /// [writable] also checks the server can write there. [isFile] true or
  /// false requires a file or a folder, null accepts either.
  Future<void> validatePath(String path, {bool writable = false, bool? isFile});
  Future<List<Map<String, dynamic>>> getDrives();
  Future<String?> getParentPath(String path);
}
