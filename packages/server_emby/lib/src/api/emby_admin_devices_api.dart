import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

/// Emby keys devices by an internal number, which is [DeviceInfoDto.id] here.
/// The id the app reports is [DeviceInfoDto.reportedDeviceId].
class EmbyAdminDevicesApi implements AdminDevicesApi {
  final Dio _dio;

  EmbyAdminDevicesApi(this._dio);

  /// Emby's own user filter wants its internal user number, so [userId] is
  /// matched against the last user here.
  @override
  Future<List<DeviceInfoDto>> getDevices({String? userId}) async {
    final response = await _dio.get('/Devices');
    final items = (response.data as Map<String, dynamic>)['Items'] as List?;
    return [
      for (final e in items ?? const [])
        DeviceInfoDto.fromJson(e as Map<String, dynamic>),
    ].where((d) => userId == null || d.lastUserId == userId).toList();
  }

  @override
  Future<DeviceInfoDto> getDeviceInfo(String id) async {
    final response = await _dio.get(
      '/Devices/Info',
      queryParameters: {'Id': id},
    );
    return DeviceInfoDto.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<DeviceOptionsDto> getDeviceOptions(String id) async {
    final response = await _dio.get(
      '/Devices/Options',
      queryParameters: {'Id': id},
    );
    return DeviceOptionsDto.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> updateDeviceOptions(String id, DeviceOptionsDto options) async {
    await _dio.post(
      '/Devices/Options',
      queryParameters: {'Id': id},
      data: options.toJson(),
    );
  }

  @override
  Future<void> deleteDevice(String id) async {
    await _dio.delete('/Devices', queryParameters: {'Id': id});
  }
}
