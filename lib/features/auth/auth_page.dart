import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/app.dart';
import '../../services/supabase_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLoginMode = true;
  bool isLoading = false;
  bool hidePassword = true;
  bool hideConfirmPassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (email.isEmpty || !email.contains('@')) {
      showMessage('Indique une adresse e-mail valide.');
      return;
    }

    if (password.length < 6) {
      showMessage('Le mot de passe doit contenir au moins 6 caractères.');
      return;
    }

    if (!isLoginMode && password != confirmPassword) {
      showMessage('Les deux mots de passe ne correspondent pas.');
      return;
    }

    setState(() => isLoading = true);

    try {
      if (isLoginMode) {
        await SupabaseService.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      } else {
        final response = await SupabaseService.client.auth.signUp(
          email: email,
          password: password,
        );

        if (response.session == null && mounted) {
          showMessage('Compte créé. Vérifie ton e-mail avant de te connecter.');
          setState(() => isLoginMode = true);
        }
      }
    } on AuthException catch (error) {
      showMessage(error.message);
    } catch (_) {
      showMessage('Une erreur inattendue est survenue.');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void switchMode() {
    FocusScope.of(context).unfocus();
    setState(() {
      isLoginMode = !isLoginMode;
      confirmPasswordController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _AuthBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                      child: AutofillGroup(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF070D18),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: RCColors.border,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AspectRatio(
                                  aspectRatio: 3 / 2,
                                  child: Image.asset(
                                    'assets/images/rc_companion_logo.png',
                                    fit: BoxFit.contain,
                                    alignment: Alignment.center,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              isLoginMode ? 'Connexion' : 'Créer un compte',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isLoginMode
                                  ? 'Retrouve ton garage RC et toutes tes données.'
                                  : 'Crée ton espace RC Companion personnel.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: RCColors.textSecondary),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'Adresse e-mail',
                                prefixIcon: Icon(Icons.alternate_email_rounded),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: passwordController,
                              obscureText: hidePassword,
                              textInputAction: isLoginMode
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                              autofillHints: isLoginMode
                                  ? const [AutofillHints.password]
                                  : const [AutofillHints.newPassword],
                              onSubmitted: isLoginMode
                                  ? (_) => isLoading ? null : submit()
                                  : null,
                              decoration: InputDecoration(
                                labelText: 'Mot de passe',
                                prefixIcon: const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                  tooltip: hidePassword
                                      ? 'Afficher le mot de passe'
                                      : 'Masquer le mot de passe',
                                  onPressed: () {
                                    setState(() => hidePassword = !hidePassword);
                                  },
                                  icon: Icon(
                                    hidePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                            if (!isLoginMode) ...[
                              const SizedBox(height: 14),
                              TextField(
                                controller: confirmPasswordController,
                                obscureText: hideConfirmPassword,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.newPassword],
                                onSubmitted: (_) => isLoading ? null : submit(),
                                decoration: InputDecoration(
                                  labelText: 'Confirmer le mot de passe',
                                  prefixIcon: const Icon(Icons.lock_reset_rounded),
                                  suffixIcon: IconButton(
                                    tooltip: hideConfirmPassword
                                        ? 'Afficher le mot de passe'
                                        : 'Masquer le mot de passe',
                                    onPressed: () {
                                      setState(
                                        () => hideConfirmPassword = !hideConfirmPassword,
                                      );
                                    },
                                    icon: Icon(
                                      hideConfirmPassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
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
                                    : Icon(
                                        isLoginMode
                                            ? Icons.login_rounded
                                            : Icons.person_add_alt_1_rounded,
                                      ),
                                label: Text(
                                  isLoginMode
                                      ? 'Se connecter'
                                      : 'Créer mon compte',
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: isLoading ? null : switchMode,
                                child: Text(
                                  isLoginMode
                                      ? 'Créer un compte'
                                      : 'J’ai déjà un compte',
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Vos modèles • Vos batteries • Vos sessions • Vos maintenances RC',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: RCColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
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
}

class _AuthBackground extends StatelessWidget {
  const _AuthBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.15,
            colors: [
              Color(0xFF17335F),
              RCColors.background,
              Color(0xFF050914),
            ],
          ),
        ),
        child: CustomPaint(painter: _GridPainter()),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 1;

    const step = 48.0;
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
