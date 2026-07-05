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
    _logController.add('[flutter] starting PocketBase...\n');

    try {
      final binary = await _resolveBinary();

      // 1. Verify the binary exists and is executable
      final binFile = File(binary);
      if (!await binFile.exists()) {
        _setStatus(ServerStatus.error);
        return 'Binary not found at $binary';
      }

      // 2. Create/upsert the superuser (admin) account
      _logController.add('[flutter] upserting superuser ${config.adminEmail}...\n');
      final adminResult = await Process.run(
        binary,
        [
          'superuser', 'upsert', config.adminEmail, config.adminPassword,
          '--dir', dataDir,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (adminResult.exitCode != 0) {
        _setStatus(ServerStatus.error);
        final err = (adminResult.stderr as String).trim();
        _logController.add('[pocketbase] superuser error: $err\n');
        return 'Failed to create admin: ${err.isEmpty ? adminResult.stdout : err}';
      }
      _logController
          .add('[pocketbase] superuser ready: ${config.adminEmail}\n');

      // 3. Start the server
      _logController
          .add('[flutter] launching: serve --listen=${config.listenAddr} --dir=$dataDir\n');
      _process = await Process.start(
        binary,
        [
          'serve',
          '--listen', config.listenAddr,
          '--dir', dataDir,
        ],
        workingDirectory: dataDir,
      );

      // 4. Pipe stdout / stderr into the log stream
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _logController.add('$line\n'));
      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _logController.add('$line\n'));

      // 5. Monitor process exit
      _process!.exitCode.then((code) {
        _logController.add('[flutter] PocketBase exited with code $code\n');
        if (_status == ServerStatus.running || _status == ServerStatus.starting) {
          _setStatus(ServerStatus.stopped);
        }
        _process = null;
      });

      // 6. Give the server a moment to bind
      await Future.delayed(const Duration(milliseconds: 1200));

      // 7. Check if still alive
      if (_process != null) {
        _setStatus(ServerStatus.running);
        _logController.add('[flutter] server is up at ${config.listenAddr}\n');
        return null; // success
      } else {
        _setStatus(ServerStatus.error);
        return 'Server exited unexpectedly during startup';
      }
    } catch (e) {
      _setStatus(ServerStatus.error);
      _logController.add('[flutter] error: $e\n');
      return e.toString();
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
      _logController.add('[flutter] stopping PocketBase...\n');
      // SIGTERM → graceful shutdown; fall back to SIGKILL after 3s
      p.kill(ProcessSignal.sigterm);
      final exited = await p.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          p.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      _logController.add('[flutter] stopped (exit=$exited)\n');
      _process = null;
      _setStatus(ServerStatus.stopped);
      return null;
    } catch (e) {
      _setStatus(ServerStatus.error);
      return e.toString();
    }
  }

  Future<bool> isRunning() async => _process != null && _status == ServerStatus.running;

  /// Versão embutida do PocketBase (lê de `--version`).
  Future<String> version() async {
    if (_cachedVersion.isNotEmpty) return _cachedVersion;
    try {
      final binary = await _resolveBinary();
      final result = await Process.run(binary, ['--version']);
      final out = (result.stdout as String).trim();
      // "PocketBase version 0.39.5"  →  "0.39.5"
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
