import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/pocketbase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_card.dart';
import '../widgets/config_form.dart';
import '../widgets/log_viewer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PocketBaseService _service;
  final _config = PocketBaseConfig();
  String _dataDir = '';
  String _version = '';
  String _lastError = '';
  ServerStatus _status = ServerStatus.stopped;
  final List<String> _logs = [];
  StreamSubscription? _statusSub;
  StreamSubscription? _logSub;

  @override
  void initState() {
    super.initState();
    _service = PocketBaseService();
    _status = _service.status;
    _statusSub = _service.statusStream.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _logSub = _service.logStream.listen((chunk) {
      if (!mounted) return;
      setState(() {
        _logs.addAll(chunk.split('\n').where((l) => l.trim().isNotEmpty));
        if (_logs.length > 500) _logs.removeRange(0, _logs.length - 500);
      });
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('pb_config');
    if (stored != null) {
      // configurações persistidas (sem senha — nunca persistimos senha)
      final parts = stored.split('|');
      if (parts.length >= 3) {
        _config.hostname = parts[0];
        _config.port = parts[1];
        _config.adminEmail = parts[2];
      }
    }
    _dataDir = await _service.resolveDataDir();
    _version = await _service.version();
    if (mounted) setState(() {});
  }

  Future<void> _persistConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pb_config',
      '${_config.hostname}|${_config.port}|${_config.adminEmail}',
    );
  }

  Future<void> _toggleServer() async {
    if (_status == ServerStatus.running) {
      final err = await _service.stop();
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao parar: $err')),
        );
      }
      return;
    }
    if (_config.adminPassword.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A senha do admin deve ter pelo menos 10 caracteres.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    await _persistConfig();
    setState(() => _logs.clear());
    final err = await _service.start(
      dataDir: _dataDir,
      config: _config,
    );
    if (err != null && mounted) {
      setState(() => _lastError = err);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao iniciar: $err'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Servidor rodando em ${_config.listenAddr}'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Future<void> _openAdmin() async {
    final uri = Uri.parse(_config.adminUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o navegador.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _logSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = _status == ServerStatus.running;
    final starting = _status == ServerStatus.starting;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.bgDarkest, Color(0xFF13132B)],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    StatusCard(
                      status: _status,
                      listenAddr: _config.listenAddr,
                      version: _version,
                      onOpenAdmin: running ? _openAdmin : null,
                    ),
                    const SizedBox(height: 16),
                    ConfigFormCard(
                      config: _config,
                      enabled: !running && !starting,
                      onChanged: (c) => setState(() => _config
                        ..hostname = c.hostname
                        ..port = c.port
                        ..adminEmail = c.adminEmail
                        ..adminPassword = c.adminPassword),
                    ),
                    const SizedBox(height: 16),
                    _buildActionRow(running, starting),
                    const SizedBox(height: 16),
                    if (_lastError.isNotEmpty && _status == ServerStatus.error)
                      _buildErrorBanner(),
                    LogViewer(logs: _logs),
                    const SizedBox(height: 32),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, AppTheme.accent],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.storage, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PocketBase',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  'Servidor embutido · Android',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          if (_version.isNotEmpty)
            Chip(
              label: Text('v$_version'),
              backgroundColor: AppTheme.bgCard,
              side: const BorderSide(color: AppTheme.border),
              labelStyle: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionRow(bool running, bool starting) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: starting ? null : _toggleServer,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    running ? AppTheme.danger : AppTheme.primary,
                disabledBackgroundColor: AppTheme.bgCardLight,
              ),
              icon: starting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
              label: Text(starting
                  ? 'Iniciando…'
                  : running
                      ? 'Parar servidor'
                      : 'Iniciar servidor'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.danger.withOpacity(0.1),
        border: Border.all(color: AppTheme.danger.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _lastError,
              style: const TextStyle(color: AppTheme.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
