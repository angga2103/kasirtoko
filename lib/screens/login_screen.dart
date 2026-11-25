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
  bool _usePasswordMode = false;
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
      setState(() => _errorMessage = 'Masukkan minimal 4 digit PIN.');
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
        _errorMessage = 'PIN tidak cocok atau akun nonaktif.';
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
      setState(() => _errorMessage = 'Username atau password salah.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final auth = Provider.of<AuthProvider>(context);
    final logoFile = settings.logoPath.isNotEmpty ? File(settings.logoPath) : null;
    final hasLogo = logoFile != null && logoFile.existsSync();

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    padding: hasLogo ? EdgeInsets.zero : const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.primaryGreenLight.withValues(alpha: 0.4)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasLogo
                        ? Image.file(logoFile, fit: BoxFit.cover)
                        : const Icon(
                            Icons.point_of_sale_rounded,
                            size: 46,
                            color: AppTheme.primaryGreenLight,
                          ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    settings.storeName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${settings.businessType.label} • ${settings.branchName}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                  ),
                  const SizedBox(height: 20),

                  // Mode Toggle (PIN Cepat vs Username & Password)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ModeTab(
                            label: 'PIN Cepat',
                            icon: Icons.dialpad_rounded,
                            selected: !_usePasswordMode,
                            onTap: () => setState(() {
                              _usePasswordMode = false;
                              _errorMessage = null;
                            }),
                          ),
                        ),
                        Expanded(
                          child: _ModeTab(
                            label: 'Username & Password',
                            icon: Icons.lock_outline_rounded,
                            selected: _usePasswordMode,
                            onTap: () => setState(() {
                              _usePasswordMode = true;
                              _errorMessage = null;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  if (!_usePasswordMode) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (index) {
                        final filled = index < _pin.length;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 7),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: filled ? AppTheme.primaryGreenLight : Colors.white24,
                            border: Border.all(
                              color: filled ? AppTheme.primaryGreenLight : Colors.white38,
                              width: 1.5,
                            ),
                          ),
                        );
                      }),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppTheme.accentRed,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Column(
                        children: [
                          _buildKeyRow(['1', '2', '3']),
                          const SizedBox(height: 10),
                          _buildKeyRow(['4', '5', '6']),
                          const SizedBox(height: 10),
                          _buildKeyRow(['7', '8', '9']),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildActionButton(icon: Icons.clear_rounded, onTap: _onClear, label: 'C'),
                              _buildNumberButton('0'),
                              _buildActionButton(icon: Icons.backspace_rounded, onTap: _onBackspace),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: auth.isLoading ? null : _attemptPinLogin,
                              icon: const Icon(Icons.login_rounded),
                              label: Text(auth.isLoading ? 'MEMERIKSA...' : 'MASUK DENGAN PIN'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryGreenLight,
                                foregroundColor: Colors.black87,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _usernameCtrl,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              hintText: 'Contoh: owner / kasir / teknisi',
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
                              style: const TextStyle(
                                color: AppTheme.accentRed,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: auth.isLoading ? null : _attemptPasswordLogin,
                              icon: const Icon(Icons.login_rounded),
                              label: Text(auth.isLoading ? 'MEMERIKSA...' : 'MASUK'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),

                  // Quick Login Chips for Demo/Testing
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Akses Cepat Akun Bawaan (PIN = Password awal):',
                          style: TextStyle(color: Colors.white70, fontSize: 11.5),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: [
                            _buildQuickRoleChip('Owner: 123456', '123456'),
                            _buildQuickRoleChip('Supervisor: 3333', '3333'),
                            _buildQuickRoleChip('Kasir: 1111', '1111'),
                            _buildQuickRoleChip('Gudang: 2222', '2222'),
                            _buildQuickRoleChip('Teknisi: 4444', '4444'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
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
      borderRadius: BorderRadius.circular(36),
      child: Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.09),
          border: Border.all(color: Colors.white12),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
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
      borderRadius: BorderRadius.circular(36),
      child: Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.04),
        ),
        alignment: Alignment.center,
        child: label != null
            ? Text(
                label,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white70),
              )
            : Icon(icon, color: Colors.white70, size: 22),
      ),
    );
  }

  Widget _buildQuickRoleChip(String label, String pin) {
    return InkWell(
      onTap: () {
        setState(() => _pin = pin);
        _attemptPinLogin();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.primaryGreen.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryGreenLight.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppTheme.primaryGreenLight,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
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
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : Colors.white60),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
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
