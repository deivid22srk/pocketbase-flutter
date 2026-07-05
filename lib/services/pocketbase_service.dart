import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Estado do servidor PocketBase.
enum ServerStatus { stopped, starting, running, error }

/// Modelo de configuração persistido entre sessões.
class PocketBaseConfig {
  String hostname;
  String port;
  String adminEmail;
  String adminPassword;

  PocketBaseConfig({
    this.hostname = '0.0.0.0',
    this.port = '8090',
    this.adminEmail = 'admin@example.com',
    this.adminPassword = '',
  });

  String get listenAddr => '$hostname:$port';
  String get adminUrl {
    final host = hostname == '0.0.0.0' ? '127.0.0.1' : hostname;
    return 'http://$host:$port/_/';
  }

  String get apiUrl {
    final host = hostname == '0.0.0.0' ? '127.0.0.1' : hostname;
    return 'http://$host:$port/api/';
  }

  Map<String, dynamic> toMap() => {
        'hostname': hostname,
        'port': port,
        'adminEmail': adminEmail,
        'adminPassword': adminPassword,
      };

  factory PocketBaseConfig.fromMap(Map<String, dynamic> m) => PocketBaseConfig(
        hostname: m['hostname'] as String? ?? '0.0.0.0',
        port: m['port'] as String? ?? '8090',
        adminEmail: m['adminEmail'] as String? ?? 'admin@example.com',
        adminPassword: m['adminPassword'] as String? ?? '',
      );
}

/// Serviço que inicia/para o binário oficial do PocketBase (pré-compilado,
/// empacotado dentro do APK como `libpocketbase.so`).
///
/// O Flutter fala com o servidor via HTTP em localhost — exatamente como
/// o PocketBase foi projetado para funcionar. Sem gomobile, sem restrições
/// de tipos.
class PocketBaseService {
  static const _channel = MethodChannel('app.pocketbase/native');

  static final PocketBaseService _instance = PocketBaseService._();
  factory PocketBaseService() => _instance;
  PocketBaseService._();

  final _statusController = StreamController<ServerStatus>.broadcast();
  final _logController = StreamController<String>.broadcast();

  Stream<ServerStatus> get statusStream => _statusController.stream;
  Stream<String> get logStream => _logController.stream;

  ServerStatus _status = ServerStatus.stopped;
  ServerStatus get status => _status;

  Process? _process;
  String? _binaryPath;
  String _cachedVersion = '';

  void _setStatus(ServerStatus s) {
    _status = s;
    _statusController.add(s);
  }

  void _log(String line) {
    _logController.add('$line\n');
  }

  /// Resolve o caminho do binário dentro do diretório de native libs
  /// extraído do APK (/data/app/<pkg>/lib/<abi>/libpocketbase.so).
  Future<String> _resolveBinary() async {
    if (_binaryPath != null) return _binaryPath!;
    final nativeLibDir =
        await _channel.invokeMethod<String>('getNativeLibraryDir');
    _binaryPath = '$nativeLibDir/libpocketbase.so';
    return _binaryPath!;
  }

