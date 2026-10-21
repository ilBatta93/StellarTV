import 'package:flutter/material.dart';
import '../models/diagnostic_guide.dart';
import 'settings_tiles.dart';
import 'tv_focusable.dart';

class DiagnosticGuideSection extends StatelessWidget {
  final DiagnosticProblem? selected;
  final ValueChanged<DiagnosticProblem?> onChanged;
  const DiagnosticGuideSection({super.key, required this.selected, required this.onChanged});
  @override
  Widget build(BuildContext context) => SettingsSection(title: 'Problema riscontrato', children: [
    for (final problem in DiagnosticProblem.values)
      TvFocusable(onPressed: () => onChanged(selected == problem ? null : problem), child: ListTile(
        leading: Icon(selected == problem ? Icons.radio_button_checked : Icons.radio_button_off),
        title: Text(problem.label), subtitle: Text(problem.check),
        onTap: () => onChanged(selected == problem ? null : problem),
      )),
    const Padding(padding: EdgeInsets.all(16), child: Text('Facoltativo. Il problema viene incluso solo nel rapporto che invii o esporti. Nessuna modifica automatica al lettore.')),
  ]);
}