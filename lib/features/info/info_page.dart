import 'package:flutter/material.dart';

class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  static const String appVersion = 'V1.0';
  static const String batteryHealthVersion = 'V1.2';
  static const String batteryCompatibilityVersion = 'V1.0';
  static const String batteryChargeStateVersion = 'V1.1';
  static const String lastUpdate = 'Juillet 2026';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informations & Références')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _headerCard(context),
          const SizedBox(height: 16),
          _warningCard(context),
          const SizedBox(height: 16),
          _sectionCard(
            context,
            icon: Icons.battery_std,
            title: 'État de charge',
            children: const [
              Text(
                'RC Companion distingue l’état de charge actuel d’une '
                'batterie de son état général de santé.',
              ),
              SizedBox(height: 10),
              Text(
                'Le niveau de charge est déterminé à partir du pourcentage '
                'enregistré dans le dernier relevé utile.',
              ),
              SizedBox(height: 12),
              Text(
                'Affichage du niveau de charge',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet('De 50 à 100 % : affichage CHARGE XX % en vert.'),
              _InfoBullet('De 21 à 49 % : affichage CHARGE XX % en orange.'),
              _InfoBullet('De 0 à 20 % : affichage CHARGE XX % en rouge.'),
              _InfoBullet('Le mode STORAGE est affiché en bleu.'),
              SizedBox(height: 12),
              Text(
                'Sélection pour un roulage',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Une batterie dont le niveau de charge est supérieur à '
                '20 % peut être sélectionnée pour un roulage.',
              ),
              _InfoBullet(
                'Une batterie dont le niveau de charge est inférieur ou '
                'égal à 20 % ne peut pas être sélectionnée.',
              ),
              _InfoBullet(
                'Une batterie en mode STORAGE reste sélectionnable. '
                'L’utilisateur doit toutefois vérifier que son niveau de '
                'charge convient à l’utilisation prévue.',
              ),
              SizedBox(height: 12),
              Text(
                'Le niveau de charge affiché dépend des valeurs saisies '
                'dans les relevés. Une saisie incorrecte peut donc produire '
                'un état de charge erroné.',
              ),
              SizedBox(height: 12),
              _VersionLine(
                label: 'Version de l’algorithme',
                value: batteryChargeStateVersion,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            context,
            icon: Icons.battery_charging_full,
            title: 'Santé batterie',
            children: const [
              Text(
                'RC Companion distingue l’état de charge d’une batterie '
                'de sa santé.',
              ),
              SizedBox(height: 10),
              Text(
                'La santé est une estimation de l’état général de la '
                'batterie au fil du temps. Une batterie peut être '
                'faiblement chargée mais en bonne santé, ou inversement.',
              ),
              SizedBox(height: 12),
              Text(
                'Données utilisées',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'La mesure de référence sert de base de comparaison.',
              ),
              _InfoBullet(
                'Seuls les relevés effectués après charge sont utilisés '
                'dans l’historique de santé.',
              ),
              _InfoBullet(
                'Les relevés de fin de roulage ne sont pas utilisés pour '
                'déterminer la santé de la batterie.',
              ),
              SizedBox(height: 12),
              Text(
                'Critères analysés',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Évolution de la résistance interne moyenne par rapport '
                'à la mesure de référence.',
              ),
              _InfoBullet(
                'Écart de tension entre la cellule la plus haute et la '
                'cellule la plus basse.',
              ),
              _InfoBullet('Écart de résistance interne entre les cellules.'),
              _InfoBullet('Évolution historique des relevés après charge.'),
              _InfoBullet(
                'Tendance observée sur les trois derniers relevés après '
                'charge lorsqu’ils sont disponibles.',
              ),
              SizedBox(height: 12),
              Text(
                'Seuils actuellement utilisés',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Écart de tension supérieur à 0,050 V : indicateur à '
                'surveiller.',
              ),
              _InfoBullet(
                'Écart de tension supérieur à 0,100 V : indicateur '
                'critique.',
              ),
              _InfoBullet(
                'Écart de résistance interne supérieur à 5 mΩ : '
                'indicateur à surveiller.',
              ),
              _InfoBullet(
                'Écart de résistance interne supérieur à 10 mΩ : '
                'indicateur critique.',
              ),
              _InfoBullet(
                'Hausse de la résistance interne moyenne supérieure à '
                '25 % par rapport à la référence : indicateur à surveiller.',
              ),
              _InfoBullet(
                'Hausse supérieure à 100 % par rapport à la référence : '
                'indicateur critique.',
              ),
              _InfoBullet(
                'Une hausse régulière supérieure à 15 % entre le premier '
                'et le dernier des trois relevés récents est considérée '
                'comme une tendance défavorable.',
              ),
              SizedBox(height: 12),
              Text(
                'Niveaux de santé',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Bonne : les valeurs restent cohérentes et aucune '
                'dégradation significative n’est détectée.',
              ),
              _InfoBullet(
                'À surveiller : au moins un indicateur de dégradation ou '
                'une tendance défavorable est détecté.',
              ),
              _InfoBullet(
                'HS : un indicateur critique est présent sur le dernier '
                'relevé ou une dégradation critique est confirmée sur '
                'plusieurs relevés récents.',
              ),
              _InfoBullet(
                'Non évaluée : aucune mesure de référence exploitable ou '
                'aucun relevé après charge exploitable n’est disponible.',
              ),
              SizedBox(height: 12),
              Text(
                'Limites du calcul',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'La santé affichée dépend directement de la qualité, de '
                'la précision et de la régularité des mesures saisies.',
              ),
              _InfoBullet(
                'Le résultat constitue une aide au suivi et non une '
                'expertise technique.',
              ),
              _InfoBullet(
                'Une batterie classée Bonne peut néanmoins présenter un '
                'défaut non détecté par les données enregistrées.',
              ),
              SizedBox(height: 12),
              Text(
                'Avertissement',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'RC Companion fournit une aide à la décision destinée au '
                'suivi des batteries. Les calculs, recommandations et '
                'niveaux de santé affichés ne constituent ni une '
                'certification, ni une garantie de sécurité ou de bon '
                'fonctionnement.',
              ),
              SizedBox(height: 10),
              Text(
                'L’utilisateur demeure seul responsable de la vérification, '
                'de la charge, du stockage, de l’utilisation et de la mise '
                'au rebut de ses batteries.',
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
                'Cette page est mise à jour lors de l’ajout ou de la '
                'modification d’un calcul, d’un seuil ou d’une règle de '
                'compatibilité.',
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
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
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
                Icon(icon, color: Theme.of(context).colorScheme.primary),
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
  const _VersionLine({required this.label, required this.value});

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
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
