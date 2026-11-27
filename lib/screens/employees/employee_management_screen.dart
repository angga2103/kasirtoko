import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/image_picker_cropper.dart';

class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() => _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AuthProvider>(context, listen: false).loadUsers(includeInactive: true);
    });
  }

  void _openEmployeeForm({UserModel? employee}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EmployeeFormScreen(employee: employee)),
    );
  }

  Future<void> _showSessionPoliciesDialog(AuthProvider auth) async {
    final values = <String, int>{
      for (final r in AppRoles.all)
        r: auth.sessionPolicies.where((p) => p.role == r).firstOrNull?.maxActiveSessions ??
            AppRoles.defaultMaxActiveSessions(r),
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          title: const Text('Kebijakan Batas Sesi per Role'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mengatur jumlah maksimum HP Staff aktif per akun secara bersamaan. Akun tetap dapat memiliki override khusus di form karyawan.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  ...AppRoles.all.map((role) {
                    final lockedOwner = role == AppRoles.owner && !auth.isOwner;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              AppRoles.displayName(role),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 96,
                            child: DropdownButtonFormField<int>(
                              value: values[role] ?? 1,
                              isExpanded: true,
                              isDense: true,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              items: [1, 2, 3, 4, 5]
                                  .map((n) => DropdownMenuItem<int>(
                                        value: n,
                                        child: Text('$n HP', maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ))
                                  .toList(),
                              onChanged: lockedOwner
                                  ? null
                                  : (v) {
                                      if (v != null) setDlgState(() => values[role] = v);
                                    },
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan Kebijakan'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;
    for (final role in AppRoles.all) {
      if (role == AppRoles.owner && !auth.isOwner) continue;
      await auth.updateRoleSessionPolicy(role, values[role] ?? 1);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kebijakan batas sesi per role berhasil diperbarui.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    if (!auth.hasPermission(AppPermissions.manageEmployees)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Manajemen Karyawan')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Akses ditolak. Hanya akun dengan izin Manajemen Karyawan yang dapat membuka halaman ini.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final users = auth.users;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Karyawan & Hak Akses'),
        actions: [
          IconButton(
            tooltip: 'Kebijakan Batas Sesi',
            icon: const Icon(Icons.devices_fold_rounded),
            onPressed: () => _showSessionPoliciesDialog(auth),
          ),
        ],
      ),
      body: users.isEmpty
          ? const Center(child: Text('Belum ada data karyawan.'))
          : ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final u = users[index];
                final photoFile = (u.photoPath != null && u.photoPath!.isNotEmpty)
                    ? File(u.photoPath!)
                    : null;
                final hasPhoto = photoFile != null && photoFile.existsSync();
                final activePermCount = u.permissions.values.where((v) => v).length;

                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: u.isActive ? AppTheme.primaryGreenSoft : Colors.grey.shade200,
                      backgroundImage: hasPhoto ? FileImage(photoFile) : null,
                      child: hasPhoto
                          ? null
                          : Icon(
                              Icons.person_rounded,
                              color: u.isActive ? AppTheme.primaryGreen : Colors.grey,
                            ),
                    ),
                    title: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          u.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: u.isActive ? null : TextDecoration.lineThrough,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: u.isOwner
                                ? Colors.amber.shade100
                                : (u.isActive ? AppTheme.primaryGreenSoft : Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            u.isActive ? u.roleDisplay : 'NONAKTIF',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: u.isOwner
                                  ? Colors.amber.shade900
                                  : (u.isActive ? AppTheme.primaryGreen : Colors.grey.shade700),
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'User: @${u.username.isEmpty ? "-" : u.username} • Telp: ${u.phone.isEmpty ? "-" : u.phone}\nHak akses: ${u.isOwner ? "Penuh (Owner)" : "$activePermCount / ${AppPermissions.labels.length}"} • Maks Sesi: ${auth.effectiveMaxSessionsFor(u)} HP${u.maxActiveSessions != null ? " (Khusus)" : ""}',
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (val) async {
                        if (val == 'edit') {
                          _openEmployeeForm(employee: u);
                        } else if (val == 'revoke_sessions') {
                          final msg = await auth.revokeAllSessionsForEmployee(u);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(msg ?? 'Semua sesi aktif milik ${u.name} telah dicabut.'),
                              backgroundColor: msg == null ? AppTheme.success : Colors.orange.shade800,
                            ),
                          );
                        } else if (val == 'toggle') {
                          final err = await auth.toggleEmployeeActive(u, !u.isActive);
                          if (err != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(err), backgroundColor: AppTheme.accentRed),
                            );
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit Profil & Hak Akses')),
                        const PopupMenuItem(
                          value: 'revoke_sessions',
                          child: Text('Cabut Semua Sesi Aktif'),
                        ),
                        if (!u.isOwner)
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text(u.isActive ? 'Nonaktifkan Akun' : 'Aktifkan Kembali'),
                          ),
                      ],
                    ),
                    onTap: () => _openEmployeeForm(employee: u),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        onPressed: () => _openEmployeeForm(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Tambah Karyawan'),
      ),
    );
  }
}

class EmployeeFormScreen extends StatefulWidget {
  final UserModel? employee;

  const EmployeeFormScreen({super.key, this.employee});

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _usernameCtrl;
  late TextEditingController _phoneCtrl;
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _pinCtrl = TextEditingController();
  late TextEditingController _maxSessionsCtrl;

