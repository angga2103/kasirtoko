import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../models/audit_log.dart';
import '../database/db_helper.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _currentUser;
  List<UserModel> _users = [];
  bool _isLoading = false;

  UserModel? get currentUser => _currentUser;
  List<UserModel> get users => _users;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _currentUser != null;

  bool get isOwner => _currentUser?.isOwner ?? false;
  bool get isSupervisor => _currentUser?.isSupervisor ?? false;
  bool get isCashier => _currentUser?.isCashier ?? false;
  bool get isWarehouse => _currentUser?.isWarehouse ?? false;

  Future<void> loadUsers() async {
    _users = await DatabaseHelper.instance.getUsers();
    notifyListeners();
  }

  Future<bool> loginWithPin(String pin) async {
    _isLoading = true;
    notifyListeners();

    final user = await DatabaseHelper.instance.login(pin);
    _isLoading = false;

    if (user != null) {
      _currentUser = user;
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }

  Future<void> logAction(String actionType, String details) async {
    if (_currentUser == null) return;
    final log = AuditLogModel(
      timestamp: DateTime.now(),
      userId: _currentUser!.id ?? 0,
      userName: _currentUser!.name,
      userRole: _currentUser!.role,
      actionType: actionType,
      details: details,
    );
    await DatabaseHelper.instance.insertAuditLog(log);
  }
}
