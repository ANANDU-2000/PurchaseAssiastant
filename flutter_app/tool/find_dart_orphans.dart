// Maintainer script: list lib/*.dart files with no import/export references from other lib/test files.
// Run from flutter_app: dart run tool/find_dart_orphans.dart
// ignore_for_file: avoid_print

import 'dart:io';

void main() {
  final root = Directory.current;
  if (!File('${root.path}/pubspec.yaml').existsSync()) {
    stderr.writeln('Run from flutter_app directory.');
    exit(1);
  }

  final dartFiles = <File>[];
  for (final dir in ['lib', 'test']) {
    final d = Directory('${root.path}/$dir');
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) {
        dartFiles.add(f);
      }
    }
  }

  final zeroRef = <String>[];
  for (final f in dartFiles) {
    final rel = f.path
        .replaceAll(r'\', '/')
        .split('/')
        .skipWhile((s) => s != 'lib' && s != 'test')
        .join('/');
    final base = f.uri.pathSegments.last;
    final stem = base.replaceAll('.dart', '');
    // Match import/export path segments containing this file name.
    final patterns = [
      RegExp("['\"][^'\"]*$base['\"]"),
      RegExp("['\"][^'\"]*$stem\\.dart['\"]"),
      RegExp('show\\s+\\w+.*$stem'),
    ];
    var externalRefs = 0;
    for (final other in dartFiles) {
      if (other.path == f.path) continue;
      final content = other.readAsStringSync();
      for (final p in patterns) {
        if (p.hasMatch(content)) {
          externalRefs++;
          break;
        }
      }
    }
    if (externalRefs == 0 && rel.startsWith('lib/')) {
      zeroRef.add(rel);
    }
  }

  zeroRef.sort();
  print('Zero external references (${zeroRef.length} lib files):');
  for (final p in zeroRef) {
    print('  $p');
  }
}
