import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/web3_identity.dart';

/// Create an account or sign in: email + password, phone + password (the
/// number is confirmed by SMS when signing up), or Google.
class AuthScreen extends StatefulWidget {
  final bool startWithSignUp;

  const AuthScreen({super.key, this.startWithSignUp = true});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _Method { email, phone }

class _AuthScreenState extends State<AuthScreen> {
  late bool _signUp = widget.startWithSignUp;
  _Method _method = _Method.email;
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  String? _verificationId;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(AuthService auth) action) async {
    final auth = context.read<AuthService>();
    final lock = context.read<BiometricLock>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(auth);
      if (!mounted) return;
      if (auth.user != null) {
        final offerLock = _signUp && await lock.supported;
        if (!mounted) return;
        if (offerLock) await _offerBiometrics(lock);
        if (!mounted) return;
        // The app root switches to the timeline once signed in.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _offerBiometrics(BiometricLock lock) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlock with fingerprint or face?'),
        content: const Text(
          'Ask for your fingerprint, face or screen lock each time the app '
          'opens. You can change this in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
    if (yes == true) await lock.setEnabled(true);
  }

  String? _checkPassword() {
    if (_password.text.length < 8) {
      return 'Use a password of at least 8 characters.';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _signUp ? _checkPassword() : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (_method == _Method.email) {
      await _run(
        (auth) => _signUp
            ? auth.signUpWithEmail(_email.text, _password.text)
            : auth.signInWithEmail(_email.text, _password.text),
      );
      return;
    }
    if (!_signUp) {
      await _run((auth) => auth.signInWithPhone(_phone.text, _password.text));
      return;
    }
    if (_verificationId == null) {
      await _run((auth) async {
        final id = await auth.sendPhoneCode(_phone.text);
        if (mounted) setState(() => _verificationId = id);
      });
      return;
    }
    await _run(
      (auth) => auth.signUpWithPhone(
        phone: _phone.text,
        verificationId: _verificationId!,
        smsCode: _code.text,
        password: _password.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthService>();
    final awaitingCode =
        _signUp && _method == _Method.phone && _verificationId != null;
    final submitLabel = switch ((_signUp, _method, awaitingCode)) {
      (true, _Method.phone, false) => 'Send code',
      (true, _, _) => 'Create account',
      (false, _, _) => 'Sign in',
    };

    return Scaffold(
      appBar: AppBar(title: Text(_signUp ? 'Create account' : 'Sign in')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('New account')),
                ButtonSegment(value: false, label: Text('Sign in')),
              ],
              selected: {_signUp},
              onSelectionChanged: (v) => setState(() {
                _signUp = v.first;
                _verificationId = null;
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            SegmentedButton<_Method>(
              segments: const [
                ButtonSegment(
                  value: _Method.email,
                  icon: Icon(Icons.email_outlined),
                  label: Text('Email'),
                ),
                ButtonSegment(
                  value: _Method.phone,
                  icon: Icon(Icons.phone_outlined),
                  label: Text('Phone'),
                ),
              ],
              selected: {_method},
              onSelectionChanged: (v) => setState(() {
                _method = v.first;
                _verificationId = null;
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            if (_method == _Method.email)
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              )
            else
              TextField(
                controller: _phone,
                enabled: !awaitingCode,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+1 555 123 4567',
                  border: OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: [
                _signUp ? AutofillHints.newPassword : AutofillHints.password,
              ],
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: _signUp ? 'At least 8 characters' : null,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (awaitingCode) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: const InputDecoration(
                  labelText: 'Code from the SMS',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(submitLabel),
            ),
            if (!_signUp && _method == _Method.email)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run((auth) async {
                        await auth.sendPasswordReset(_email.text);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Password reset email sent.'),
                            ),
                          );
                        }
                      }),
                child: const Text('Forgot password?'),
              ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or'),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _run((a) => a.signInWithGoogle()),
              icon: const Icon(Icons.account_circle_outlined),
              label: const Text('Continue with Google'),
            ),
            const SizedBox(height: 16),
            _Web3Section(
              busy: _busy,
              onPick: (identity) => _run((a) => a.signInWithWeb3(identity)),
            ),
            if (auth.isReviewBuild) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run((a) => a.signInAsReviewer()),
                icon: const Icon(Icons.rate_review_outlined),
                label: const Text('Continue as reviewer (test build)'),
              ),
            ],
            if (!auth.available) ...[
              const SizedBox(height: 16),
              Text(
                'Account sign-up isn\'t connected in this build yet.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sign-in with a Web3 identity (crypto wallet or Farcaster), with a note
/// saying what these are and a plain-language explanation.
class _Web3Section extends StatelessWidget {
  final bool busy;
  final ValueChanged<Web3Identity> onPick;

  const _Web3Section({required this.busy, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.wallet_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'These are Web3 identities',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: () => showWeb3Explainer(context),
                  child: const Text('What is this?'),
                ),
              ],
            ),
            Text(
              'Sign in with a crypto wallet or Farcaster account you already '
              'have. Free, and never a payment.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final identity in web3Identities)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: OutlinedButton(
                  onPressed: busy ? null : () => onPick(identity),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Continue with ${identity.name}'),
                      Text(
                        identity.examples.join(', '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The "What is this?" explanation of Web3 identities.
Future<void> showWeb3Explainer(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('Web3 identities', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final (title, body) in web3Explainer) ...[
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(body),
                const SizedBox(height: 14),
              ],
              Text('Names we can show', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final name in web3NameServices) Text('• $name'),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ],
          ),
        );
      },
    );

/// Asks for fingerprint, face or screen lock before showing the app.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    // Ask straight away; the button is there if the user cancels.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<BiometricLock>().unlock(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.read<BiometricLock>();
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fingerprint,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text('EventLens is locked'),
            const SizedBox(height: 16),
            FilledButton(onPressed: lock.unlock, child: const Text('Unlock')),
            TextButton(
              onPressed: () => context.read<AuthService>().signOut(),
              child: const Text('Sign out instead'),
            ),
          ],
        ),
      ),
    );
  }
}
