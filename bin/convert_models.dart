import 'dart:convert';
import 'dart:io';

const _defaultInput = 'assets/source_models';
const _defaultOutput = 'assets/models/generated';
const _manifestFileName = '.stage_3d_generated_models.json';
const _sourceExtensions = {'.obj', '.fbx', '.dae', '.blend'};

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  try {
    final runner = _ConverterRunner(options);
    await runner.run();
  } on _UsageException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln('');
    _printUsage();
    exitCode = 64;
  } on _ToolException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}

void _printUsage() {
  stdout.writeln('''
Converts source 3D models into GLB files for Stage 3D runtime assets.

Usage:
  dart run stage_3d:convert_models
  dart run stage_3d:convert_models assets/source_models/tree.obj
  dart run stage_3d:convert_models --input assets/source_models --output assets/models/generated

Options:
  --input <path>       Source file or directory. Default: $_defaultInput
  --output <dir>      Generated GLB directory. Default: $_defaultOutput
  --converter <name>  auto, blender, or obj2gltf. Default: auto
  --blender <path>    Explicit Blender executable path.
  --clean             Remove stale GLB files from the previous manifest.
  --no-clean          Keep previously generated GLB files.
  --force             Convert even when the output GLB is newer.
  --dry-run           Print planned work without running converters.
  -h, --help          Show this help.

Notes:
  Blender supports OBJ, FBX, DAE, and BLEND sources.
  obj2gltf supports OBJ sources only and must be installed on PATH.
''');
}

final class _ConverterRunner {
  _ConverterRunner(this.options);

  final _Options options;

  Future<void> run() async {
    final input = FileSystemEntity.typeSync(options.inputPath);
    if (input == FileSystemEntityType.notFound) {
      throw _ToolException('Input path not found: ${options.inputPath}');
    }

    final inputDir = input == FileSystemEntityType.directory
        ? Directory(options.inputPath)
        : null;
    final sources = inputDir != null
        ? _findSources(inputDir)
        : [File(options.inputPath)];

    if (sources.isEmpty) {
      stdout.writeln(
        'No supported source models found in ${options.inputPath}.',
      );
      return;
    }

    final outputDir = Directory(options.outputDir);
    final previousManifest = await _Manifest.read(outputDir);
    final entries = <_ManifestEntry>[];

    if (!options.dryRun) {
      await outputDir.create(recursive: true);
    }

    for (final source in sources) {
      final extension = _extensionOf(source.path);
      if (!_sourceExtensions.contains(extension)) {
        throw _ToolException('Unsupported source model: ${source.path}');
      }

      final output = _outputFor(source, outputDir, inputDir);
      entries.add(
        _ManifestEntry(
          sourcePath: _relativePath(source.absolute.path),
          outputPath: _relativePath(output.absolute.path),
        ),
      );

      if (!options.force && !await _needsConversion(source, output)) {
        stdout.writeln('Up to date: ${_relativePath(output.path)}');
        continue;
      }

      stdout.writeln(
        'Converting ${_relativePath(source.path)} -> ${_relativePath(output.path)}',
      );
      if (options.dryRun) {
        continue;
      }

      await output.parent.create(recursive: true);
      await _convert(source, output);
    }

    if (options.clean) {
      await _cleanStaleOutputs(previousManifest, entries);
    }

    if (!options.dryRun) {
      await _Manifest(entries).write(outputDir);
    }

    stdout.writeln(
      'Done. Generated assets live in ${_relativePath(outputDir.path)}.',
    );
  }

  List<File> _findSources(Directory inputDir) {
    return inputDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => _sourceExtensions.contains(_extensionOf(file.path)))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  File _outputFor(File source, Directory outputDir, Directory? inputDir) {
    if (inputDir == null) {
      final stem = _fileStem(source.path);
      return File('${outputDir.path}${Platform.pathSeparator}$stem.glb');
    }

    final inputRoot = inputDir.absolute.path;
    final prefix = inputRoot.endsWith(Platform.pathSeparator)
        ? inputRoot
        : '$inputRoot${Platform.pathSeparator}';
    final sourcePath = source.absolute.path;
    final relativeSource = sourcePath.startsWith(prefix)
        ? sourcePath.substring(prefix.length)
        : _fileName(sourcePath);
    final relativeOutput = _replaceExtension(relativeSource, '.glb');
    return File('${outputDir.path}${Platform.pathSeparator}$relativeOutput');
  }

