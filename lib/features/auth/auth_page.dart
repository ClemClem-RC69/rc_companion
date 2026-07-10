import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoginMode = true;
  bool isLoading = false;
  bool hidePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.length < 6) {
      showMessage(
        'Indique un e-mail valide et un mot de passe de 6 caractères minimum.',
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

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
          showMessage(
            'Compte créé. Vérifie ton e-mail avant de te connecter.',
          );
        }
      }
    } on AuthException catch (error) {
      showMessage(error.message);
    } catch (_) {
      showMessage('Une erreur inattendue est survenue.');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.sports_motorsports,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'RC Companion',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isLoginMode
                          ? 'Connexion'
                          : 'Créer un compte',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Adresse e-mail',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: passwordController,
                      obscureText: hidePassword,
                      autofillHints: isLoginMode
                          ? const [AutofillHints.password]
                          : const [AutofillHints.newPassword],
                      onSubmitted: (_) => isLoading ? null : submit(),
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              hidePassword = !hidePassword;
                            });
                          },
                          icon: Icon(
                            hidePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                    ),
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
                                ),
                              )
                            : Icon(
                                isLoginMode
                                    ? Icons.login
                                    : Icons.person_add,
                              ),
                        label: Text(
                          isLoginMode
                              ? 'Se connecter'
                              : 'Créer le compte',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: isLoading
                          ? null
                          : () {
                              setState(() {
                                isLoginMode = !isLoginMode;
                              });
                            },
                      child: Text(
                        isLoginMode
                            ? 'Je n’ai pas encore de compte'
                            : 'J’ai déjà un compte',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}