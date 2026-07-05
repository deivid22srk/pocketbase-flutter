import 'package:flutter/material.dart';
import '../services/pocketbase_service.dart';
import '../theme/app_theme.dart';

/// Formulário de configuração do servidor.
class ConfigFormCard extends StatelessWidget {
  const ConfigFormCard({
    super.key,
    required this.config,
    required this.enabled,
    required this.onChanged,
  });

  final PocketBaseConfig config;
  final bool enabled;
  final ValueChanged<PocketBaseConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Configuração',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 16,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _field(
                    label: 'Hostname',
                    value: config.hostname,
                    hint: '0.0.0.0',
                    icon: Icons.dns_outlined,
                    onChanged: (v) => _emit(hostname: v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: _field(
                    label: 'Porta',
                    value: config.port,
                    hint: '8090',
                    icon: Icons.numbers,
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _emit(port: v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _field(
              label: 'Email do admin',
              value: config.adminEmail,
              hint: 'admin@example.com',
              icon: Icons.alternate_email,
              keyboardType: TextInputType.emailAddress,
              onChanged: (v) => _emit(adminEmail: v),
            ),
            const SizedBox(height: 14),
            _field(
              label: 'Senha do admin',
              value: config.adminPassword,
              hint: 'mín. 10 caracteres',
              icon: Icons.lock_outline,
              obscure: true,
              onChanged: (v) => _emit(adminPassword: v),
            ),
            const SizedBox(height: 10),
            const _HelperText(),
          ],
        ),
      ),
    );
  }

  void _emit({
    String? hostname,
    String? port,
    String? adminEmail,
    String? adminPassword,
  }) {
    onChanged(PocketBaseConfig(
      hostname: hostname ?? config.hostname,
      port: port ?? config.port,
      adminEmail: adminEmail ?? config.adminEmail,
      adminPassword: adminPassword ?? config.adminPassword,
    ));
  }

  Widget _field({
    required String label,
    required String value,
    required String hint,
    required IconData icon,
    required ValueChanged<String> onChanged,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      enabled: enabled,
      controller: TextEditingController(text: value)..selection =
          TextSelection.fromPosition(TextPosition(offset: value.length)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: AppTheme.textMuted),
        isDense: true,
      ),
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
      onChanged: onChanged,
    );
  }
}

class _HelperText extends StatelessWidget {
  const _HelperText();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCardLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Use 0.0.0.0 para escutar em todas as interfaces. '
              'O admin UI ficará disponível em /_ e a API em /api/.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