  Future<bool> _needsConversion(File source, File output) async {
    if (!await output.exists()) {
      return true;
    }
    final sourceModified = await source.lastModified();
    final outputModified = await output.lastModified();
    return sourceModified.isAfter(outputModified);
  }

  Future<void> _convert(File source, File output) async {
    final converter = await _resolveConverter(source);
    switch (converter.kind) {
      case _ConverterKind.blender:
        await _runBlender(converter.executable!, source, output);
      case _ConverterKind.obj2gltf:
        await _runObj2Gltf(converter.executable!, source, output);
    }
  }

  Future<_ResolvedConverter> _resolveConverter(File source) async {
    final requested = options.converter;
    if (requested == 'blender' || requested == 'auto') {
      final blender = options.blenderPath != null
          ? File(options.blenderPath!).absolute.path
          : _findExecutable('blender');
      if (blender != null) {
        return _ResolvedConverter(_ConverterKind.blender, blender);
      }
      if (requested == 'blender') {
        throw _ToolException(
          'Blender was not found. Install Blender, add it to PATH, or pass '
          '--blender <path>.',
        );
      }
    }

    if (_extensionOf(source.path) == '.obj' &&
        (requested == 'obj2gltf' || requested == 'auto')) {
      final obj2gltf = _findExecutable('obj2gltf');
      if (obj2gltf != null) {
        return _ResolvedConverter(_ConverterKind.obj2gltf, obj2gltf);
      }
      if (requested == 'obj2gltf') {
        throw _ToolException(
          'obj2gltf was not found on PATH. Install it globally or use '
          '--converter blender.',
        );
      }
    }

    throw _ToolException(
      'No converter found for ${source.path}. Install Blender or obj2gltf.',
    );
  }

  Future<void> _runBlender(String blender, File source, File output) async {
    final script = await _writeBlenderScript();
    try {
      final result = await Process.run(blender, [
        '--background',
        '--factory-startup',
        '--python',
        script.path,
        '--',
        source.absolute.path,
        output.absolute.path,
      ]);
      _throwIfFailed('Blender', result);
    } finally {
      final scriptDir = script.parent;
      if (await scriptDir.exists()) {
        await scriptDir.delete(recursive: true);
      }
    }
  }

  Future<File> _writeBlenderScript() async {
    final dir = await Directory.systemTemp.createTemp('stage_3d_blender_');
    final script = File('${dir.path}${Platform.pathSeparator}convert_model.py');
    await script.writeAsString(_blenderScript);
    return script;
  }

  Future<void> _runObj2Gltf(String obj2gltf, File source, File output) async {
    final result = await Process.run(obj2gltf, [
      '-i',
      source.absolute.path,
      '-o',
      output.absolute.path,
    ]);
    _throwIfFailed('obj2gltf', result);
  }

  void _throwIfFailed(String toolName, ProcessResult result) {
    if (result.exitCode == 0) {
      return;
    }
    throw _ToolException('''
$toolName failed with exit code ${result.exitCode}.

stdout:
${result.stdout}

stderr:
${result.stderr}
''');
  }

  Future<void> _cleanStaleOutputs(
    _Manifest previous,
    List<_ManifestEntry> currentEntries,
  ) async {
    final currentOutputs = currentEntries
        .map((entry) => entry.outputPath)
        .toSet();
    for (final entry in previous.entries) {
      if (currentOutputs.contains(entry.outputPath)) {
        continue;
      }
      final output = File(entry.outputPath);
      if (!await output.exists()) {
        continue;
      }
      if (_extensionOf(output.path) != '.glb') {
        continue;
      }
      stdout.writeln(
        'Removing stale generated model: ${_relativePath(output.path)}',
      );
      if (!options.dryRun) {
        await output.delete();
      }
    }
  }
}

final class _Options {
  const _Options({
    required this.inputPath,
    required this.outputDir,
    required this.converter,
    required this.clean,
    required this.force,
    required this.dryRun,
    required this.help,
    this.blenderPath,
  });

