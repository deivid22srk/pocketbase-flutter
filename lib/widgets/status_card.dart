import 'package:flutter/material.dart';
import '../services/pocketbase_service.dart';
import '../theme/app_theme.dart';

/// Card de status que mostra se o servidor está parado/iniciando/rodando.
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.status,
    required this.listenAddr,
    required this.version,
    this.onOpenAdmin,
  });

  final ServerStatus status;
  final String listenAddr;
  final String version;
  final VoidCallback? onOpenAdmin;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(status);
    final label = _labelFor(status);
    final running = status == ServerStatus.running;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.5),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 17,
                      ),
                ),
                const Spacer(),
                if (running)
                  OutlinedButton.icon(
                    onPressed: onOpenAdmin,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Admin UI'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      side: const BorderSide(color: AppTheme.accent),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 14),
            _infoRow('Endereço', running ? listenAddr : '—'),
            const SizedBox(height: 8),
            _infoRow(
              'API',
              running ? 'http://${listenAddr.replaceAll('0.0.0.0', '127.0.0.1')}/api/' : '—',
              mono: true,
            ),
            const SizedBox(height: 8),
            _infoRow('Data', version.isEmpty ? '—' : 'PocketBase v$version'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String key, String value, {bool mono = false}) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            key,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }

  Color _colorFor(ServerStatus s) {
    switch (s) {
      case ServerStatus.running:
        return AppTheme.success;
      case ServerStatus.starting:
        return AppTheme.warning;
      case ServerStatus.error:
        return AppTheme.danger;
      case ServerStatus.stopped:
        return AppTheme.textMuted;
    }
  }

  String _labelFor(ServerStatus s) {
    switch (s) {
      case ServerStatus.running:
        return 'Servidor rodando';
      case ServerStatus.starting:
        return 'Iniciando servidor…';
      case ServerStatus.error:
        return 'Erro ao iniciar';
      case ServerStatus.stopped:
        return 'Servidor parado';
    }
  }
}
