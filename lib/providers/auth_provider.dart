import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../database/multi_device_dao.dart';
import '../models/audit_log.dart';
import '../models/operational_models.dart';
import '../models/user.dart';
import '../utils/security_helper.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _currentUser;
  List<UserModel> _users = [];
  List<SessionPolicyModel> _sessionPolicies = [];
  bool _isLoading = false;
  String? _lastAuthError;

  UserModel? get currentUser => _currentUser;
  List<UserModel> get users => _users;
  List<SessionPolicyModel> get sessionPolicies => _sessionPolicies;
  List<UserModel> get activeUsers => _users.where((u) => u.isActive).toList();
  List<UserModel> get technicians => _users
      .where((u) => u.isActive && (u.isTechnician || u.hasPermission(AppPermissions.manageService)))
      .toList();
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _currentUser != null;
  String? get lastAuthError => _lastAuthError;

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
    _sessionPolicies = await DatabaseHelper.instance.getSessionPolicies();
    notifyListeners();
  }

  int effectiveMaxSessionsFor(UserModel user) {
    if (user.maxActiveSessions != null && user.maxActiveSessions! > 0) {
      return user.maxActiveSessions!;
    }
    final policy = _sessionPolicies.where((p) => p.role == user.role).firstOrNull;
    return policy?.maxActiveSessions ?? AppRoles.defaultMaxActiveSessions(user.role);
  }

  Future<String?> updateRoleSessionPolicy(String role, int maxSessions) async {
    if (!hasPermission(AppPermissions.manageEmployees)) {
      return 'Tidak memiliki izin mengelola kebijakan sesi karyawan.';
    }
    if (role == AppRoles.owner && !isOwner) {
      return 'Hanya Owner yang dapat mengubah batas sesi untuk role Owner.';
    }
    await DatabaseHelper.instance.upsertSessionPolicy(
      role,
      maxSessions,
      actorName: _currentUser?.name ?? 'Admin',
    );
    _sessionPolicies = await DatabaseHelper.instance.getSessionPolicies();
    notifyListeners();
    return null;
  }

  Future<String?> revokeAllSessionsForEmployee(UserModel target) async {
    if (!hasPermission(AppPermissions.manageEmployees) && !isOwner && !isAdmin) {
      return 'Tidak memiliki izin mencabut sesi karyawan.';
    }
    if (target.id == null) return 'ID karyawan tidak valid.';
    final revokedCount = await MultiDeviceDao().revokeAllSessionsForCashier(
      target.id!,
      actorName: _currentUser?.name ?? 'Admin',
      reason: 'Dicabut dari Manajemen Karyawan oleh ${_currentUser?.name ?? "Admin"}',
    );
    notifyListeners();
    return revokedCount == 0
        ? 'Tidak ada sesi terminal aktif untuk ${target.name}.'
        : null;
  }

  Future<bool> loginWithPin(String pin) async {
    _isLoading = true;
    _lastAuthError = null;
    notifyListeners();

    final res = await DatabaseHelper.instance.authenticateWithPin(pin);
    _isLoading = false;

    if (res.isSuccess && res.user != null) {
      _currentUser = res.user;
      await logAction('login', 'Login via PIN oleh ${res.user!.name} (${res.user!.roleDisplay})');
      notifyListeners();
      return true;
    }
    _lastAuthError = res.message.isNotEmpty ? res.message : 'PIN tidak sesuai atau akun sedang dinonaktifkan.';
    notifyListeners();
    return false;
  }

  Future<bool> loginWithPassword(String username, String password) async {
    _isLoading = true;
    _lastAuthError = null;
    notifyListeners();

    final res = await DatabaseHelper.instance.authenticateWithPassword(username, password);
    _isLoading = false;

    if (res.isSuccess && res.user != null) {
      _currentUser = res.user;
      await logAction('login', 'Login via username ($username) oleh ${res.user!.name}');
      notifyListeners();
      return true;
    }
    _lastAuthError = res.message.isNotEmpty ? res.message : 'Username atau password salah.';
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
    int? maxActiveSessions,
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

    String pwSalt = existing?.passwordSalt ?? '';
    String pwHash = existing?.passwordHash ?? '';
    String pSalt = existing?.pinSalt ?? '';
    String pHash = existing?.pinHash ?? '';
    String pLookup = existing?.pinLookupHash ?? '';
    String hashVersion = existing?.hashVersion ?? SecurityHelper.hashVersionV2Pbkdf2;

    if (newPassword != null && newPassword.trim().isNotEmpty) {
      final pwPair = await SecurityHelper.hashSecretV2(
        newPassword.trim(),
        domain: SecurityHelper.domainPassword,
      );
      pwSalt = pwPair.salt;
      pwHash = pwPair.hash;
      hashVersion = SecurityHelper.hashVersionV2Pbkdf2;
    } else if (existingId == null) {
      return 'Password wajib diisi untuk karyawan baru.';
    }

    final cleanNewPin = newPin?.trim() ?? '';
    if (cleanNewPin.isNotEmpty) {
      final inUse = await DatabaseHelper.instance.isPinAlreadyInUse(
        cleanNewPin,
        excludeUserId: existingId,
      );
      if (inUse) {
        return 'PIN ini sudah dipakai karyawan lain. Gunakan PIN unik per kasir.';
      }
      final pinPair = await SecurityHelper.hashSecretV2(
        cleanNewPin,
        domain: SecurityHelper.domainPin,
      );
      pSalt = pinPair.salt;
      pHash = pinPair.hash;
      pLookup = await SecurityHelper.computePinLookupDigest(cleanNewPin);
      hashVersion = SecurityHelper.hashVersionV2Pbkdf2;
    } else if (pHash.isEmpty && newPassword != null && newPassword.trim().isNotEmpty) {
      final fallbackPin = newPassword.trim();
      final pinPair = await SecurityHelper.hashSecretV2(
        fallbackPin,
        domain: SecurityHelper.domainPin,
      );
      pSalt = pinPair.salt;
      pHash = pinPair.hash;
      pLookup = await SecurityHelper.computePinLookupDigest(fallbackPin);
      hashVersion = SecurityHelper.hashVersionV2Pbkdf2;
    }

    final finalPermissions = role == AppRoles.owner
        ? AppPermissions.allTrue()
        : Map<String, bool>.from(permissions);

    final user = UserModel(
      id: existingId,
      name: name.trim(),
      username: cleanUsername,
      passwordHash: pwHash,
      passwordSalt: pwSalt,
      pin: '',
      pinHash: pHash,
      pinSalt: pSalt,
      hashVersion: hashVersion,
      pinLookupHash: pLookup,
      failedPinCount: existing?.failedPinCount ?? 0,
      pinLockedUntil: existing?.pinLockedUntil,
      role: role,
      phone: phone.trim(),
      photoPath: photoPath ?? existing?.photoPath,
      permissions: finalPermissions,
      isActive: isActive,
      maxActiveSessions: maxActiveSessions != null && maxActiveSessions > 0 ? maxActiveSessions : null,
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
    await DatabaseHelper.instance.setUserActive(
      target.id!,
      isActive,
      actorName: _currentUser?.name ?? 'Admin',
    );
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

    final pwCheck = await SecurityHelper.verifyCredential(
      secret: currentSecret,
      storedHash: me.passwordHash,
      legacyOrV2Salt: me.passwordSalt,
      expectedDomain: SecurityHelper.domainPassword,
    );
    ({bool valid, bool needsRehash}) pinCheck = (valid: false, needsRehash: false);
    if (!pwCheck.valid) {
      final effectivePinSalt = me.pinSalt.isNotEmpty ? me.pinSalt : me.passwordSalt;
      pinCheck = await SecurityHelper.verifyCredential(
        secret: currentSecret,
        storedHash: me.pinHash,
        legacyOrV2Salt: effectivePinSalt,
        expectedDomain: SecurityHelper.domainPin,
      );
    }
    if (!pwCheck.valid && !pinCheck.valid) {
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
    if (cleanPin.isNotEmpty) {
      final inUse = await DatabaseHelper.instance.isPinAlreadyInUse(cleanPin, excludeUserId: me.id);
      if (inUse) {
        return 'PIN ini sudah digunakan akun lain. Pilih PIN yang berbeda.';
      }
    }

    String updatedPwSalt = me.passwordSalt;
    String updatedPwHash = me.passwordHash;
    if (cleanPw.isNotEmpty || pwCheck.needsRehash) {
      final pwPair = await SecurityHelper.hashSecretV2(
        cleanPw.isNotEmpty ? cleanPw : currentSecret,
        domain: SecurityHelper.domainPassword,
      );
      updatedPwSalt = pwPair.salt;
      updatedPwHash = pwPair.hash;
    }

    String updatedPinSalt = me.pinSalt;
    String updatedPinHash = me.pinHash;
    String updatedLookup = me.pinLookupHash;
    if (cleanPin.isNotEmpty) {
      final pinPair = await SecurityHelper.hashSecretV2(
        cleanPin,
        domain: SecurityHelper.domainPin,
      );
      updatedPinSalt = pinPair.salt;
      updatedPinHash = pinPair.hash;
      updatedLookup = await SecurityHelper.computePinLookupDigest(cleanPin);
    } else if (pinCheck.valid && (pinCheck.needsRehash || updatedPinSalt.isEmpty)) {
      final pinPair = await SecurityHelper.hashSecretV2(
        currentSecret,
        domain: SecurityHelper.domainPin,
      );
      updatedPinSalt = pinPair.salt;
      updatedPinHash = pinPair.hash;
      updatedLookup = await SecurityHelper.computePinLookupDigest(currentSecret);
    }

    final bothV2 = SecurityHelper.isV2PhcHash(updatedPwHash) && SecurityHelper.isV2PhcHash(updatedPinHash);
    final updated = me.copyWith(
      passwordSalt: updatedPwSalt,
      passwordHash: updatedPwHash,
      pinSalt: updatedPinSalt,
      pinHash: updatedPinHash,
      pinLookupHash: updatedLookup,
      hashVersion: bothV2 ? SecurityHelper.hashVersionV2Pbkdf2 : me.hashVersion,
      failedPinCount: 0,
      clearPinLockedUntil: true,
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
    final targetPinPlain = cleanPin.isNotEmpty ? cleanPin : newPassword.trim();
    if (cleanPin.isNotEmpty) {
      final inUse = await DatabaseHelper.instance.isPinAlreadyInUse(cleanPin, excludeUserId: target.id);
      if (inUse) {
        return 'PIN baru sudah dipakai oleh karyawan lain.';
      }
    }

    final pwPair = await SecurityHelper.hashSecretV2(
      newPassword.trim(),
      domain: SecurityHelper.domainPassword,
    );
    final pinPair = await SecurityHelper.hashSecretV2(
      targetPinPlain,
      domain: SecurityHelper.domainPin,
    );
    final lookup = await SecurityHelper.computePinLookupDigest(targetPinPlain);

    final updated = target.copyWith(
      passwordSalt: pwPair.salt,
      passwordHash: pwPair.hash,
      pinSalt: pinPair.salt,
      pinHash: pinPair.hash,
      pinLookupHash: lookup,
      hashVersion: SecurityHelper.hashVersionV2Pbkdf2,
      failedPinCount: 0,
      clearPinLockedUntil: true,
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
