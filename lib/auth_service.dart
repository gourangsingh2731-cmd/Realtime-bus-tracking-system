import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> createUserByAdmin(
    String email,
    String password,
    String role,
    String name,
  ) async {
    try {
      final admin = _auth.currentUser;

      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final newUser = result.user;

      if (newUser != null) {
        await FirebaseDatabase.instance.ref("users/${newUser.uid}").set({
          "email": email,
          "role": role,
          "name": name,
        });
      }

      await _auth.signOut();

      await _auth.signInWithEmailAndPassword(
        email: admin!.email!,
        password: "Admin@01",
      );
    } catch (e) {
      print("Error creating user: $e");
    }
  }

  Future<User?> login(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } catch (e) {
      print("Login error: $e");
      return null;
    }
  }

  Future<User?> register(
    String email,
    String password,
    String role,
    String name,
  ) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = result.user;

      if (user != null) {
        await FirebaseDatabase.instance.ref("users/${user.uid}").set({
          "email": email,
          "role": role,
          "name": name,
        });
      }

      return user;
    } catch (e) {
      print("Register error: $e");
      return null;
    }
  }
}
