import 'package:flutter/material.dart';

class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  static const String appVersion = 'V1.0';
  static const String batteryHealthVersion = 'V1.2';
  static const String batteryCompatibilityVersion = 'V1.0';
  static const String batteryChargeStateVersion = 'V1.1';
  static const String offlineArchitectureVersion = 'V1.1';
  static const String authenticationVersion = 'V1.0';
  static const String lastUpdate = 'Août 2026';

  static const String _termsOfUseV1 = """
CONDITIONS D’UTILISATION — RC COMPANION

Version du 16 août 2026

1. Objet

RC Companion est une application de gestion destinée au modélisme radiocommandé. Elle permet notamment d’enregistrer et d’organiser des informations relatives aux modèles RC, batteries, sessions d’utilisation, opérations de maintenance, documents et autres éléments proposés par l’application.

RC Companion constitue exclusivement un outil d’organisation, de suivi et d’aide à la gestion. L’application ne constitue pas un dispositif de sécurité, de diagnostic, de certification ou de contrôle technique.

2. Acceptation des conditions

La création d’un compte nécessite l’acceptation des présentes Conditions d’utilisation.

L’utilisateur reconnaît les avoir consultées avant de créer son compte.

3. Compte utilisateur

L’utilisateur doit fournir une adresse e-mail valide à laquelle il a accès et est responsable de la confidentialité de ses identifiants et de son mot de passe.

Il lui appartient de protéger l’accès aux appareils sur lesquels RC Companion est installé et de signaler ou désactiver, lorsque les fonctionnalités disponibles le permettent, un appareil qui ne devrait plus accéder à son compte.

4. Informations enregistrées

L’utilisateur demeure responsable de l’exactitude des informations qu’il saisit dans RC Companion.

Certaines informations affichées par l’application peuvent résulter de calculs, de données antérieurement enregistrées ou de synchronisations entre appareils.

Malgré les contrôles réalisés par l’application, une information peut être incomplète, incorrecte, obsolète ou temporairement non synchronisée.

Toute information susceptible d’influencer la sécurité ou l’utilisation d’un équipement doit être vérifiée par l’utilisateur avant utilisation du matériel.

5. Batteries

Les fonctions relatives aux batteries constituent uniquement des outils de suivi.

Les indications telles que l’état de charge, le pourcentage restant, les tensions, résistances internes, températures, compatibilités, état de santé ou toute autre information affichée par RC Companion ne constituent aucune certification de l’état ou de la sécurité d’une batterie.

Une batterie indiquée comme « Bonne », « Chargée », « Storage », compatible ou présentant toute autre indication favorable peut néanmoins être endommagée, défectueuse ou dangereuse.

L’utilisateur reste seul responsable du contrôle physique de ses batteries ainsi que de leur choix, branchement, charge, décharge, équilibrage, stockage, transport, entretien et utilisation conformément notamment aux instructions des fabricants.

RC Companion ne remplace ni un chargeur adapté, ni un appareil de mesure, ni les contrôles de sécurité nécessaires.

6. Modèles radiocommandés et autres équipements

RC Companion ne garantit jamais qu’un modèle radiocommandé, une batterie, un système radio, un chargeur ou tout autre équipement est en état de fonctionner ou peut être utilisé en sécurité.

Les historiques de sessions et de maintenance, compteurs, rappels et informations enregistrées ne remplacent pas l’inspection du matériel.

L’utilisateur demeure responsable de l’état mécanique, électrique et électronique de son matériel avant et pendant son utilisation.

7. Utilisation des modèles RC

L’utilisateur est seul responsable de l’utilisation de ses modèles radiocommandés et doit respecter les règles de sécurité, les recommandations des fabricants et la réglementation applicable au lieu et au matériel utilisés.

Il lui appartient notamment de s’assurer que son utilisation ne présente pas de danger pour les personnes, les animaux, les biens ou l’environnement.

8. Fonctionnement hors ligne et synchronisation

RC Companion est conçu pour permettre certaines utilisations locales et une synchronisation des données lorsque les conditions techniques nécessaires sont réunies.

Une synchronisation immédiate ou permanente entre plusieurs appareils ne peut cependant être garantie.

Une absence de connexion, une interruption réseau, l’indisponibilité d’un service tiers, un conflit de données, un dysfonctionnement matériel ou logiciel ou tout autre incident technique peut retarder ou empêcher temporairement une synchronisation.

9. Données et fichiers

Les données structurées nécessaires au fonctionnement de RC Companion peuvent être enregistrées localement sur les appareils et synchronisées au moyen de l’infrastructure utilisée par RC Companion.

Elles ne constituent pas une sauvegarde Google Drive et ne sont pas présentées comme exportables par l’utilisateur sous la forme d’une sauvegarde complète de la base RC Companion.

Lorsque l’utilisateur active une fonctionnalité permettant de stocker des fichiers dans son propre espace Google Drive, les fichiers concernés sont placés dans l’espace associé à son compte Google.

La disponibilité et la capacité de cet espace ainsi que certains mécanismes de conservation ou récupération dépendent alors également des services proposés par Google.

10. Perte ou altération de données

RC Companion met en œuvre des mécanismes destinés à enregistrer et synchroniser les informations nécessaires au service.

Toutefois, aucun système informatique ne permet de garantir une conservation ou une disponibilité absolue des données.

Dans les limites autorisées par la loi, RC Companion ne saurait être tenu responsable d’une perte ou altération résultant notamment d’une panne ou perte d’un appareil, d’une suppression volontaire effectuée par l’utilisateur, d’un dysfonctionnement d’un service tiers, d’une interruption réseau ou d’un événement indépendant du fonctionnement normalement attendu de RC Companion.

Cette disposition ne limite pas les responsabilités qui ne peuvent légalement être exclues ou limitées.

11. Services tiers

RC Companion utilise ou peut utiliser des services fournis par des prestataires tiers pour certaines fonctionnalités, notamment l’authentification, la synchronisation et, lorsque l’utilisateur l’active, Google Drive.

La disponibilité et les conditions de fonctionnement de ces services peuvent évoluer indépendamment de RC Companion.

12. Suppression du compte

Lorsque l’utilisateur demande la suppression définitive de son compte par les fonctions prévues à cet effet, les données serveur associées au compte et gérées par RC Companion sont destinées à être supprimées conformément au fonctionnement prévu par l’application.

Cette opération est irréversible.

Les éléments éventuellement conservés dans un service personnel externe appartenant à l’utilisateur, notamment son propre espace Google Drive, peuvent relever d’un stockage distinct et doivent être gérés depuis le service concerné lorsque nécessaire.

13. Limitation de responsabilité

Dans les limites autorisées par la législation applicable, RC Companion ne peut être considéré comme garant de l’état, des performances, de la compatibilité ou de la sécurité du matériel enregistré dans l’application.

RC Companion ne saurait notamment être considéré comme responsable d’un dommage résultant de l’utilisation d’un modèle RC, d’une batterie, d’un chargeur ou d’un autre équipement sur la seule base d’une indication fournie par l’application.

L’utilisateur doit toujours appliquer les règles de sécurité appropriées et contrôler son matériel indépendamment des informations affichées par RC Companion.

Aucune disposition des présentes conditions n’a pour objet d’exclure ou de limiter une responsabilité lorsque son exclusion ou sa limitation est interdite par la loi applicable.

14. Disponibilité et évolution

RC Companion peut faire l’objet de mises à jour, opérations de maintenance, corrections ou modifications.

Certaines fonctionnalités peuvent évoluer, être remplacées ou supprimées lorsque cela est nécessaire au développement, à la sécurité ou au fonctionnement de l’application.

15. Propriété intellectuelle

Sauf indication contraire, RC Companion, son nom, son interface, ses éléments graphiques et les éléments logiciels qui la composent sont protégés par les droits de propriété intellectuelle applicables.

L’utilisation de l’application n’accorde à l’utilisateur aucun droit de propriété sur ces éléments.

Les marques, noms et contenus appartenant à des tiers restent la propriété de leurs titulaires respectifs.

16. Modification des présentes conditions

Les présentes Conditions d’utilisation peuvent être modifiées afin de tenir compte notamment de l’évolution de RC Companion, de ses services ou du cadre juridique applicable.

Lorsque cela est nécessaire, l’utilisateur sera informé d’une nouvelle version et une nouvelle acceptation pourra être demandée.

17. Droit applicable et contact

Les présentes conditions sont soumises au droit français, sous réserve des dispositions impératives éventuellement applicables au lieu de résidence de l’utilisateur.

Pour toute question relative à RC Companion :

rccompanion.app@gmail.com
""";

  static const String _privacyPolicyV1 = """
POLITIQUE DE CONFIDENTIALITÉ — RC COMPANION

Version du 16 août 2026

1. Objet

La présente Politique de confidentialité explique quelles données personnelles peuvent être traitées lors de l’utilisation de RC Companion, pour quelles raisons et quels sont les droits de l’utilisateur.

2. Données liées au compte

La création et l’utilisation d’un compte peuvent notamment nécessiter :

• l’adresse e-mail ;
• le pseudo choisi ;
• les informations techniques nécessaires à l’authentification ;
• les informations nécessaires à la gestion des appareils autorisés et des sessions de connexion.

Le mot de passe est traité par le système d’authentification et n’est pas destiné à être accessible en clair par RC Companion.

3. Données saisies dans RC Companion

L’utilisateur peut enregistrer des informations concernant notamment ses modèles radiocommandés, batteries, sessions et opérations de maintenance.

Ces données servent à fournir les fonctionnalités demandées par l’utilisateur et à permettre leur synchronisation lorsque celle-ci est disponible.

Certaines informations peuvent indirectement constituer des données personnelles lorsqu’elles sont associées au compte d’un utilisateur.

4. Finalités

Les données sont utilisées uniquement dans la mesure nécessaire notamment pour :

• créer et sécuriser le compte ;
• authentifier l’utilisateur ;
• fournir les fonctionnalités RC Companion ;
• synchroniser les données entre les appareils autorisés ;
• permettre la gestion et la sécurité des appareils associés au compte ;
• permettre la récupération du compte et la réinitialisation du mot de passe ;
• assurer le fonctionnement, la sécurité et la maintenance technique du service.

Les données ne sont pas destinées à être vendues à des annonceurs.

5. Base juridique

Les traitements strictement nécessaires à la création du compte et à la fourniture des fonctionnalités demandées sont réalisés dans le cadre nécessaire à la fourniture du service.

Lorsque le consentement constitue la base juridique appropriée pour une fonctionnalité facultative, il doit être recueilli séparément.

6. Stockage local et synchronisation

Une partie des données RC Companion est conservée localement sur les appareils utilisés.

Les données nécessaires à la synchronisation peuvent être transmises à l’infrastructure serveur utilisée par RC Companion afin de permettre leur disponibilité sur les différents appareils associés au compte.

7. Supabase

RC Companion utilise Supabase pour certaines fonctions serveur, notamment l’authentification et la synchronisation.

Supabase intervient comme prestataire technique pour les traitements nécessaires au fonctionnement du service.

8. Google Drive

Google Drive est une fonctionnalité distincte et facultative lorsqu’elle est proposée.

Si l’utilisateur choisit de connecter son compte Google, RC Companion accède uniquement aux autorisations Google nécessaires aux fonctionnalités proposées.

Les données Google auxquelles RC Companion accède sont utilisées uniquement pour fournir les fonctionnalités correspondantes.

Les fichiers enregistrés dans Google Drive restent associés à l’espace Google de l’utilisateur.

RC Companion ne vend pas les données Google de l’utilisateur et ne les utilise pas à des fins publicitaires.

9. Appareil photo

RC Companion peut demander l’autorisation d’utiliser l’appareil photo pour les fonctionnalités qui le nécessitent, notamment la lecture de QR Codes.

Cette autorisation permet d’utiliser la caméra pour la fonctionnalité demandée et ne constitue pas en elle-même un consentement général à d’autres traitements de données.

10. Destinataires

Les données sont accessibles dans la mesure nécessaire :

• à l’utilisateur ;
• aux systèmes techniques nécessaires au fonctionnement de RC Companion ;
• aux prestataires techniques utilisés par RC Companion dans le cadre de leurs fonctions respectives ;
• aux autorités lorsqu’une obligation légale l’impose.

RC Companion ne prévoit pas la commercialisation des données personnelles de ses utilisateurs.

11. Durée de conservation

Les données associées au compte sont conservées pendant la durée nécessaire au fonctionnement du compte et du service, sauf obligation légale ou nécessité technique justifiant une durée différente.

Lorsqu’un compte est définitivement supprimé, les données serveur associées et gérées par RC Companion sont destinées à être supprimées selon le fonctionnement prévu par le service.

Les données éventuellement détenues indépendamment par un service tiers personnel, tel que Google Drive, peuvent obéir aux règles de conservation du service concerné.

12. Sécurité

Des mesures techniques et organisationnelles adaptées sont mises en œuvre afin de protéger les données contre les accès non autorisés, pertes, altérations ou divulgations.

Aucun système informatique ou réseau ne pouvant garantir une sécurité absolue, les mesures sont adaptées et réévaluées en fonction des risques et de l’évolution du service.

13. Droits de l’utilisateur

Conformément à la réglementation applicable en matière de protection des données, l’utilisateur peut, selon les conditions prévues par celle-ci, exercer notamment ses droits :

• d’accès ;
• de rectification ;
• d’effacement ;
• de limitation ;
• d’opposition lorsque ce droit est applicable ;
• à la portabilité lorsque les conditions légales sont réunies.

L’utilisateur dispose également du droit d’introduire une réclamation auprès de l’autorité de contrôle compétente, notamment la CNIL en France.

Pour exercer ses droits ou poser une question relative aux données personnelles :

rccompanion.app@gmail.com

14. Modification de la politique

Cette Politique de confidentialité peut évoluer afin de refléter les modifications de RC Companion, des services utilisés ou de la réglementation.

La version applicable et sa date de mise à jour doivent rester accessibles à l’utilisateur.
""";

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
            icon: Icons.lock_outline_rounded,
            title: 'Authentification et sécurité',
            children: const [
              Text(
                'L’authentification permet de protéger l’accès au compte '
                'RC Companion et de rattacher les données synchronisées au '
                'bon utilisateur.',
              ),
              SizedBox(height: 12),
              Text('Connexion', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              _InfoBullet(
                'La connexion s’effectue avec une adresse e-mail et un mot '
                'de passe.',
              ),
              _InfoBullet(
                'Le pseudo demandé lors de la création du compte sert '
                'uniquement d’information de profil. Il ne permet pas de '
                'se connecter.',
              ),
              _InfoBullet(
                'Une connexion Internet est nécessaire lors de la première '
                'authentification, après une déconnexion complète ou lorsque '
                'la session n’est plus valide.',
              ),
              SizedBox(height: 12),
              Text(
                'Gestion de la session',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Après une connexion réussie, la session utilisateur peut '
                'rester enregistrée sur l’appareil afin d’éviter une nouvelle '
                'saisie du mot de passe à chaque ouverture.',
              ),
              _InfoBullet(
                'Une déconnexion volontaire supprime la session enregistrée '
                'sur l’appareil et impose une nouvelle authentification en '
                'ligne.',
              ),
              SizedBox(height: 12),
              Text(
                'Protection du mot de passe',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Les mots de passe sont gérés par le service '
                'd’authentification Supabase.',
              ),
              _InfoBullet(
                'Ils ne sont pas enregistrés dans la base de données métier '
                'de RC Companion ni dans les données locales de l’application.',
              ),
              _InfoBullet(
                'RC Companion ne connaît pas le mot de passe en clair de '
                'l’utilisateur.',
              ),
              SizedBox(height: 12),
              Text(
                'Évolutions prévues',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Déverrouillage local par Face ID, Touch ID ou biométrie '
                'Android, selon les capacités de l’appareil.',
              ),
              _InfoBullet(
                'Verrouillage local de l’application sans déconnexion du '
                'compte utilisateur.',
              ),
              SizedBox(height: 12),
              _VersionLine(
                label: 'Version de la documentation',
                value: authenticationVersion,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            context,
            icon: Icons.cloud_off_rounded,
            title: 'Fonctionnement hors ligne',
            children: const [
              Text(
                'RC Companion est conçu pour permettre la consultation et '
                'l’enregistrement de données même lorsque l’appareil ne '
                'dispose pas d’une connexion Internet.',
              ),
              SizedBox(height: 12),
              Text(
                'Base de données locale',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Les données utiles au fonctionnement de l’application sont '
                'conservées localement dans une base Drift sur chaque appareil.',
              ),
              _InfoBullet(
                'Les informations déjà synchronisées restent consultables '
                'hors connexion.',
              ),
              _InfoBullet(
                'Les créations, modifications et suppressions compatibles '
                'avec le mode hors ligne sont enregistrées localement avant '
                'leur envoi vers le cloud.',
              ),
              SizedBox(height: 12),
              Text(
                'File d’attente de synchronisation',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Chaque opération réalisée hors ligne est placée dans une '
                'file d’attente locale.',
              ),
              _InfoBullet(
                'Cette file permet de conserver les opérations à transmettre '
                'jusqu’au retour du réseau.',
              ),
              _InfoBullet(
                'La fermeture puis la réouverture de l’application ne doit '
                'pas supprimer les opérations locales encore en attente.',
              ),
              SizedBox(height: 12),
              Text('Limites', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              _InfoBullet(
                'Une nouvelle authentification ne peut pas être créée hors '
                'connexion après une déconnexion complète.',
              ),
              _InfoBullet(
                'Certaines fonctions dépendant directement d’un service en '
                'ligne peuvent rester indisponibles sans réseau.',
              ),
              SizedBox(height: 12),
              _VersionLine(
                label: 'Version de l’architecture hors ligne',
                value: offlineArchitectureVersion,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            context,
            icon: Icons.sd_storage_rounded,
            title: 'Stockage hors ligne des fichiers',
            children: const [
              Text(
                'Les documents, notices radio et photos utilisés par '
                'RC Companion peuvent être conservés localement afin de '
                'rester accessibles sans connexion Internet.',
              ),
              SizedBox(height: 12),
              Text(
                'Choix du stockage',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Sur Android, le stockage hors ligne peut utiliser la mémoire '
                'interne de l’appareil ou une carte SD lorsqu’elle est '
                'disponible.',
              ),
              _InfoBullet(
                'Le choix s’effectue dans Mon compte → Stockage hors ligne. '
                'Un seul emplacement est utilisé à la fois.',
              ),
              _InfoBullet(
                'La capacité disponible dépend de l’appareil ou de la carte '
                'SD sélectionnée.',
              ),
              SizedBox(height: 12),
              Text(
                'Mise à jour automatique',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Lorsqu’un fichier est ajouté depuis un autre appareil, '
                'RC Companion récupère automatiquement sa copie hors ligne '
                'sur l’emplacement sélectionné.',
              ),
              _InfoBullet(
                'Lorsqu’un fichier est remplacé, la nouvelle version est '
                'récupérée et l’ancienne copie locale devenue inutile est '
                'nettoyée.',
              ),
              _InfoBullet(
                'Lorsqu’un fichier est supprimé depuis un autre appareil, '
                'la copie correspondante est également supprimée du stockage '
                'hors ligne après synchronisation.',
              ),
              SizedBox(height: 12),
              Text(
                'Carte SD retirée ou remplacée',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Le retrait, la panne ou le remplacement d’une carte SD ne '
                'doit jamais être interprété comme une demande de suppression '
                'des fichiers distants.',
              ),
              _InfoBullet(
                'Lorsqu’une nouvelle carte SD vierge est sélectionnée, le '
                'stockage hors ligne peut être reconstruit à partir des '
                'fichiers encore disponibles dans le stockage synchronisé.',
              ),
              _InfoBullet(
                'Le bouton Mettre à jour le stockage hors ligne permet de '
                'reconstruire ou réparer le contenu local lorsque cela est '
                'nécessaire. Il n’est pas requis lors du fonctionnement '
                'normal de la synchronisation automatique.',
              ),
              SizedBox(height: 12),
              Text(
                'Google Drive — sauvegarde et synchronisation des fichiers',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'L’utilisation de Google Drive nécessite un compte Google. '
                'L’utilisateur doit connecter un compte existant ou en créer '
                'un s’il n’en possède pas.',
              ),
              _InfoBullet(
                'Google Drive est utilisé par RC Companion pour conserver et '
                'synchroniser les fichiers associés à l’application, notamment '
                'les documents des modèles, les notices et manuels radio ainsi '
                'que les photos prises en charge.',
              ),
              _InfoBullet(
                'Les données structurées de RC Companion, telles que les '
                'modèles, batteries, sessions, maintenances et relevés, ne '
                'sont pas stockées sur Google Drive. Elles sont conservées '
                'localement dans Drift et synchronisées via Supabase.',
              ),
              _InfoBullet(
                'L’espace disponible sur Google Drive dépend du quota du '
                'compte Google utilisé. Si davantage de stockage est '
                'nécessaire, l’utilisateur peut choisir de souscrire une '
                'offre de stockage supplémentaire proposée par Google.',
              ),
              _InfoBullet(
                'Tout abonnement ou achat de stockage Google relève du choix '
                'et de la responsabilité de l’utilisateur. RC Companion '
                'n’impose, ne fournit et ne facture aucun abonnement Google.',
              ),
              _InfoBullet(
                'Le stockage hors ligne de l’appareil ou de la carte SD '
                'constitue une copie locale permettant notamment l’accès aux '
                'fichiers sans réseau. Google Drive permet de conserver une '
                'copie synchronisée et de reconstituer le stockage local '
                'lorsque cela est nécessaire.',
              ),
              _InfoBullet(
                'La disparition d’une copie locale provoquée par le retrait, '
                'la panne ou le remplacement du support de stockage ne doit '
                'jamais entraîner la suppression du fichier conservé sur '
                'Google Drive.',
              ),
              SizedBox(height: 12),
              Text(
                'Précautions',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Une carte SD doit rester insérée pour que les fichiers qui '
                'y sont stockés puissent être ouverts hors ligne.',
              ),
              _InfoBullet(
                'Après un changement de support, laisser RC Companion '
                'reconstituer le stockage avant de compter sur les fichiers '
                'pour une utilisation entièrement hors connexion.',
              ),
              SizedBox(height: 12),
              _VersionLine(
                label: 'Version de l’architecture hors ligne',
                value: offlineArchitectureVersion,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            context,
            icon: Icons.sync_rounded,
            title: 'Synchronisation multi-appareils',
            children: const [
              Text(
                'La synchronisation permet de retrouver les mêmes données '
                'RC Companion sur les différents appareils connectés au même '
                'compte utilisateur.',
              ),
              SizedBox(height: 12),
              Text(
                'Principe général',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet('L’opération est d’abord enregistrée localement.'),
              _InfoBullet(
                'Lorsqu’elle ne peut pas être envoyée immédiatement, elle '
                'reste dans la file d’attente de synchronisation.',
              ),
              _InfoBullet(
                'Dès que le réseau est disponible, l’application tente '
                'd’envoyer les opérations en attente vers Supabase.',
              ),
              _InfoBullet(
                'Les autres appareils récupèrent ensuite les données '
                'synchronisées lors de leur prochaine mise à jour.',
              ),
              SizedBox(height: 12),
              Text(
                'Appareils concernés',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet('macOS.'),
              _InfoBullet('iPadOS et iOS.'),
              _InfoBullet('Android.'),
              _InfoBullet(
                'Windows lorsque la version correspondante sera distribuée.',
              ),
              SizedBox(height: 12),
              Text(
                'Précautions',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Une synchronisation peut nécessiter quelques instants selon '
                'la qualité du réseau et le nombre d’opérations en attente.',
              ),
              _InfoBullet(
                'Avant de modifier la même donnée sur plusieurs appareils '
                'hors ligne, il est recommandé de laisser les appareils se '
                'synchroniser afin de limiter les conflits.',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            context,
            icon: Icons.account_tree_outlined,
            title: 'Architecture de RC Companion',
            children: const [
              Text(
                'RC Companion repose sur une architecture locale et cloud '
                'afin de concilier rapidité, fonctionnement hors ligne et '
                'synchronisation entre appareils.',
              ),
              SizedBox(height: 12),
              Text(
                'Drift — base locale',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Conserve les données utiles directement sur l’appareil.',
              ),
              _InfoBullet(
                'Permet la consultation et les opérations compatibles hors '
                'connexion.',
              ),
              SizedBox(height: 12),
              Text(
                'Supabase — services en ligne',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet('Gère l’authentification des utilisateurs.'),
              _InfoBullet(
                'Centralise les données synchronisées afin qu’elles puissent '
                'être retrouvées sur plusieurs appareils.',
              ),
              SizedBox(height: 12),
              Text(
                'Synchronisation automatique',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              _InfoBullet(
                'Relie la base locale Drift aux données distantes Supabase.',
              ),
              _InfoBullet(
                'Transmet les opérations en attente lorsque le réseau '
                'redevient disponible.',
              ),
            ],
          ),
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
            icon: Icons.description_outlined,
            title: 'Formats de fichiers pris en charge',
            children: const [
              Text(
                'RC Companion accepte uniquement les formats de documents '
                'et d’images officiellement prévus par l’application.',
              ),
              SizedBox(height: 12),
              Text('Documents', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              _InfoBullet('PDF.'),
              SizedBox(height: 8),
              Text('Images', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              _InfoBullet('JPG et JPEG.'),
              _InfoBullet('PNG.'),
              _InfoBullet('WEBP.'),
              SizedBox(height: 12),
              Text(
                'Les autres formats bureautiques ou formats de documents '
                'ne sont pas pris en charge dans cette version de '
                'RC Companion.',
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
                'modification d’un calcul, d’un seuil, d’une règle de '
                'compatibilité ou d’un fonctionnement important de '
                'l’application.',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            context,
            icon: Icons.gavel_rounded,
            title: 'Informations légales',
            children: [
              const Text(
                'Les documents ci-dessous restent accessibles à tout moment '
                'depuis RC Companion.',
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: const Text(
                  'Conditions d’utilisation',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Version du 16 août 2026'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showLegalDocument(
                  context,
                  title: 'Conditions d’utilisation',
                  body: _termsOfUseV1,
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text(
                  'Politique de confidentialité',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Version du 16 août 2026'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showLegalDocument(
                  context,
                  title: 'Politique de confidentialité',
                  body: _privacyPolicyV1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            context,
            icon: Icons.history_rounded,
            title: 'Historique documentaire',
            children: const [
              _InfoBullet('V1.0 : première documentation générale.'),
              _InfoBullet('V1.1 : documentation de l’état de charge.'),
              _InfoBullet('V1.2 : documentation de la santé batterie.'),
              _InfoBullet(
                'Juillet 2026 : ajout de l’authentification, du mode hors '
                'ligne, de la synchronisation, de l’architecture et des '
                'formats de fichiers pris en charge.',
              ),
              _InfoBullet(
                'Août 2026 : ajout du stockage hors ligne des fichiers, du '
                'choix mémoire interne/carte SD sur Android, de Google Drive '
                'pour la sauvegarde et la synchronisation des fichiers, de la '
                'reconstruction du stockage et de sa mise à jour automatique.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showLegalDocument(
    BuildContext context, {
    required String title,
    required String body,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final mediaQuery = MediaQuery.of(dialogContext);
        final isPhone = mediaQuery.size.width < 600;

        return AlertDialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: isPhone ? 16 : 40,
            vertical: isPhone ? 16 : 24,
          ),
          title: Text(title),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 680,
              maxHeight: mediaQuery.size.height * (isPhone ? 0.70 : 0.74),
            ),
            child: SingleChildScrollView(
              child: SelectableText(body, style: const TextStyle(height: 1.48)),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
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
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
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
