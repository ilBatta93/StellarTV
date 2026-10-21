import 'dart:convert';

enum DiagnosticProblem {
  stutter('Micro-scatti', 'Fotogrammi scartati, sincronizzazione audio/video e decodifica.'),
  buffer('Attese o blocchi', 'Buffer, durata delle attese e avvio.'),
  audio('Audio o immagine', 'Formato audio/video e dati del dispositivo.');
  final String label;
  final String check;
  const DiagnosticProblem(this.label, this.check);
}

String guidedDiagnosticReport(String original, DiagnosticProblem? problem) {
  if (problem == null) return original;
  return jsonEncode({'guide': {'v': 1, 'problem': problem.name}, 'report': jsonDecode(original)});
}