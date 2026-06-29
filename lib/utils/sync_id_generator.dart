class SyncIdGenerator {
  static int _counter = 0;

  static int nextId() {
    _counter++;
    return DateTime.now().microsecondsSinceEpoch + _counter;
  }
}
