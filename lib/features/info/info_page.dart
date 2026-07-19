import 'package:flutter/material.dart';

class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  static const String appVersion = 'V1.0';
  static const String batteryHealthVersion = 'V1.0';
  static const String batteryCompatibilityVersion = 'V1.0';
  static const String lastUpdate = 'Juillet 2026';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Informations & Références'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _headerCard(context),
          const SizedBox(height: 16),
          _warningCard(context),
          const SizedBox(height: 16),
          _sectionCard(
            context,
            icon: Icons.battery_charging_full,
            title: 'Santé batterie',
            children: const [
              Text(
                'Les estimations de santé affichées par RC Companion '
                'sont actuellement basées sur :',
              ),
              SizedBox(height: 10),
              _InfoBullet('la tension de chaque cellule ;'),
              _InfoBullet('l’écart de tension entre les cellules ;'),
              _InfoBullet(
                'la résistance interne de chaque cellule relevée '
                'après charge ;',
              ),
              _InfoBullet(
                'l’évolution des résistances internes par rapport '
                'au relevé de référence ;',
              ),
              _InfoBullet(
                'la cohérence des valeurs entre les cellules du pack.',
              ),
              SizedBox(height: 12),
              Text(
                'Les résistances internes relevées après un roulage '
                'ne sont pas utilisées pour estimer la santé de la batterie.',
              ),
              SizedBox(height: 12),
              _VersionLine(
                label: 'Version de l’algorithme',
                value: batteryHealthVersion,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            context,
            icon: Icons.link,
            title: 'Compatibilité batteries',
            children: const [
              Text(
                'Les règles de compatibilité proposées par RC Companion '
                'constituent une aide à la sélection des batteries.',
              ),
              SizedBox(height: 10),
              Text(
                'Elles reposent notamment sur le nombre de cellules, '
                'la technologie, la capacité, le taux de décharge et '
                'la configuration du modèle.',
              ),
              SizedBox(height: 10),
              Text(
                'Elles ne remplacent pas les recommandations du fabricant '
                'du modèle, du variateur, du moteur, du chargeur ou '
                'de la batterie.',
              ),
              SizedBox(height: 12),
              _VersionLine(
                label: 'Version de l’algorithme',
                value: batteryCompatibilityVersion,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            context,
            icon: Icons.update,
            title: 'Évolution des calculs',
            children: const [
              Text(
                'Les règles, seuils et algorithmes utilisés par '
                'RC Companion sont susceptibles d’évoluer au fil des '
                'mises à jour afin d’améliorer la précision des analyses, '
                'l’ergonomie et la sécurité d’utilisation.',
              ),
              SizedBox(height: 10),
              Text(
                'Cette page sera mise à jour à chaque ajout ou modification '
                'd’un calcul, d’un seuil ou d’une règle de compatibilité.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(
              Icons.info_outline,
              size: 54,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 10),
            const Text(
              'RC Companion',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const _VersionLine(
              label: 'Version de l’application',
              value: appVersion,
            ),
            const _VersionLine(
              label: 'Dernière mise à jour',
              value: lastUpdate,
            ),
          ],
        ),
      ),
    );
  }

  Widget _warningCard(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;

    return Card(
      color: color.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: color, size: 30),
                const SizedBox(width: 10),
                Text(
                  'Avertissement important',
                  style: TextStyle(
                    color: color,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'RC Companion est un outil d’aide au suivi, à l’analyse '
              'et à la gestion des modèles radiocommandés, des batteries '
              'et des équipements associés.',
            ),
            const SizedBox(height: 10),
            const Text(
              'Les informations, calculs, estimations, alertes et '
              'indicateurs fournis par l’application sont donnés à titre '
              'strictement indicatif. Ils ne constituent ni une '
              'certification, ni un diagnostic, ni une garantie de '
              'sécurité, de fiabilité ou de bon fonctionnement.',
            ),
            const SizedBox(height: 10),
            const Text(
              'L’utilisateur demeure seul responsable du choix, de la '
              'charge, de l’utilisation, du stockage, du contrôle et de '
              'l’entretien de son matériel, ainsi que du respect des '
              'recommandations du fabricant et des règles de sécurité '
              'applicables.',
            ),
            const SizedBox(height: 10),
            const Text(
              'RC Companion, son développeur et ses contributeurs ne '
              'pourront être tenus responsables d’un dommage matériel '
              'ou corporel, d’une perte de données, d’un incident ou de '
              'toute conséquence directe ou indirecte résultant de '
              'l’utilisation de l’application, d’une erreur de saisie '
              'ou de l’interprétation des informations affichées.',
            ),
            const SizedBox(height: 10),
            const Text(
              'En cas de doute ou de contradiction, les recommandations '
              'du fabricant et les règles de sécurité doivent toujours '
              'prévaloir sur les indications fournies par RC Companion.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoBullet extends StatelessWidget {
  const _InfoBullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, size: 6),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _VersionLine extends StatelessWidget {
  const _VersionLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