  final String inputPath;
  final String outputDir;
  final String converter;
  final bool clean;
  final bool force;
  final bool dryRun;
  final bool help;
  final String? blenderPath;

  static _Options parse(List<String> args) {
    var inputPath = _defaultInput;
    var outputDir = _defaultOutput;
    var converter = 'auto';
    var clean = true;
    var force = false;
    var dryRun = false;
    var help = false;
    String? blenderPath;
    final positional = <String>[];

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (arg == '-h' || arg == '--help') {
        help = true;
      } else if (arg == '--clean') {
        clean = true;
      } else if (arg == '--no-clean') {
        clean = false;
      } else if (arg == '--force') {
        force = true;
      } else if (arg == '--dry-run') {
        dryRun = true;
      } else if (arg.startsWith('--input=')) {
        inputPath = arg.substring('--input='.length);
      } else if (arg == '--input') {
        inputPath = _requireValue(args, index, arg);
        index += 1;
      } else if (arg.startsWith('--output=')) {
        outputDir = arg.substring('--output='.length);
      } else if (arg == '--output') {
        outputDir = _requireValue(args, index, arg);
        index += 1;
      } else if (arg.startsWith('--converter=')) {
        converter = arg.substring('--converter='.length);
      } else if (arg == '--converter') {
        converter = _requireValue(args, index, arg);
        index += 1;
      } else if (arg.startsWith('--blender=')) {
        blenderPath = arg.substring('--blender='.length);
      } else if (arg == '--blender') {
        blenderPath = _requireValue(args, index, arg);
        index += 1;
      } else if (arg.startsWith('-')) {
        throw _UsageException('Unknown option: $arg');
      } else {
        positional.add(arg);
      }
    }

    if (positional.length > 1) {
      throw _UsageException('Only one positional input path is supported.');
    }
    if (positional.isNotEmpty) {
      inputPath = positional.single;
    }
    if (!{'auto', 'blender', 'obj2gltf'}.contains(converter)) {
      throw _UsageException(
        'Unsupported converter "$converter". Use auto, blender, or obj2gltf.',
      );
    }

    return _Options(
      inputPath: inputPath,
      outputDir: outputDir,
      converter: converter,
      clean: clean,
      force: force,
      dryRun: dryRun,
      help: help,
      blenderPath: blenderPath,
    );
  }

  static String _requireValue(List<String> args, int index, String option) {
    final valueIndex = index + 1;
    if (valueIndex >= args.length || args[valueIndex].startsWith('-')) {
      throw _UsageException('$option requires a value.');
    }
    return args[valueIndex];
  }
}

final class _Manifest {
  const _Manifest(this.entries);

  final List<_ManifestEntry> entries;

  static Future<_Manifest> read(Directory outputDir) async {
    final file = File(
      '${outputDir.path}${Platform.pathSeparator}$_manifestFileName',
    );
    if (!await file.exists()) {
      return const _Manifest([]);
    }
    final content = await file.readAsString();
    final json = jsonDecode(content);
    if (json is! Map<String, Object?>) {
      return const _Manifest([]);
    }
    final entriesJson = json['entries'];
    if (entriesJson is! List<Object?>) {
      return const _Manifest([]);
    }
    return _Manifest(
      entriesJson
          .whereType<Map<String, Object?>>()
          .map(_ManifestEntry.fromJson)
          .toList(),
    );
  }

  Future<void> write(Directory outputDir) async {
    final file = File(
      '${outputDir.path}${Platform.pathSeparator}$_manifestFileName',
    );
    final json = const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'entries': entries.map((entry) => entry.toJson()).toList(),
    });
    await file.writeAsString('$json\n');
  }
}

final class _ManifestEntry {
  const _ManifestEntry({required this.sourcePath, required this.outputPath});

  final String sourcePath;
  final String outputPath;

  factory _ManifestEntry.fromJson(Map<String, Object?> json) {
    return _ManifestEntry(
      sourcePath: json['source'] as String? ?? '',
      outputPath: json['output'] as String? ?? '',
    );
  }

  Map<String, String> toJson() {
    return {'source': sourcePath, 'output': outputPath};
  }
}

enum _ConverterKind { blender, obj2gltf }

