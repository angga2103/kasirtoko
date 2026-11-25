import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/audit_log.dart';
import '../models/user.dart';
import '../utils/security_helper.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _currentUser;
  List<UserModel> _users = [];
  bool _isLoading = false;

  UserModel? get currentUser => _currentUser;
  List<UserModel> get users => _users;
  List<UserModel> get activeUsers => _users.where((u) => u.isActive).toList();
  List<UserModel> get technicians => _users
      .where((u) => u.isActive && (u.isTechnician || u.hasPermission(AppPermissions.manageService)))
      .toList();
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _currentUser != null;

  bool get isOwner => _currentUser?.isOwner ?? false;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isSupervisor => _currentUser?.isSupervisor ?? false;
  bool get isCashier => _currentUser?.isCashier ?? false;
  bool get isWarehouse => _currentUser?.isWarehouse ?? false;
  bool get isTechnician => _currentUser?.isTechnician ?? false;
  bool get isDelivery => _currentUser?.isDelivery ?? false;

  bool hasPermission(String permissionKey) {
    if (_currentUser == null) return false;
    return _currentUser!.hasPermission(permissionKey);
  }

  Future<void> loadUsers({bool includeInactive = true}) async {
    _users = await DatabaseHelper.instance.getUsers(includeInactive: includeInactive);
    notifyListeners();
  }

  Future<bool> loginWithPin(String pin) async {
    _isLoading = true;
    notifyListeners();

    final user = await DatabaseHelper.instance.loginWithPin(pin);
    _isLoading = false;

    if (user != null) {
      _currentUser = user;
      await logAction('login', 'Login via PIN oleh ${user.name} (${user.roleDisplay})');
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  Future<bool> loginWithPassword(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    final user = await DatabaseHelper.instance.loginWithPassword(username, password);
    _isLoading = false;

    if (user != null) {
      _currentUser = user;
      await logAction('login', 'Login via username ($username) oleh ${user.name}');
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  void logout() {
    if (_currentUser != null) {
      logAction('logout', 'Logout akun ${_currentUser!.name}');
    }
    _currentUser = null;
    notifyListeners();
  }

  Future<String?> saveEmployee({
    int? existingId,
    required String name,
    required String username,
    required String role,
    required String phone,
    String? newPassword,
    String? newPin,
    String? photoPath,
    required Map<String, bool> permissions,
    bool isActive = true,
  }) async {
    if (!hasPermission(AppPermissions.manageEmployees)) {
      return 'Anda tidak memiliki hak akses manajemen karyawan.';
    }

    // Security check: non-owner cannot grant owner role or modify their own permissions
    if (role == AppRoles.owner && !isOwner) {
      return 'Hanya Owner yang dapat membuat atau mengubah akun Owner.';
    }
    if (existingId != null && existingId == _currentUser?.id && !isOwner) {
      return 'Karyawan tidak diperbolehkan mengubah hak akses atau level akun sendiri.';
    }

    final existing = existingId != null
        ? _users.firstWhere((u) => u.id == existingId, orElse: () => UserModel(name: name, role: role))
        : null;

    final cleanUsername = username.trim().toLowerCase();
    if (cleanUsername.isEmpty) return 'Username wajib diisi.';

    // Check username uniqueness
    final conflict = _users.any(
      (u) => u.username.toLowerCase() == cleanUsername && u.id != existingId,
    );
    if (conflict) return 'Username "$cleanUsername" sudah dipakai karyawan lain.';

    String salt = existing?.passwordSalt ?? '';
    if (salt.isEmpty) salt = SecurityHelper.generateSalt();

    String pwHash = existing?.passwordHash ?? '';
    String pHash = existing?.pinHash ?? '';

    if (newPassword != null && newPassword.trim().isNotEmpty) {
      pwHash = SecurityHelper.hashSecret(newPassword.trim(), salt);
    } else if (existingId == null) {
      return 'Password wajib diisi untuk karyawan baru.';
    }

    if (newPin != null && newPin.trim().isNotEmpty) {
      pHash = SecurityHelper.hashSecret(newPin.trim(), salt);
    } else if (pHash.isEmpty && newPassword != null && newPassword.trim().isNotEmpty) {
      pHash = SecurityHelper.hashSecret(newPassword.trim(), salt);
    }

    final finalPermissions = role == AppRoles.owner
        ? AppPermissions.allTrue()
        : Map<String, bool>.from(permissions);

    final user = UserModel(
      id: existingId,
      name: name.trim(),
      username: cleanUsername,
      passwordHash: pwHash,
      passwordSalt: salt,
      pin: '',
      pinHash: pHash,
      role: role,
      phone: phone.trim(),
      photoPath: photoPath ?? existing?.photoPath,
      permissions: finalPermissions,
      isActive: isActive,
    );

    if (existingId == null) {
      await DatabaseHelper.instance.insertUser(user);
      await logAction('karyawan_tambah', 'Menambahkan karyawan ${user.name} (${AppRoles.displayName(role)})');
    } else {
      await DatabaseHelper.instance.updateUser(user);
      if (_currentUser?.id == existingId) {
        _currentUser = user;
      }
      await logAction('karyawan_ubah', 'Memperbarui data/hak akses karyawan ${user.name} (${AppRoles.displayName(role)})');
    }

    await loadUsers(includeInactive: true);
    return null;
  }

  Future<String?> toggleEmployeeActive(UserModel target, bool isActive) async {
    if (!hasPermission(AppPermissions.manageEmployees)) {
      return 'Tidak memiliki izin mengelola karyawan.';
    }
    if (target.id == _currentUser?.id) {
      return 'Tidak dapat menonaktifkan akun Anda sendiri yang sedang login.';
    }
    if (target.isOwner && !isActive) {
      return 'Akun Pemilik (Owner) tidak dapat dinonaktifkan.';
    }
    await DatabaseHelper.instance.setUserActive(target.id!, isActive);
    await logAction(
      isActive ? 'karyawan_aktif' : 'karyawan_nonaktif',
      '${isActive ? "Mengaktifkan" : "Menonaktifkan"} karyawan ${target.name}',
    );
    await loadUsers(includeInactive: true);
    return null;
  }

  /// Self-service password / PIN update requiring current secret verification.
  Future<String?> changeOwnCredentials({
    required String currentSecret,
    String? newPassword,
    String? newPin,
  }) async {
    final me = _currentUser;
    if (me == null || me.id == null) return 'Sesi login tidak ditemukan.';

    final validPw = me.passwordHash.isNotEmpty &&
        me.passwordSalt.isNotEmpty &&
        SecurityHelper.verifySecret(currentSecret, me.passwordSalt, me.passwordHash);
    final validPin = me.pinHash.isNotEmpty &&
        me.passwordSalt.isNotEmpty &&
        SecurityHelper.verifySecret(currentSecret, me.passwordSalt, me.pinHash);
    if (!validPw && !validPin) {
      return 'Password atau PIN saat ini tidak cocok.';
    }

    final cleanPw = newPassword?.trim() ?? '';
    final cleanPin = newPin?.trim() ?? '';
    if (cleanPw.isEmpty && cleanPin.isEmpty) {
      return 'Masukkan password baru atau PIN baru.';
    }
    if (cleanPw.isNotEmpty && cleanPw.length < 4) {
      return 'Password baru minimal 4 karakter.';
    }
    if (cleanPin.isNotEmpty && (cleanPin.length < 4 || cleanPin.length > 6)) {
      return 'PIN baru harus 4 sampai 6 digit.';
    }

    final newSalt = SecurityHelper.generateSalt();
    final updatedPwHash = cleanPw.isNotEmpty
        ? SecurityHelper.hashSecret(cleanPw, newSalt)
        : SecurityHelper.hashSecret(currentSecret, newSalt);
    final updatedPinHash = cleanPin.isNotEmpty
        ? SecurityHelper.hashSecret(cleanPin, newSalt)
        : (validPin ? SecurityHelper.hashSecret(currentSecret, newSalt) : updatedPwHash);

    final updated = me.copyWith(
      passwordSalt: newSalt,
      passwordHash: updatedPwHash,
      pinHash: updatedPinHash,
      pin: '',
    );

    await DatabaseHelper.instance.updateUser(updated);
    _currentUser = updated;
    await logAction('ubah_password', 'Pengguna ${me.name} memperbarui kredensial akunnya secara mandiri.');
    await loadUsers(includeInactive: true);
    return null;
  }

  /// Offline password recovery authorized strictly by an active Owner account.
  Future<String?> recoverPasswordByOwner({
    required String ownerUsername,
    required String ownerSecret,
    required String targetUsername,
    required String newPassword,
    String? newPin,
  }) async {
    final cleanOwner = ownerUsername.trim().toLowerCase();
    final cleanTarget = targetUsername.trim().toLowerCase();
    if (cleanOwner.isEmpty || ownerSecret.isEmpty || cleanTarget.isEmpty || newPassword.trim().length < 4) {
      return 'Lengkapi kredensial Owner, username target, dan password baru (min. 4 karakter).';
    }

    UserModel? verifiedOwner = await DatabaseHelper.instance.loginWithPassword(cleanOwner, ownerSecret);
    verifiedOwner ??= await DatabaseHelper.instance.loginWithPin(ownerSecret);
    if (verifiedOwner == null || !verifiedOwner.isOwner) {
      return 'Otorisasi gagal. Hanya kredensial Pemilik (Owner) yang valid untuk memulihkan akun.';
    }

    final allUsers = await DatabaseHelper.instance.getUsers(includeInactive: true);
    final idx = allUsers.indexWhere((u) => u.username.toLowerCase() == cleanTarget);
    if (idx == -1) {
      return 'Username "$cleanTarget" tidak ditemukan.';
    }
    final target = allUsers[idx];
    final cleanPin = newPin?.trim() ?? '';
    if (cleanPin.isNotEmpty && (cleanPin.length < 4 || cleanPin.length > 6)) {
      return 'PIN baru harus 4 sampai 6 digit.';
    }

    final salt = SecurityHelper.generateSalt();
    final pwHash = SecurityHelper.hashSecret(newPassword.trim(), salt);
    final pinHash = SecurityHelper.hashSecret(cleanPin.isNotEmpty ? cleanPin : newPassword.trim(), salt);

    final updated = target.copyWith(
      passwordSalt: salt,
      passwordHash: pwHash,
      pinHash: pinHash,
      pin: '',
    );
    await DatabaseHelper.instance.updateUser(updated);
    await DatabaseHelper.instance.insertAuditLog(
      AuditLogModel(
        timestamp: DateTime.now(),
        userId: verifiedOwner.id ?? 0,
        userName: verifiedOwner.name,
        userRole: verifiedOwner.role,
        actionType: 'pemulihan_password',
        module: 'Autentikasi',
        objectId: 'USER-${target.id}',
        details: 'Pemulihan akun "@${target.username}" disetujui oleh Owner ${verifiedOwner.name}.',
      ),
    );
    return null;
  }

  Future<void> logAction(
    String actionType,
    String details, {
    String? module,
    String objectId = '',
    String beforeValue = '',
    String afterValue = '',
  }) async {
    if (_currentUser == null) return;
    final log = AuditLogModel(
      timestamp: DateTime.now(),
      userId: _currentUser!.id ?? 0,
      userName: _currentUser!.name,
      userRole: _currentUser!.role,
      actionType: actionType,
      module: module,
      objectId: objectId,
      beforeValue: beforeValue,
      afterValue: afterValue,
      details: details,
    );
    await DatabaseHelper.instance.insertAuditLog(log);
  }
}
