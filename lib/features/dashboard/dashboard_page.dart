import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/app.dart';
import '../../pages/radios_page.dart';
import '../batteries/batteries_page.dart';
import '../info/info_page.dart';
import '../maintenance/maintenance_page.dart';
import '../models/models_page.dart';
import '../sessions/sessions_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  void open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> logout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Déconnexion'),
          content: const Text(
            'Veux-tu vraiment te déconnecter de RC Companion ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(backgroundColor: RCColors.accent),
              child: const Text('Se déconnecter'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) return;

    try {
      await Supabase.instance.client.auth.signOut();
      if (!context.mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la déconnexion : $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = Supabase.instance.client.auth.currentUser?.email;
    final displayName = _displayName(userEmail);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/images/rc_companion_logo.png',
                width: 46,
                height: 46,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RC COMPANION'),
                Text(
                  'Gestionnaire RC',
                  style: TextStyle(
                    color: RCColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Informations & Références',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => open(context, const InfoPage()),
          ),
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => logout(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth >= 900 ? 32.0 : 16.0;
          final crossAxisCount = constraints.maxWidth >= 1100
              ? 4
              : constraints.maxWidth >= 700
                  ? 3
                  : 2;

          return ListView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              18,
              horizontalPadding,
              28,
            ),
            children: [
              _WelcomeHeader(
                displayName: displayName,
                email: userEmail,
              ),
              const SizedBox(height: 22),
              Text(
                'MON GARAGE RC',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: constraints.maxWidth >= 700 ? 1.25 : 0.95,
                children: [
                  DashboardCard(
                    icon: Icons.directions_car_filled_rounded,
                    iconColor: RCColors.primaryLight,
                    title: 'Mes modèles',
                    subtitle: 'Gère tes modèles et leurs setups',
                    onTap: () => open(context, const ModelsPage()),
                  ),
                  DashboardCard(
                    icon: Icons.battery_charging_full_rounded,
                    iconColor: RCColors.accent,
                    title: 'Mes batteries',
                    subtitle: 'Suivi, mesures et santé de tes packs',
                    onTap: () => open(context, const BatteriesPage()),
                  ),
                  DashboardCard(
                    icon: Icons.calendar_month_rounded,
                    iconColor: RCColors.primaryLight,
                    title: 'Mes sessions',
                    subtitle: 'Roulages, lieux et historiques',
                    onTap: () => open(context, const SessionsPage()),
                  ),
                  DashboardCard(
                    icon: Icons.build_circle_rounded,
                    iconColor: RCColors.success,
                    title: 'Maintenance',
                    subtitle: 'Révisions, réparations et modifications',
                    onTap: () => open(context, const MaintenancePage()),
                  ),
                  DashboardCard(
                    icon: Icons.settings_remote_rounded,
                    iconColor: RCColors.warning,
                    title: 'Mes radios',
                    subtitle: 'Catalogue et réglages radio',
                    onTap: () => open(context, const RadiosPage()),
                  ),
                  DashboardCard(
                    icon: Icons.info_outline_rounded,
                    iconColor: RCColors.textSecondary,
                    title: 'Informations',
                    subtitle: 'Références, règles et avertissements',
                    onTap: () => open(context, const InfoPage()),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const _FeatureStrip(),
            ],
          );
        },
      ),
    );
  }

  String _displayName(String? email) {
    if (email == null || email.trim().isEmpty) return 'pilote';
    final raw = email.split('@').first.trim();
    if (raw.isEmpty) return 'pilote';
    return '${raw[0].toUpperCase()}${raw.substring(1)}';
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.displayName, required this.email});

  final String displayName;
  final String? email;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: RCColors.border),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF172C4E), RCColors.surface],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: RCColors.primary,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: RCColors.primary.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.sports_motorsports_rounded, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bonjour, $displayName !',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  email == null
                      ? 'Bienvenue dans ton garage RC.'
                      : 'Connecté avec $email',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: RCColors.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.bolt_rounded,
            color: RCColors.accent,
            size: 34,
          ),
        ],
      ),
    );
  }
}

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: iconColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(icon, color: iconColor, size: 27),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: RCColors.textSecondary,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: RCColors.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureStrip extends StatelessWidget {
  const _FeatureStrip();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 24,
          runSpacing: 18,
          alignment: WrapAlignment.spaceAround,
          children: const [
            _FeatureItem(
              icon: Icons.speed_rounded,
              title: 'Simple & rapide',
              subtitle: 'Les infos utiles en quelques secondes',
            ),
            _FeatureItem(
              icon: Icons.fact_check_outlined,
              title: 'Suivi complet',
              subtitle: 'Modèles, batteries, sessions et entretiens',
            ),
            _FeatureItem(
              icon: Icons.query_stats_rounded,
              title: 'Historique détaillé',
              subtitle: 'Suis l’évolution de ton matériel',
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 245,
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0x332563EB),
            child: Icon(icon, color: RCColors.primaryLight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: RCColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