final class _ResolvedConverter {
  const _ResolvedConverter(this.kind, this.executable);

  final _ConverterKind kind;
  final String? executable;
}

final class _UsageException implements Exception {
  const _UsageException(this.message);

  final String message;
}

final class _ToolException implements Exception {
  const _ToolException(this.message);

  final String message;
}

String? _findExecutable(String name) {
  final candidates = <String>[];
  final isWindows = Platform.isWindows;
  final extensions = isWindows
      ? (Platform.environment['PATHEXT'] ?? '.EXE;.BAT;.CMD')
            .split(';')
            .where((ext) => ext.isNotEmpty)
            .toList()
      : [''];

  for (final dir in (Platform.environment['PATH'] ?? '').split(
    isWindows ? ';' : ':',
  )) {
    if (dir.isEmpty) {
      continue;
    }
    for (final ext in extensions) {
      candidates.add('$dir${Platform.pathSeparator}$name$ext');
    }
  }

  if (isWindows && name == 'blender') {
    final programFiles = Platform.environment['ProgramFiles'];
    if (programFiles != null) {
      candidates.add(
        '$programFiles${Platform.pathSeparator}Blender Foundation'
        '${Platform.pathSeparator}Blender 4.4${Platform.pathSeparator}blender.exe',
      );
      candidates.add(
        '$programFiles${Platform.pathSeparator}Blender Foundation'
        '${Platform.pathSeparator}Blender 4.3${Platform.pathSeparator}blender.exe',
      );
      candidates.add(
        '$programFiles${Platform.pathSeparator}Blender Foundation'
        '${Platform.pathSeparator}Blender 4.2${Platform.pathSeparator}blender.exe',
      );
    }
  }

  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

String _extensionOf(String path) {
  final name = _fileName(path);
  final dot = name.lastIndexOf('.');
  return dot == -1 ? '' : name.substring(dot).toLowerCase();
}

String _fileStem(String path) {
  final name = _fileName(path);
  final dot = name.lastIndexOf('.');
  return dot == -1 ? name : name.substring(0, dot);
}

String _replaceExtension(String path, String extension) {
  final separatorIndex = path.lastIndexOf(RegExp(r'[\\/]'));
  final dot = path.lastIndexOf('.');
  if (dot == -1 || dot < separatorIndex) {
    return '$path$extension';
  }
  return '${path.substring(0, dot)}$extension';
}

String _fileName(String path) {
  return path.split(RegExp(r'[\\/]')).last;
}

String _relativePath(String path) {
  final cwd = Directory.current.absolute.path;
  final absolute = FileSystemEntity.isDirectorySync(path)
      ? Directory(path).absolute.path
      : File(path).absolute.path;
  if (absolute == cwd) {
    return '.';
  }
  final prefix = cwd.endsWith(Platform.pathSeparator)
      ? cwd
      : '$cwd${Platform.pathSeparator}';
  if (absolute.startsWith(prefix)) {
    return absolute.substring(prefix.length);
  }
  return path;
}

const _blenderScript = r'''
import os
import sys
import bpy


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(2)


argv = sys.argv
if "--" not in argv:
    fail("Expected -- input output arguments.")

args = argv[argv.index("--") + 1:]
if len(args) != 2:
    fail("Expected input and output paths.")

input_path = os.path.abspath(args[0])
output_path = os.path.abspath(args[1])
ext = os.path.splitext(input_path)[1].lower()

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()

if ext == ".obj":
    if hasattr(bpy.ops.wm, "obj_import"):
        bpy.ops.wm.obj_import(filepath=input_path)
    else:
        bpy.ops.import_scene.obj(filepath=input_path)
elif ext == ".fbx":
    bpy.ops.import_scene.fbx(filepath=input_path)
elif ext == ".dae":
    bpy.ops.wm.collada_import(filepath=input_path)
elif ext == ".blend":
    bpy.ops.wm.open_mainfile(filepath=input_path)
else:
    fail("Unsupported source extension: " + ext)

os.makedirs(os.path.dirname(output_path), exist_ok=True)

bpy.ops.export_scene.gltf(
    filepath=output_path,
    export_format="GLB",
    path_mode="COPY",
    export_yup=True,
)
''';
