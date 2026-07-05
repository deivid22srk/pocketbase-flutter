import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Visualizador de logs em tempo real.
class LogViewer extends StatelessWidget {
  const LogViewer({super.key, required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.terminal, size: 16, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text(
                  'Logs',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 14,
                      ),
                ),
                const Spacer(),
                if (logs.isNotEmpty)
                  Text(
                    '${logs.length} linhas',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 260),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: logs.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Sem logs ainda. Inicie o servidor para ver a saída.',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      reverse: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: logs
                            .map((l) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 1),
                                  child: Text(
                                    l,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11.5,
                                      color: _colorForLine(l),
                                      height: 1.45,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Color _colorForLine(String line) {
    final l = line.toLowerCase();
    if (l.contains('error') || l.contains('panic') || l.contains('fatal')) {
      return AppTheme.danger;
    }
    if (l.contains('warn')) return AppTheme.warning;
    if (l.contains('ready') || l.contains('started') || l.contains('boot')) {
      return AppTheme.success;
    }
    return AppTheme.textSecondary;
  }
}
