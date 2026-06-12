import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'driver_qr_screen.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'student_qr_scanner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  await FlutterBackgroundService().configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: (service) async {
        return true;
      },
    ),
  );

  runApp(const MyApp());
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  Geolocator.getPositionStream().listen((position) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseDatabase.instance.ref("bus_location/${user.uid}");

    final snapshot = await ref.get();

    //Only update if trip is running
    if (!snapshot.exists || snapshot.child("status").value != "Running") {
      return;
    }

    await ref.update({
      "latitude": position.latitude,
      "longitude": position.longitude,
      "time": DateTime.now().toIso8601String(),
    });
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController idController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;
  String errorText = '';

  Future<void> login() async {
    setState(() {
      isLoading = true;
    });

    try {
      final user = await AuthService().login(
        idController.text.trim(),
        passwordController.text.trim(),
      );

      if (user == null) {
        throw Exception("Login failed");
      }

      final snapshot = await FirebaseDatabase.instance
          .ref("users/${user.uid}")
          .get();

      if (!snapshot.exists) {
        throw Exception("User data not found");
      }

      String role = snapshot.child("role").value.toString();

      if (!mounted) return;

      if (role == "student") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const StudentHome()),
        );
      } else if (role == "driver") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DriverHome()),
        );
      }
    } catch (e) {
      String message = "Login failed";

      if (e is FirebaseAuthException) {
        if (e.code == 'user-not-found') {
          message = "No user found";
        } else if (e.code == 'wrong-password') {
          message = "Wrong password";
        }
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      setState(() {
        errorText = message;
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Column(
              children: [
                Icon(Icons.directions_bus, size: 60, color: Colors.blue),
                SizedBox(height: 10),
                Text(
                  "Smart Bus Tracker",
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                Text(
                  "Track Your College Bus in Real Time",
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 30),
            TextField(
              controller: idController,
              decoration: const InputDecoration(
                labelText: "User ID",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Password",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: isLoading ? null : login,
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Login"),
            ),
            const SizedBox(height: 15),
            Text(errorText, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  GoogleMapController? mapController;
  List<Map<String, dynamic>> busList = [];
  LatLng? busPosition;
  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  LatLng? previousPosition;
  String etaText = "Waiting for bus...";
  String busStatus = "Waiting...";
  BitmapDescriptor? busIcon;
  @override
  void initState() {
    super.initState();

    loadBusIcon();
    listenBusLocation();
  }

  Future<void> loadBusIcon() async {
    busIcon = await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/bus_icon.png',
    );

    setState(() {}); // refresh UI after loading icon
  }

  Future<void> calculateETA(LatLng busPos) async {
    try {
      // 1. Check location permission
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint("Location permissions are permanently denied");
        return;
      }

      // 2. Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      double studentLat = position.latitude;
      double studentLng = position.longitude;

      // 3. Calculate distance (in meters)
      double distance = Geolocator.distanceBetween(
        busPos.latitude,
        busPos.longitude,
        studentLat,
        studentLng,
      );

      // 4. Convert distance to ETA (assume avg speed = 30 km/h)
      double speed = 30 * 1000 / 3600; // m/s
      double timeInSeconds = distance / speed;
      double timeInMinutes = timeInSeconds / 60;

      debugPrint("Distance: ${distance.toStringAsFixed(2)} meters");
      debugPrint("ETA: ${timeInMinutes.toStringAsFixed(2)} minutes");
    } catch (e) {
      debugPrint("Error calculating ETA: $e");
    }
  }

  void animateBus(LatLng newPosition) {
    if (previousPosition == null) {
      previousPosition = newPosition;
      return;
    }

    double latDiff = (newPosition.latitude - previousPosition!.latitude) / 10;
    double lngDiff = (newPosition.longitude - previousPosition!.longitude) / 10;

    for (int i = 1; i <= 10; i++) {
      Future.delayed(Duration(milliseconds: i * 60), () {
        LatLng intermediate = LatLng(
          previousPosition!.latitude + latDiff * i,
          previousPosition!.longitude + lngDiff * i,
        );

        setState(() {
          markers = {
            Marker(
              markerId: const MarkerId("bus"),
              position: intermediate,
              icon: busIcon ?? BitmapDescriptor.defaultMarker,
              infoWindow: const InfoWindow(title: "College Bus"),
            ),
          };
        });
        mapController?.animateCamera(CameraUpdate.newLatLng(intermediate));
      });
    }
    previousPosition = newPosition;
  }

  void listenBusLocation() {
    FirebaseDatabase.instance.ref("bus_location").onValue.listen((event) {
      if (!event.snapshot.exists) return;

      Map data = Map<String, dynamic>.from(event.snapshot.value as Map);

      Set<Marker> newMarkers = {};
      List<Map<String, dynamic>> tempList = [];

      for (var driverId in data.keys) {
        var busData = data[driverId];

        if (busData == null || busData is! Map) continue;

        String status = (busData["status"] ?? "").toString();
        if (status.toLowerCase() != "running") continue;

        double lat = (busData["latitude"] ?? 0).toDouble();
        double lng = (busData["longitude"] ?? 0).toDouble();
        String name = busData["driverName"] ?? "Driver";

        LatLng position = LatLng(lat, lng);

        newMarkers.add(
          Marker(
            markerId: MarkerId(driverId),
            position: position,
            infoWindow: InfoWindow(title: name, snippet: "Status: $status"),
          ),
        );

        tempList.add({
          "driverId": driverId,
          "name": name,
          "lat": lat,
          "lng": lng,
          "status": status,
        });
      }

      setState(() {
        markers = newMarkers;
        busList = tempList;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Live Bus Tracker")),

      // ✅ Move FAB here (correct place)
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StudentQRScanner()),
          );
        },
        child: const Icon(Icons.qr_code_scanner),
      ),

      body: Stack(
        children: [
          // 🔥 GOOGLE MAP
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: busPosition ?? const LatLng(20.5937, 78.9629),
              zoom: 15,
            ),
            markers: markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onMapCreated: (controller) {
              mapController = controller;
            },
          ),

          // 🔥 CONDITIONAL UI (NO EMPTY SHEET)
          busList.isEmpty
              ? Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 5),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        "No buses running 🚫",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                )
              // BUS LIST SHEET
              : DraggableScrollableSheet(
                  initialChildSize: 0.2,
                  minChildSize: 0.1,
                  maxChildSize: 0.5,
                  builder: (context, scrollController) {
                    return Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: busList.length,
                        itemBuilder: (context, index) {
                          var bus = busList[index];

                          return ListTile(
                            leading: const Icon(
                              Icons.directions_bus,
                              color: Colors.blue,
                            ),
                            title: Text(bus["name"] ?? "Driver"),
                            subtitle: Text(
                              "Status: ${bus["status"]}",
                              style: TextStyle(
                                color: bus["status"] == "Running"
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                            onTap: () {
                              LatLng selected = LatLng(bus["lat"], bus["lng"]);

                              mapController?.animateCamera(
                                CameraUpdate.newLatLngZoom(selected, 17),
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  bool tripRunning = false;
  double totalDistance = 0;
  Position? previousPosition;
  double fuelAverage = 0;
  String tripStatusText = "Trip Stopped";
  DateTime? lastUpdate;

  StreamSubscription<Position>? positionStream;
  GoogleMapController? mapController;

  LatLng? currentPosition;
  Set<Marker> markers = {};

  Future<void> startTrip() async {
    if (tripRunning) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final String driverId = user.uid;

    // Get driver name
    final userSnapshot = await FirebaseDatabase.instance
        .ref("users/$driverId")
        .get();

    String driverName =
        userSnapshot.child("name").value?.toString() ?? "Driver";

    // Permission
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    // Background service
    final service = FlutterBackgroundService();
    await service.startService();

    await FirebaseDatabase.instance.ref("bus_location/$driverId").update({
      "status": "Running",
      "time": DateTime.now().toIso8601String(),
    });
    setState(() {
      tripRunning = true;
      tripStatusText = "🟢 Trip Started";
    });

    positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 10,
          ),
        ).listen((Position position) async {
          //  THROTTLE
          if (lastUpdate == null ||
              DateTime.now().difference(lastUpdate!) >
                  const Duration(seconds: 2)) {
            lastUpdate = DateTime.now();

            final LatLng newPosition = LatLng(
              position.latitude,
              position.longitude,
            );

            setState(() {
              currentPosition = newPosition;
            });

            //  Distance calculation (MOVE INSIDE)
            if (previousPosition != null) {
              double distance = Geolocator.distanceBetween(
                previousPosition!.latitude,
                previousPosition!.longitude,
                position.latitude,
                position.longitude,
              );

              totalDistance += distance;
            }

            previousPosition = position;

            try {
              await FirebaseDatabase.instance
                  .ref("bus_location/$driverId")
                  .update({
                    "latitude": position.latitude,
                    "longitude": position.longitude,
                    "driverName": driverName,
                    "time": DateTime.now().toIso8601String(),
                    "distance": totalDistance,
                  });
            } catch (e) {
              debugPrint("Firebase error: $e");
            }
          }

          //UI UPDATE (ALWAYS FAST)
          setState(() {
            currentPosition = LatLng(position.latitude, position.longitude);
          });
        });
  }

  //  STOP TRIP
  Future<void> stopTrip() async {
    positionStream?.cancel();
    positionStream = null;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String driverId = user.uid;

    await FirebaseDatabase.instance.ref("bus_location/$driverId").update({
      "status": "Stopped",
      "time": DateTime.now().toIso8601String(),
    });

    setState(() {
      tripRunning = false;
      tripStatusText = "🔴 Trip Stopped";
    });
  }

  @override
  void dispose() {
    positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Driver Map Panel")),

      body: Stack(
        children: [
          // 🔥 GOOGLE MAP
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: currentPosition ?? const LatLng(20.5937, 78.9629),
              zoom: 15,
            ),
            markers: markers,
            myLocationEnabled: true,
            onMapCreated: (controller) {
              mapController = controller;
            },
          ),

          // 🔥 TRIP STATUS TEXT
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tripRunning
                    ? Colors.green.withValues(alpha: 0.9)
                    : Colors.red.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 5),
                ],
              ),
              child: Center(
                child: Text(
                  tripStatusText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      // 🔥 BUTTONS
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "start",
            backgroundColor: Colors.green,
            onPressed: startTrip,
            child: const Icon(Icons.play_arrow),
          ),
          const SizedBox(height: 15),

          FloatingActionButton(
            heroTag: "stop",
            backgroundColor: Colors.red,
            onPressed: stopTrip,
            child: const Icon(Icons.stop),
          ),
          const SizedBox(height: 15),

          FloatingActionButton(
            heroTag: "qr",
            backgroundColor: Colors.blue,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DriverQRScreen(tripId: "BUS_TRIP_101"),
                ),
              );
            },
            child: const Icon(Icons.qr_code),
          ),
        ],
      ),
    );
  }
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  final DatabaseReference attendanceRef = FirebaseDatabase.instance.ref(
    "attendance",
  );

  List attendanceList = [];

  @override
  void initState() {
    super.initState();
    loadAttendance();
  }

  void loadAttendance() {
    attendanceRef.onValue.listen((event) {
      if (!event.snapshot.exists) return;

      Map data = Map<String, dynamic>.from(event.snapshot.value as Map);

      List temp = [];
      data.forEach((key, value) {
        temp.add(value);
      });

      setState(() {
        attendanceList = temp;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Panel")),

      body: Column(
        children: [
          // 🔥 CREATE USER BUTTON
          Padding(
            padding: const EdgeInsets.all(10),
            child: ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => CreateUserDialog(),
                );
              },
              child: const Text("➕ Create User"),
            ),
          ),

          // 🔥 ATTENDANCE LIST
          Expanded(
            child: attendanceList.isEmpty
                ? const Center(
                    child: Text(
                      "No Attendance Records Yet",
                      style: TextStyle(fontSize: 18),
                    ),
                  )
                : ListView.builder(
                    itemCount: attendanceList.length,
                    itemBuilder: (context, index) {
                      var record = attendanceList[index];

                      return Card(
                        margin: const EdgeInsets.all(10),
                        child: ListTile(
                          leading: const Icon(Icons.person),
                          title: Text("Student: ${record["studentId"]}"),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Trip: ${record["tripId"]}"),
                              Text("Time: ${record["time"]}"),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class CreateUserDialog extends StatefulWidget {
  const CreateUserDialog({super.key});

  @override
  State<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<CreateUserDialog> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();

  String role = "student";

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Create User"),

      content: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),

            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              initialValue: role,
              items: [
                "student",
                "driver",
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (val) {
                setState(() {
                  role = val!;
                });
              },
              decoration: const InputDecoration(labelText: "Role"),
            ),
          ],
        ),
      ),

      actions: [
        ElevatedButton(
          onPressed: () async {
            final navigator = Navigator.of(context);
            await AuthService().createUserByAdmin(
              emailController.text.trim(),
              passwordController.text.trim(),
              role,
              nameController.text.trim(),
            );
            navigator.pop();
          },
          child: const Text("Create"),
        ),
      ],
    );
  }
}
