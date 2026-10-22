import 'package:flutter/material.dart';

import '../../services/provider_diagnosis.dart';
import '../settings_tiles.dart';

class ProviderCheckButton extends StatefulWidget {
  const ProviderCheckButton({
    super.key,
    this.playbackUrl,
    this.playbackFailed = false,
    this.automatic = false,
  });
  final String? playbackUrl;
  final bool playbackFailed;
  final bool automatic;
  @override
  State<ProviderCheckButton> createState() => _ProviderCheckButtonState();
}

class _ProviderCheckButtonState extends State<ProviderCheckButton> {
  bool _busy = false;
  ProviderDiagnosis? _result;
  @override
  void initState() {
    super.initState();
    if (widget.automatic) _check();
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await ProviderDiagnosisService.check(
      playbackUrl: widget.playbackUrl,
      playbackFailed: widget.playbackFailed,
    );
    if (mounted)
      setState(() {
        _result = result;
        _busy = false;
      });
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 440),
    child: tvSettingsRow(
      onPressed: _busy ? null : _check,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_result != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_result?.message ?? '', textAlign: TextAlign.center),
            ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _check,
            icon: Icon(
              _busy ? Icons.hourglass_top_rounded : Icons.network_check_rounded,
            ),
            label: Text(_busy ? 'Verifica in corso…' : 'Verifica servizio'),
          ),
        ],
      ),
    ),
  );
}