  late String _role;
  late Map<String, bool> _permissions;
  String? _photoPath;
  bool _isActive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _usernameCtrl = TextEditingController(text: e?.username ?? '');
    _phoneCtrl = TextEditingController(text: e?.phone ?? '');
    _maxSessionsCtrl = TextEditingController(text: e?.maxActiveSessions?.toString() ?? '');
    _role = e?.role ?? AppRoles.cashier;
    _permissions = e != null
        ? Map<String, bool>.from(e.permissions)
        : AppPermissions.defaultForRole(_role);
    _photoPath = e?.photoPath;
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _pinCtrl.dispose();
    _maxSessionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final path = await ImagePickerHelper.pickAndCropImage(
      context,
      prefix: 'emp',
      title: 'Foto Profil Karyawan',
    );
    if (path != null && mounted) {
      setState(() => _photoPath = path);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final parsedMaxSessions = int.tryParse(_maxSessionsCtrl.text.trim());
    final err = await auth.saveEmployee(
      existingId: widget.employee?.id,
      name: _nameCtrl.text,
      username: _usernameCtrl.text,
      role: _role,
      phone: _phoneCtrl.text,
      newPassword: _passwordCtrl.text,
      newPin: _pinCtrl.text,
      photoPath: _photoPath,
      permissions: _permissions,
      isActive: _isActive,
      maxActiveSessions: parsedMaxSessions != null && parsedMaxSessions > 0 ? parsedMaxSessions : null,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppTheme.accentRed),
      );
    } else {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data karyawan berhasil disimpan!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isEdit = widget.employee != null;
    final isOwnerTarget = _role == AppRoles.owner;
    final photoFile = (_photoPath != null && _photoPath!.isNotEmpty) ? File(_photoPath!) : null;
    final hasPhoto = photoFile != null && photoFile.existsSync();

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Karyawan' : 'Tambah Karyawan Baru')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar section
                  Center(
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 44,
                              backgroundColor: AppTheme.primaryGreenSoft,
                              backgroundImage: hasPhoto ? FileImage(photoFile) : null,
                              child: hasPhoto
                                  ? null
                                  : const Icon(Icons.person_rounded, size: 44, color: AppTheme.primaryGreen),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: AppTheme.primaryGreen,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                                  onPressed: _pickPhoto,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (hasPhoto)
                          TextButton(
                            onPressed: () => setState(() => _photoPath = ''),
                            child: const Text('Hapus Foto', style: TextStyle(color: AppTheme.accentRed, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Identity Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Identitas & Akun Login', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(labelText: 'Nama Lengkap *'),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _usernameCtrl,
                                decoration: const InputDecoration(labelText: 'Username Login *'),
                                validator: (v) => v == null || v.trim().isEmpty ? 'Username wajib diisi' : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _phoneCtrl,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(labelText: 'Nomor Telepon / WA'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        AppBreakpoints.buildResponsivePair(
                          minPairWidth: 360,
                          spacing: 10,
                          first: TextFormField(
                            controller: _passwordCtrl,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: isEdit ? 'Password Baru (Opsional)' : 'Password *',
                              helperText: 'Disimpan ter-enkripsi (hash + salt)',
                            ),
                            validator: (v) {
                              if (!isEdit && (v == null || v.trim().length < 4)) {
                                return 'Min. 4 karakter';
                              }
                              return null;
                            },
                          ),
                          second: TextFormField(
                            controller: _pinCtrl,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: InputDecoration(
                              labelText: isEdit ? 'PIN Baru (4-6 digit)' : 'PIN Cepat (4-6 digit)',
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _role,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Level / Role Karyawan'),
                          items: AppRoles.all
                              .where((r) => auth.isOwner || r != AppRoles.owner)
                              .map((r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(AppRoles.displayName(r), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: isOwnerTarget && isEdit && !auth.isOwner
                              ? null
                              : (val) {
                                  if (val != null) {
                                    setState(() {
                                      _role = val;
                                      _permissions = AppPermissions.defaultForRole(val);
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _maxSessionsCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Batas Maks. Sesi HP Aktif (Opsional)',
                            hintText: 'Default role: ${AppRoles.defaultMaxActiveSessions(_role)} HP',
                            helperText:
                                'Kosongkan untuk mengikuti kebijakan role (${AppRoles.defaultMaxActiveSessions(_role)} HP)',
                          ),
                          validator: (v) {
                            final raw = (v ?? '').trim();
                            if (raw.isEmpty) return null;
                            final parsed = int.tryParse(raw);
                            if (parsed == null || parsed < 1 || parsed > 20) {
                              return 'Masukkan angka antara 1 sampai 20';
                            }
                            return null;
                          },
                        ),
                        if (isEdit && !isOwnerTarget)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Akun Aktif'),
                            subtitle: const Text('Nonaktifkan agar karyawan tidak bisa login'),
                            value: _isActive,
                            onChanged: (v) => setState(() => _isActive = v),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Granular Permissions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Hak Akses Granular', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            if (!isOwnerTarget)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _permissions = AppPermissions.defaultForRole(_role);
                                  });
                                },
                                child: const Text('Reset Bawaan Role'),
                              ),
                          ],
                        ),
                        if (isOwnerTarget)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Pemilik (Owner) secara otomatis memiliki akses penuh ke seluruh fitur.',
                              style: TextStyle(color: AppTheme.primaryGreen, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          )
                        else
                          ...AppPermissions.labels.entries.map((entry) {
                            return SwitchListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(entry.value, style: const TextStyle(fontSize: 13)),
                              value: _permissions[entry.key] ?? false,
                              activeColor: AppTheme.primaryGreen,
                              onChanged: (val) {
                                setState(() {
                                  _permissions[entry.key] = val;
                                });
                              },
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_rounded),
                      label: Text(_saving ? 'MENYIMPAN...' : 'SIMPAN DATA KARYAWAN'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
