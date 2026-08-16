import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/supabase_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    this.passwordRecoveryMode = false,
    this.onPasswordResetComplete,
  });

  final bool passwordRecoveryMode;
  final Future<void> Function()? onPasswordResetComplete;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  static const _rememberedEmailsKey = 'rc_remembered_login_emails_v1';
  static const _lastRememberedEmailKey = 'rc_last_remembered_login_email_v1';

  final identifierController = TextEditingController();
  final emailController = TextEditingController();
  final pseudoController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLoginMode = true;
  bool isLoading = false;
  bool hidePassword = true;
  bool hideConfirmPassword = true;
  bool rememberMe = true;
  bool acceptTerms = false;
  bool showRememberedEmails = false;
  String? pendingVerificationEmail;
  List<String> rememberedEmails = const [];

  @override
  void initState() {
    super.initState();
    _loadRememberedEmails();
  }

  Future<void> _loadRememberedEmails() async {
    final prefs = await SharedPreferences.getInstance();
    final emails =
        (prefs.getStringList(_rememberedEmailsKey) ?? const <String>[])
            .map((email) => email.trim().toLowerCase())
            .where((email) => email.contains('@'))
            .toSet()
            .toList()
          ..sort();

    final lastEmail = prefs
        .getString(_lastRememberedEmailKey)
        ?.trim()
        .toLowerCase();

    if (!mounted) return;

    setState(() {
      rememberedEmails = emails;
      if (identifierController.text.trim().isEmpty &&
          lastEmail != null &&
          emails.contains(lastEmail)) {
        identifierController.text = lastEmail;
      }
    });
  }

  Future<void> _rememberSuccessfulLogin(String email) async {
    final normalized = email.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    final emails = <String>{...rememberedEmails};

    if (rememberMe) {
      emails.add(normalized);
      await prefs.setString(_lastRememberedEmailKey, normalized);
    } else {
      emails.remove(normalized);
      final lastEmail = prefs.getString(_lastRememberedEmailKey);
      if (lastEmail == normalized) {
        await prefs.remove(_lastRememberedEmailKey);
      }
    }

    final sorted = emails.toList()..sort();
    await prefs.setStringList(_rememberedEmailsKey, sorted);

    if (!mounted) return;
    setState(() => rememberedEmails = sorted);
  }

  Future<void> _forgetRememberedEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    final emails =
        rememberedEmails
            .where((item) => item.toLowerCase() != normalized)
            .toList()
          ..sort();

    await prefs.setStringList(_rememberedEmailsKey, emails);

    if (prefs.getString(_lastRememberedEmailKey)?.toLowerCase() == normalized) {
      await prefs.remove(_lastRememberedEmailKey);
    }

    if (!mounted) return;
    setState(() => rememberedEmails = emails);
  }

  @override
  void dispose() {
    identifierController.dispose();
    emailController.dispose();
    pseudoController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();

    if (isLoginMode) {
      final identifier = identifierController.text.trim();
      final password = passwordController.text;

      if (identifier.isEmpty || password.length < 6) {
        _showMessage(
          'Indique ton adresse e-mail et un mot de passe de 6 caractères minimum.',
        );
        return;
      }

      if (!identifier.contains('@')) {
        _showMessage(
          'La connexion par pseudo sera activée lors de la mise en place des profils. '
          'Pour le moment, utilise ton adresse e-mail.',
        );
        return;
      }

      await _runAuthAction(() async {
        await SupabaseService.client.auth.signInWithPassword(
          email: identifier,
          password: password,
        );
        await _rememberSuccessfulLogin(identifier);
      });
      return;
    }

    final pseudo = pseudoController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;
    final confirmation = confirmPasswordController.text;

    if (pseudo.length < 3) {
      _showMessage('Le pseudo doit contenir au moins 3 caractères.');
      return;
    }
    if (!email.contains('@')) {
      _showMessage('Indique une adresse e-mail valide.');
      return;
    }
    if (password.length < 6) {
      _showMessage('Le mot de passe doit contenir au moins 6 caractères.');
      return;
    }
    if (password != confirmation) {
      _showMessage('Les deux mots de passe ne correspondent pas.');
      return;
    }
    if (!acceptTerms) {
      _showMessage('Tu dois accepter les Conditions d’utilisation.');
      return;
    }

    await _runAuthAction(() async {
      final response = await SupabaseService.client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: 'rccompanion://login-callback',
        data: {'pseudo': pseudo},
      );

      if (response.session == null && mounted) {
        setState(() {
          pendingVerificationEmail = email.trim().toLowerCase();
          identifierController.text = email.trim().toLowerCase();
          passwordController.clear();
          confirmPasswordController.clear();
        });
      }
    });
  }

  Future<void> _requestPasswordReset() async {
    final controller = TextEditingController(
      text: identifierController.text.trim(),
    );

    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Réinitialiser le mot de passe'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Adresse e-mail',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              onSubmitted: (value) {
                final normalized = value.trim().toLowerCase();
                if (normalized.contains('@')) {
                  Navigator.of(dialogContext).pop(normalized);
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final normalized = controller.text.trim().toLowerCase();
                if (!normalized.contains('@')) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Indique une adresse e-mail valide.'),
                    ),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(normalized);
              },
              child: const Text('Envoyer le lien'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (email == null || !mounted) return;

    await _runAuthAction(() async {
      await SupabaseService.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'rccompanion://login-callback',
      );

      if (!mounted) return;
      identifierController.text = email;
      _showMessage(
        'Un e-mail de réinitialisation a été envoyé à $email. '
        'Vérifie aussi les courriers indésirables.',
      );
    });
  }

  Future<void> _saveNewPassword() async {
    final password = passwordController.text;
    final confirmation = confirmPasswordController.text;

    if (password.length < 6) {
      _showMessage('Le mot de passe doit contenir au moins 6 caractères.');
      return;
    }

    if (password != confirmation) {
      _showMessage('Les deux mots de passe ne correspondent pas.');
      return;
    }

    await _runAuthAction(() async {
      await SupabaseService.client.auth.updateUser(
        UserAttributes(password: password),
      );

      passwordController.clear();
      confirmPasswordController.clear();

      if (!mounted) return;

      _showMessage('Mot de passe modifié avec succès.');

      final callback = widget.onPasswordResetComplete;
      if (callback != null) {
        await callback();
      }
    });
  }

  Future<void> _resendVerificationEmail() async {
    final email = pendingVerificationEmail;
    if (email == null || email.isEmpty) return;

    await _runAuthAction(() async {
      await SupabaseService.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      _showMessage('E-mail de validation renvoyé à $email.');
    });
  }

  void _editVerificationEmail() {
    final email = pendingVerificationEmail ?? '';
    setState(() {
      pendingVerificationEmail = null;
      isLoginMode = false;
      emailController.text = email;
      passwordController.clear();
      confirmPasswordController.clear();
      acceptTerms = false;
    });
  }

  void _backToLoginFromVerification() {
    final email = pendingVerificationEmail ?? '';
    setState(() {
      pendingVerificationEmail = null;
      isLoginMode = true;
      identifierController.text = email;
      passwordController.clear();
      confirmPasswordController.clear();
    });
  }

  Future<void> _runAuthAction(Future<void> Function() action) async {
    setState(() => isLoading = true);
    try {
      await action();
    } on AuthException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Une erreur inattendue est survenue.');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showLegalDocument({
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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

  Future<void> _showTermsOfUse() {
    return _showLegalDocument(
      title: 'Conditions d’utilisation',
      body: _termsOfUseV1,
    );
  }

  Future<void> _showPrivacyPolicy() {
    return _showLegalDocument(
      title: 'Politique de confidentialité',
      body: _privacyPolicyV1,
    );
  }

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

  void _switchMode() {
    FocusScope.of(context).unfocus();
    setState(() {
      isLoginMode = !isLoginMode;
      passwordController.clear();
      confirmPasswordController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.passwordRecoveryMode) {
      return _buildPasswordRecoveryPage();
    }

    if (pendingVerificationEmail != null) {
      return _buildEmailVerificationPage();
    }

    return Scaffold(
      body: Stack(
        children: [
          const _GridBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isLoginMode ? 430 : 440,
                  ),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                    decoration: BoxDecoration(
                      color: const Color(0xFF071426),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF34506F)),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 28,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: AutofillGroup(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isLoginMode ? 'CONNEXION' : 'CRÉER UN COMPTE',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: AspectRatio(
                              aspectRatio: 16 / 11,
                              child: Center(
                                child: Transform.scale(
                                  scale: 1.60,
                                  child: Image.asset(
                                    'assets/images/rc_logo_login_hd.png',
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Gestionnaire RC',
                            style: TextStyle(
                              color: Color(0xFF2493FF),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (isLoginMode) ...[
                            _field(
                              controller: identifierController,
                              label: 'Adresse e-mail',
                              icon: Icons.person_outline_rounded,
                              keyboardType: TextInputType.emailAddress,
                              inputAction: TextInputAction.next,
                              autofillHints: const [
                                AutofillHints.username,
                                AutofillHints.email,
                              ],
                              suffixIcon: IconButton(
                                tooltip: 'Adresses mémorisées',
                                onPressed: isLoading
                                    ? null
                                    : () {
                                        if (rememberedEmails.isEmpty) {
                                          _showMessage(
                                            'Aucune adresse e-mail mémorisée sur cet appareil.',
                                          );
                                          return;
                                        }
                                        setState(
                                          () => showRememberedEmails =
                                              !showRememberedEmails,
                                        );
                                      },
                                icon: Icon(
                                  showRememberedEmails
                                      ? Icons.arrow_drop_up_rounded
                                      : Icons.arrow_drop_down_rounded,
                                ),
                              ),
                            ),
                            if (showRememberedEmails &&
                                rememberedEmails.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0B1A2E),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFF34506F),
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (
                                      var index = 0;
                                      index < rememberedEmails.length;
                                      index++
                                    ) ...[
                                      ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        leading: const Icon(
                                          Icons.account_circle_outlined,
                                          size: 20,
                                        ),
                                        title: Text(
                                          rememberedEmails[index],
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                        onTap: () {
                                          setState(() {
                                            identifierController.text =
                                                rememberedEmails[index];
                                            rememberMe = true;
                                            showRememberedEmails = false;
                                          });
                                        },
                                        trailing: IconButton(
                                          tooltip: 'Retirer de cette liste',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () async {
                                            final email =
                                                rememberedEmails[index];
                                            await _forgetRememberedEmail(email);
                                            if (!mounted) return;
                                            if (rememberedEmails.isEmpty) {
                                              setState(
                                                () => showRememberedEmails =
                                                    false,
                                              );
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                      if (index < rememberedEmails.length - 1)
                                        const Divider(height: 1),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            _passwordField(
                              controller: passwordController,
                              label: 'Mot de passe',
                              hidden: hidePassword,
                              onToggle: () =>
                                  setState(() => hidePassword = !hidePassword),
                              onSubmitted: (_) => isLoading ? null : submit(),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Checkbox(
                                  value: rememberMe,
                                  onChanged: (value) => setState(
                                    () => rememberMe = value ?? false,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const Text(
                                  'Se souvenir de moi',
                                  style: TextStyle(fontSize: 12),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: isLoading
                                      ? null
                                      : _requestPasswordReset,
                                  child: const Text(
                                    'Mot de passe oublié ?',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _primaryButton(
                              icon: Icons.login_rounded,
                              label: 'Se connecter',
                            ),
                            const SizedBox(height: 14),
                            const Row(
                              children: [
                                Expanded(child: Divider()),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('OU'),
                                ),
                                Expanded(child: Divider()),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _secondaryButton(
                              label: 'Créer un compte',
                              onPressed: _switchMode,
                            ),
                          ] else ...[
                            _field(
                              controller: pseudoController,
                              label: 'Pseudo',
                              icon: Icons.person_outline_rounded,
                              inputAction: TextInputAction.next,
                            ),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: EdgeInsets.only(left: 12, top: 4),
                                child: Text(
                                  'Le pseudo doit être unique',
                                  style: TextStyle(
                                    color: Color(0xFF8290A5),
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _field(
                              controller: emailController,
                              label: 'Email',
                              icon: Icons.mail_outline_rounded,
                              keyboardType: TextInputType.emailAddress,
                              inputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                            ),
                            const SizedBox(height: 12),
                            _passwordField(
                              controller: passwordController,
                              label: 'Mot de passe',
                              hidden: hidePassword,
                              onToggle: () =>
                                  setState(() => hidePassword = !hidePassword),
                            ),
                            const SizedBox(height: 12),
                            _passwordField(
                              controller: confirmPasswordController,
                              label: 'Confirmer le mot de passe',
                              hidden: hideConfirmPassword,
                              onToggle: () => setState(
                                () =>
                                    hideConfirmPassword = !hideConfirmPassword,
                              ),
                              onSubmitted: (_) => isLoading ? null : submit(),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Checkbox(
                                  value: acceptTerms,
                                  onChanged: (value) => setState(
                                    () => acceptTerms = value ?? false,
                                  ),
                                ),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      text: 'J’accepte les ',
                                      children: [
                                        TextSpan(
                                          text: 'Conditions d’utilisation',
                                          style: const TextStyle(
                                            color: Color(0xFF2493FF),
                                            decoration:
                                                TextDecoration.underline,
                                            decorationColor: Color(0xFF2493FF),
                                          ),
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = isLoading
                                                ? null
                                                : _showTermsOfUse,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 48),
                                child: Text.rich(
                                  TextSpan(
                                    text: 'Politique de confidentialité',
                                    style: const TextStyle(
                                      color: Color(0xFF2493FF),
                                      decoration: TextDecoration.underline,
                                      decorationColor: Color(0xFF2493FF),
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = isLoading
                                          ? null
                                          : _showPrivacyPolicy,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _primaryButton(
                              icon: Icons.person_add_alt_1_rounded,
                              label: 'Créer mon compte',
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: isLoading ? null : _switchMode,
                              child: const Text.rich(
                                TextSpan(
                                  text: 'Déjà un compte ? ',
                                  style: TextStyle(color: Colors.white70),
                                  children: [
                                    TextSpan(
                                      text: 'Se connecter',
                                      style: TextStyle(
                                        color: Color(0xFF2493FF),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordRecoveryPage() {
    return Scaffold(
      body: Stack(
        children: [
          const _GridBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF071426),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF34506F)),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 28,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            height: 120,
                            child: Image.asset(
                              'assets/images/rc_logo_login_hd.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'NOUVEAU MOT DE PASSE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Choisis un nouveau mot de passe pour ton compte RC Companion.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, height: 1.4),
                        ),
                        const SizedBox(height: 20),
                        _passwordField(
                          controller: passwordController,
                          label: 'Nouveau mot de passe',
                          hidden: hidePassword,
                          onToggle: () =>
                              setState(() => hidePassword = !hidePassword),
                        ),
                        const SizedBox(height: 12),
                        _passwordField(
                          controller: confirmPasswordController,
                          label: 'Confirmer le nouveau mot de passe',
                          hidden: hideConfirmPassword,
                          onToggle: () => setState(
                            () => hideConfirmPassword = !hideConfirmPassword,
                          ),
                          onSubmitted: (_) =>
                              isLoading ? null : _saveNewPassword(),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: isLoading ? null : _saveNewPassword,
                            icon: isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.lock_reset_rounded),
                            label: const Text(
                              'Enregistrer le nouveau mot de passe',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailVerificationPage() {
    final email = pendingVerificationEmail ?? '';

    return Scaffold(
      body: Stack(
        children: [
          const _GridBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF071426),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF34506F)),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 28,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.mark_email_unread_outlined,
                          size: 54,
                          color: Color(0xFF2493FF),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'VALIDE TON ADRESSE E-MAIL',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Ton compte RC Companion a été créé.\n'
                          'Un e-mail de validation a été envoyé à :',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          email,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF2493FF),
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Ouvre cet e-mail et clique sur le lien de validation. '
                          'Tu pourras ensuite revenir dans RC Companion et te connecter.',
                          textAlign: TextAlign.center,
                          style: TextStyle(height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFF59E0B,
                            ).withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(
                                0xFFF59E0B,
                              ).withValues(alpha: .55),
                            ),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: Color(0xFFF59E0B),
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Tu ne trouves pas l’e-mail ? Vérifie le dossier '
                                  'Indésirables / Spam. La réception peut aussi '
                                  'prendre quelques instants.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    height: 1.35,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: isLoading
                                ? null
                                : _resendVerificationEmail,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            icon: isLoading
                                ? const SizedBox(
                                    width: 19,
                                    height: 19,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded),
                            label: const Text(
                              'Renvoyer l’e-mail de validation',
                              textAlign: TextAlign.center,
                              softWrap: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: isLoading
                                ? null
                                : _editVerificationEmail,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Corriger l’adresse e-mail'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: isLoading
                              ? null
                              : _backToLoginFromVerification,
                          icon: const Icon(Icons.login_rounded),
                          label: const Text('Retour à la connexion'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction? inputAction,
    Iterable<String>? autofillHints,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: inputAction,
      autofillHints: autofillHints,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool hidden,
    required VoidCallback onToggle,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: hidden,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }

  Widget _primaryButton({required IconData icon, required String label}) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton.icon(
        onPressed: isLoading ? null : submit,
        icon: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        label: Text(label),
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        child: Text(label),
      ),
    );
  }
}

class _GridBackground extends StatelessWidget {
  const _GridBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _GridPainter(),
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.2,
              colors: [Color(0xFF14315A), Color(0xFF07111F), Color(0xFF030913)],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF294565).withValues(alpha: .18)
      ..strokeWidth = .7;

    const step = 64.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
