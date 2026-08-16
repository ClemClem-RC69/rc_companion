import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/supabase_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

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
                                  onPressed: () => _showMessage(
                                    'La récupération du mot de passe sera ajoutée ensuite.',
                                  ),
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
                                const Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      text: 'J’accepte les ',
                                      children: [
                                        TextSpan(
                                          text: 'Conditions d’utilisation',
                                          style: TextStyle(
                                            color: Color(0xFF2493FF),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
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
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: isLoading
                                ? null
                                : _resendVerificationEmail,
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
                        const SizedBox(height: 8),
                        const Text(
                          'Si tu ne vois pas l’e-mail, vérifie également le dossier spam ou courrier indésirable.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF8290A5),
                            fontSize: 11,
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
