enum MultiViewLayout {
  automatic('Automatica'),
  grid('Griglia'),
  mainAndSide('Principale e laterali');

  const MultiViewLayout(this.label);
  final String label;

  static MultiViewLayout parse(String? value) => values.firstWhere(
    (layout) => layout.name == value,
    orElse: () => automatic,
  );

  int columns(int count) => switch (this) {
    automatic => count <= 1 ? 1 : 2,
    grid => count <= 1 ? 1 : 2,
    mainAndSide => count <= 1 ? 1 : 2,
  };
}
