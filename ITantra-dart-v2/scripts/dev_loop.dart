import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  stdout.writeln('===========================================================');
  stdout.writeln('🚀 iTantra Fast Dev Loop: Windows Live Auto-Reload Runner');
  stdout.writeln('===========================================================');
  stdout.writeln('• Watching "lib/" for code changes');
  stdout.writeln('• UI / Widget changes   -> Auto HOT RELOAD  ("r")');
  stdout.writeln('• Schema / Main changes -> Auto HOT RESTART ("R")');
  stdout.writeln('• Keyboard shortcuts:');
  stdout.writeln('    r: Manual Hot Reload');
  stdout.writeln('    R: Manual Hot Restart');
  stdout.writeln('    h: Help');
  stdout.writeln('    q: Quit');
  stdout.writeln('===========================================================\n');

  final flutterCmd = Platform.isWindows ? 'flutter.bat' : 'flutter';

  Process proc;
  try {
    proc = await Process.start(
      flutterCmd,
      ['run', '-d', 'windows', ...args],
      mode: ProcessStartMode.normal,
    );
  } catch (e) {
    stderr.writeln('Failed to start Flutter: $e');
    exit(1);
  }

  // Stream output to console
  proc.stdout.transform(utf8.decoder).listen(stdout.write);
  proc.stderr.transform(utf8.decoder).listen(stderr.write);

  // Forward developer terminal keyboard inputs to Flutter
  StreamSubscription? stdinSub;
  try {
    stdin.lineMode = false;
    stdin.echoMode = false;
    stdinSub = stdin.listen((bytes) {
      proc.stdin.add(bytes);
    });
  } catch (_) {
    // Stdin redirection if interactive mode unsupported
  }

  // Watch the lib directory for code modifications
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('Error: lib/ directory not found.');
    exit(1);
  }

  Timer? debounceTimer;
  bool pendingRestart = false;
  String lastChangedFile = '';

  final watcher = libDir.watch(recursive: true);
  final watchSub = watcher.listen((event) {
    final path = event.path;
    if (!path.endsWith('.dart')) return;

    // Normalize path separators
    final normalized = path.replaceAll('\\', '/');

    // Structural changes that require Hot Restart (state/schema/entrypoint)
    final isStructural = normalized.contains('main.dart') ||
        normalized.contains('/entities/') ||
        normalized.contains('app_database.dart');

    if (isStructural) {
      pendingRestart = true;
    }
    lastChangedFile = normalized.split('/').last;

    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (pendingRestart) {
        stdout.writeln('\n[DevLoop] 🔄 Structural change in $lastChangedFile -> Triggering Hot Restart ("R")...');
        proc.stdin.writeln('R');
        pendingRestart = false;
      } else {
        stdout.writeln('\n[DevLoop] ⚡ Code change in $lastChangedFile -> Triggering Hot Reload ("r")...');
        proc.stdin.writeln('r');
      }
    });
  });

  final code = await proc.exitCode;
  debounceTimer?.cancel();
  await watchSub.cancel();
  await stdinSub?.cancel();
  exit(code);
}
