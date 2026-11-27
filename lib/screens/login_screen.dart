import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_theme.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _usePinMode = false;
  String _pin = '';
  String? _errorMessage;

  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _onKeyPress(String val) {
    if (_pin.length < 6) {
      setState(() {
        _pin += val;
        _errorMessage = null;
      });
    }
  }

  void _onBackspace() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _errorMessage = null;
      });
    }
  }

  void _onClear() {
    setState(() {
      _pin = '';
      _errorMessage = null;
    });
  }

  Future<void> _attemptPinLogin() async {
    if (_pin.length < 4) {
      setState(() => _errorMessage = 'Masukkan minimal 4 digit PIN karyawan.');
      return;
    }
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final success = await auth.loginWithPin(_pin);

    if (!mounted) return;
    if (success) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() {
        _errorMessage = auth.lastAuthError ?? 'PIN tidak sesuai atau akun sedang dinonaktifkan.';
        _pin = '';
      });
    }
  }

  Future<void> _attemptPasswordLogin() async {
    final user = _usernameCtrl.text.trim();
    final pass = _passwordCtrl.text;
    if (user.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = 'Username dan password wajib diisi.');
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final success = await auth.loginWithPassword(user, pass);

    if (!mounted) return;
    if (success) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() => _errorMessage = auth.lastAuthError ?? 'Username atau password salah.');
    }
  }

  void _showPasswordRecoveryDialog() {
    final ownerUserCtrl = TextEditingController();
    final ownerSecretCtrl = TextEditingController();
    final targetUserCtrl = TextEditingController();
    final newPwCtrl = TextEditingController();
    final newPinCtrl = TextEditingController();
    String? dialogErr;
    bool busy = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_reset_rounded, color: AppTheme.primaryGreen),
              SizedBox(width: 8),
              Flexible(child: Text('Pemulihan Password / PIN')),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Otorisasi diperlukan. Masukkan kredensial akun Pemilik (Owner) aktif untuk mereset password atau PIN karyawan secara aman.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ownerUserCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Username Pemilik (Owner) *',
                      prefixIcon: Icon(Icons.verified_user_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: ownerSecretCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password atau PIN Owner *',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                  ),
                  const Divider(height: 20),
                  TextField(
                    controller: targetUserCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Username Akun yang Dipulihkan *',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: newPwCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password Baru (min. 4 karakter) *',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: newPinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'PIN Cepat Baru (4-6 digit, opsional)',
                      counterText: '',
                      prefixIcon: Icon(Icons.dialpad_rounded),
                    ),
                  ),
                  if (dialogErr != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      dialogErr!,
                      style: const TextStyle(color: AppTheme.accentRed, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDState(() {
                        busy = true;
                        dialogErr = null;
                      });
                      final err = await Provider.of<AuthProvider>(context, listen: false).recoverPasswordByOwner(
                        ownerUsername: ownerUserCtrl.text,
                        ownerSecret: ownerSecretCtrl.text,
                        targetUsername: targetUserCtrl.text,
                        newPassword: newPwCtrl.text,
                        newPin: newPinCtrl.text,
                      );
                      if (err != null) {
                        setDState(() {
                          busy = false;
                          dialogErr = err;
                        });
                      } else if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text('Password / PIN akun berhasil diperbarui. Silakan login kembali.'),
                            backgroundColor: AppTheme.success,
                          ),
                        );
                      }
                    },
              child: Text(busy ? 'MEMPROSES...' : 'Simpan Password Baru'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      Future.delayed(const Duration(milliseconds: 300), () {
        ownerUserCtrl.dispose();
        ownerSecretCtrl.dispose();
        targetUserCtrl.dispose();
        newPwCtrl.dispose();
        newPinCtrl.dispose();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final auth = Provider.of<AuthProvider>(context);
    final logoFile = settings.logoPath.isNotEmpty ? File(settings.logoPath) : null;
    final hasLogo = logoFile != null && logoFile.existsSync();
    final isWideTablet = MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;

    final brandPanel = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isWideTablet ? 96 : 76,
          height: isWideTablet ? 96 : 76,
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.primaryGreenLight.withValues(alpha: 0.5), width: 2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryGreen.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: hasLogo
              ? Image.file(logoFile, fit: BoxFit.contain)
              : Image.asset(
                  'assets/branding/kasirtoko_admin_logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.point_of_sale_rounded, size: 42, color: AppTheme.primaryGreen),
                ),
        ),
        const SizedBox(height: 14),
        Text(
          settings.storeName,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isWideTablet ? 24 : 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${settings.businessType.label} • ${settings.branchName}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: Colors.white70),
        ),
      ],
    );

    final authCard = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Masuk ke Sistem Kasir',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 4),
          const Text(
            'Autentikasi karyawan terenkripsi untuk memulai operasional',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 16),

          // Minimalist segmented switch: Username & Password vs PIN
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.lightGreyBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _ModeTab(
                    label: 'Password',
                    icon: Icons.lock_outline_rounded,
                    selected: !_usePinMode,
                    onTap: () => setState(() {
                      _usePinMode = false;
                      _errorMessage = null;
                    }),
                  ),
                ),
                Expanded(
                  child: _ModeTab(
                    label: 'PIN Cepat',
                    icon: Icons.dialpad_rounded,
                    selected: _usePinMode,
                    onTap: () => setState(() {
                      _usePinMode = true;
                      _errorMessage = null;
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (!_usePinMode) ...[
            TextField(
              controller: _usernameCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Username Karyawan',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _attemptPasswordLogin(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.accentRed,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: auth.isLoading ? null : _attemptPasswordLogin,
              icon: const Icon(Icons.login_rounded),
              label: Text(auth.isLoading ? 'MEMVERIFIKASI...' : 'MASUK'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                final filled = index < _pin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? AppTheme.primaryGreen : Colors.grey.shade200,
                    border: Border.all(
                      color: filled ? AppTheme.primaryGreen : Colors.grey.shade400,
                      width: 1.5,
                    ),
                  ),
                );
              }),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.accentRed,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 16),
            _buildKeyRow(['1', '2', '3']),
            const SizedBox(height: 8),
            _buildKeyRow(['4', '5', '6']),
            const SizedBox(height: 8),
            _buildKeyRow(['7', '8', '9']),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(icon: Icons.clear_rounded, onTap: _onClear, label: 'C'),
                _buildNumberButton('0'),
                _buildActionButton(icon: Icons.backspace_rounded, onTap: _onBackspace),
              ],
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: auth.isLoading ? null : _attemptPinLogin,
              icon: const Icon(Icons.login_rounded),
              label: Text(auth.isLoading ? 'MEMVERIFIKASI...' : 'MASUK DENGAN PIN'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],

          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _showPasswordRecoveryDialog,
            icon: const Icon(Icons.lock_reset_rounded, size: 17, color: AppTheme.textSecondary),
            label: const Text(
              'Lupa Password atau PIN? Pulihkan dengan Otorisasi Owner',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF134E4A)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWideTablet ? 860 : 420),
                child: isWideTablet
                    ? Row(
                        children: [
                          Expanded(flex: 5, child: Padding(padding: const EdgeInsets.all(16), child: brandPanel)),
                          const SizedBox(width: 24),
                          Expanded(flex: 6, child: authCard),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          brandPanel,
                          const SizedBox(height: 22),
                          authCard,
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeyRow(List<String> numbers) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: numbers.map((n) => _buildNumberButton(n)).toList(),
    );
  }

  Widget _buildNumberButton(String text) {
    return InkWell(
      onTap: () => _onKeyPress(text),
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.lightGreyBg,
          border: Border.all(color: AppTheme.borderLight),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: AppTheme.textDark),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    String? label,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey.shade100,
        ),
        alignment: Alignment.center,
        child: label != null
            ? Text(
                label,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
              )
            : Icon(icon, color: AppTheme.textSecondary, size: 20),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: selected ? Colors.white : AppTheme.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