  /// Inicia o servidor PocketBase.
  Future<String?> start({
    required String dataDir,
    required PocketBaseConfig config,
  }) async {
    if (_status == ServerStatus.running) return 'already running';

    _setStatus(ServerStatus.starting);
    _log('[flutter] starting PocketBase...');

    final List<String> stderrBuffer = [];
    final List<String> stdoutBuffer = [];

    try {
      final binary = await _resolveBinary();
      _log('[flutter] binary: $binary');

      // 1. Verify the binary exists and is executable
      final binFile = File(binary);
      if (!await binFile.exists()) {
        _setStatus(ServerStatus.error);
        return 'Binary not found at $binary';
      }

      // 2. Pre-flight check: run --version to confirm the binary actually
      //    executes on this device (catches permission / ABI / page-size
      //    issues early with a clear message).
      _log('[flutter] pre-flight: pocketbase --version');
      final versionResult = await Process.run(
        binary,
        ['--version'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 5));
      if (versionResult.exitCode != 0) {
        _setStatus(ServerStatus.error);
        final msg = 'Pre-flight --version failed (exit=${versionResult.exitCode}).\n'
            'stdout: ${versionResult.stdout}\n'
            'stderr: ${versionResult.stderr}';
        _log('[flutter] $msg');
        return msg;
      }
      _log('[pocketbase] ${versionResult.stdout.toString().trim()}');

      // 3. Create/upsert the superuser (admin) account.
      //    The superuser subcommand initialises the SQLite DB if needed.
      _log('[flutter] upserting superuser ${config.adminEmail}...');
      final adminResult = await Process.run(
        binary,
        [
          'superuser', 'upsert', config.adminEmail, config.adminPassword,
          '--dir', dataDir,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 15));
      if (adminResult.exitCode != 0) {
        _setStatus(ServerStatus.error);
        final err = (adminResult.stderr as String).trim();
        final out = (adminResult.stdout as String).trim();
        final msg = 'superuser upsert failed (exit=${adminResult.exitCode})\n'
            'stdout: $out\nstderr: $err';
        _log('[flutter] $msg');
        return msg;
      }
      _log('[pocketbase] superuser ready: ${config.adminEmail}');

      // 4. Start the HTTP server.
      //    IMPORTANT: PocketBase v0.23+ renamed --listen → --http.
      //    Using --listen will cause the process to print "unknown flag"
      //    and exit immediately.
      _log('[flutter] launching: serve --http=${config.listenAddr} --dir=$dataDir');
      _process = await Process.start(
        binary,
        [
          'serve',
          '--http', config.listenAddr,
          '--dir', dataDir,
        ],
        workingDirectory: dataDir,
      );

      // 5. Pipe stdout / stderr into the log stream + buffers for diagnostics
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stdoutBuffer.add(line);
        _log('[pocketbase] $line');
      });
      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stderrBuffer.add(line);
        _log('[pocketbase:err] $line');
      });

      // 6. Monitor process exit
      bool exited = false;
      int exitCode = -1;
      _process!.exitCode.then((code) {
        exited = true;
        exitCode = code;
        _log('[flutter] PocketBase exited with code $code');
        if (_status == ServerStatus.running ||
            _status == ServerStatus.starting) {
          _setStatus(ServerStatus.stopped);
        }
        _process = null;
      });

      // 7. Poll for up to 4 seconds: either the process stays alive
      //    (success) or it exits (failure → we report exit code + stderr).
      for (int i = 0; i < 40; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (exited) break;
      }

      if (!exited) {
        _setStatus(ServerStatus.running);
        _log('[flutter] server is up at ${config.listenAddr}');
        return null; // success
      } else {
        _setStatus(ServerStatus.error);
        // Give the streams a moment to flush
        await Future.delayed(const Duration(milliseconds: 200));
        final stderrOut = stderrBuffer.join('\n').trim();
        final stdoutOut = stdoutBuffer.join('\n').trim();
        final msg = StringBuffer('PocketBase exited during startup (code=$exitCode).');
        if (stdoutOut.isNotEmpty) msg.writeln('\n--- stdout ---\n$stdoutOut');
        if (stderrOut.isNotEmpty) msg.writeln('\n--- stderr ---\n$stderrOut');
        if (stdoutOut.isEmpty && stderrOut.isEmpty) {
          msg.writeln('\n(no output — possible permission/page-size issue)');
        }
        return msg.toString();
      }
    } catch (e, st) {
      _setStatus(ServerStatus.error);
      _log('[flutter] exception: $e');
      _log('[flutter] stack: $st');
      return 'Exception: $e';
    }
  }

  /// Para o servidor graciosamente (SIGTERM).
  Future<String?> stop() async {
    try {
      final p = _process;
      if (p == null) {
        _setStatus(ServerStatus.stopped);
        return null;
      }
      _log('[flutter] stopping PocketBase...');
      p.kill(ProcessSignal.sigterm);
      final exited = await p.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          p.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      _log('[flutter] stopped (exit=$exited)');
      _process = null;
      _setStatus(ServerStatus.stopped);
      return null;
    } catch (e) {
      _setStatus(ServerStatus.error);
      return e.toString();
    }
  }

  Future<bool> isRunning() async =>
      _process != null && _status == ServerStatus.running;

  /// Versão embutida do PocketBase (lê de `--version`).
  Future<String> version() async {
    if (_cachedVersion.isNotEmpty) return _cachedVersion;
    try {
      final binary = await _resolveBinary();
      final result = await Process.run(binary, ['--version']);
      final out = (result.stdout as String).trim();
      final m = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(out);
      _cachedVersion = m?.group(1) ?? 'unknown';
    } catch (_) {
      _cachedVersion = 'unknown';
    }
    return _cachedVersion;
  }

  /// Caminho gravável dentro do sandbox do app.
  Future<String> resolveDataDir() async {
    try {
      return await _channel.invokeMethod<String>('getDataDir') ??
          '/data/local/tmp/pocketbase';
    } catch (_) {
      return Directory.systemTemp.path;
    }
  }

  void dispose() {
    _process?.kill(ProcessSignal.sigterm);
    _process = null;
    _statusController.close();
    _logController.close();
  }
}
