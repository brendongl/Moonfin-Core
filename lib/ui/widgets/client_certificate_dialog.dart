import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:server_core/server_core.dart';

import '../../auth/store/client_certificate_store.dart';
import '../../data/services/certificate_upload_server.dart';
import '../../data/services/client_certificate_service.dart';
import '../../l10n/app_localizations.dart';
import '../../util/pkcs12_decoder.dart';
import '../../util/platform_detection.dart';
import 'adaptive/adaptive_dialog.dart';
import 'overlay_sheet.dart';

/// Imports a client certificate for [host] and puts it to use right away.
/// Returns null if nothing was saved.
Future<StoredClientCertificate?> showClientCertificateDialog({
  required BuildContext context,
  required String host,
}) {
  return showFocusRestoringDialog<StoredClientCertificate>(
    context: context,
    builder: (_) =>
        _ClientCertificateDialog(host: normalizeCertificateHost(host)),
  );
}

class _ClientCertificateDialog extends StatefulWidget {
  const _ClientCertificateDialog({required this.host});

  final String host;

  @override
  State<_ClientCertificateDialog> createState() =>
      _ClientCertificateDialogState();
}

class _ClientCertificateDialogState extends State<_ClientCertificateDialog> {
  final _store = GetIt.instance<ClientCertificateStore>();
  final _password = TextEditingController();
  CertificateUploadServer? _upload;
  List<String> _uploadUrls = const [];
  String? _fileName;
  Uint8List? _file;
  Pkcs12Decoded? _decoded;
  String? _error;
  bool _busy = false;

  // TVs have no file picker, so a phone sends the file instead.
  bool get _fromPhone => PlatformDetection.isTV;

  @override
  void dispose() {
    _password.dispose();
    _upload?.close();
    super.dispose();
  }

  String _describe(AppLocalizations l10n, Pkcs12Exception error) =>
      error.error == Pkcs12Error.wrongPassword
      ? l10n.clientCertWrongPassword
      : l10n.clientCertDecodeFailed;

  Future<void> _pickFile() async {
    final l10n = AppLocalizations.of(context);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['p12', 'pfx'],
        withData: true,
      );
      final file = picked?.files.singleOrNull;
      if (file == null || !mounted) return;
      setState(() {
        _file = file.bytes;
        _fileName = file.name;
        _error = file.bytes == null ? l10n.clientCertNoFileData : null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = l10n.clientCertPickFailed);
    }
  }

  Future<void> _startUpload() async {
    final l10n = AppLocalizations.of(context);
    final upload = CertificateUploadServer(
      describeError: (error) => _describe(l10n, error),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await upload.start();
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final urls = [
        for (final interface in interfaces)
          for (final address in interface.addresses)
            if (_isPrivate(address.rawAddress))
              'http://${address.address}:${upload.port}${upload.path}',
      ];
      if (urls.isEmpty || !mounted) throw StateError('no LAN address');
      setState(() {
        _upload = upload;
        _uploadUrls = urls;
        _busy = false;
      });
      final decoded = await upload.received;
      if (mounted) setState(() => _decoded = decoded);
    } catch (_) {
      upload.close();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.clientCertUploadFailed;
        });
      }
    }
  }

  void _stopUpload() {
    _upload?.close();
    setState(() => _upload = null);
  }

  static bool _isPrivate(List<int> ip) =>
      ip[0] == 10 ||
      (ip[0] == 172 && ip[1] >= 16 && ip[1] <= 31) ||
      (ip[0] == 192 && ip[1] == 168);

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final Pkcs12Decoded decoded;
    try {
      decoded = _decoded ?? decodePkcs12(_file!, _password.text);
    } on Pkcs12Exception catch (e) {
      setState(() => _error = _describe(l10n, e));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final certificate = StoredClientCertificate(
      host: widget.host,
      chainPem: decoded.chainPem,
      keyPem: decoded.keyPem,
      subject: decoded.subject,
      notAfter: decoded.notAfter,
    );
    await _store.save(certificate);
    if (_store.consumeSecureStorageUnavailable()) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.clientCertNoSecureStorage;
        });
      }
      return;
    }
    await installClientCertificates(_store);
    if (mounted) Navigator.of(context).pop(certificate);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final decoded = _decoded;
    final upload = _upload;
    final canSave = !_busy && (decoded != null || _file != null);

    return AlertDialog.adaptive(
      title: Text(l10n.clientCertTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.clientCertHost(widget.host)),
              const SizedBox(height: 16),
              if (decoded != null) ...[
                Text('${l10n.clientCertSubject}: ${decoded.subject}'),
                Text(
                  l10n.clientCertExpires(
                    MaterialLocalizations.of(context)
                        .formatMediumDate(decoded.notAfter.toLocal()),
                  ),
                ),
              ] else if (_fromPhone) ...[
                if (upload == null)
                  FilledButton(
                    autofocus: true,
                    onPressed: _busy ? null : _startUpload,
                    child: Text(l10n.clientCertStartUpload),
                  )
                else ...[
                  // The dialog sizes itself from intrinsic widths, which the
                  // QR view's LayoutBuilder can't report.
                  Center(
                    child: SizedBox.square(
                      dimension: 180,
                      child: QrImageView(
                        data: _uploadUrls.first,
                        size: 180,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.clientCertUploadHint),
                  for (final url in _uploadUrls)
                    SelectableText(url, style: theme.textTheme.bodySmall),
                  TextButton(
                    autofocus: true,
                    onPressed: _stopUpload,
                    child: Text(l10n.clientCertStopUpload),
                  ),
                ],
              ] else ...[
                Row(
                  children: [
                    FilledButton(
                      autofocus: true,
                      onPressed: _busy ? null : _pickFile,
                      child: Text(l10n.clientCertChooseFile),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _fileName ?? '',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.clientCertPassword,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => canSave ? _save() : null,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        adaptiveDialogAction(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        adaptiveDialogAction(
          onPressed: canSave ? _save : null,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
