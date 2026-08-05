import 'package:bcrypt/bcrypt.dart';

class BcryptHelper {
  static String hashPassword(String password) {
    final salt = BCrypt.gensalt();
    return BCrypt.hashpw(password, salt);
  }

  static bool verifyPassword(String password, String hash) {
    return BCrypt.checkpw(password, hash);
  }
}
