
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:another_telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_amqp/dart_amqp.dart'; // Changed from amqp_client
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p; // Alias the path package
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'dart:typed_data';
import 'dart:async' show runZonedGuarded;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[900],
        appBarTheme: const AppBarTheme(backgroundColor: Colors.grey),
      ),
      home: const SplashScreen(),
    );
  }
}

// Database Helper Class
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path =
    p.join(await getDatabasesPath(), 'vigil_eye.db'); // Use p.join
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE employees(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        image_path TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertEmployee(Map<String, dynamic> employee) async {
    final db = await database;
    return await db.insert('employees', employee);
  }

  Future<List<Map<String, dynamic>>> getAllEmployees() async {
    final db = await database;
    return await db.query('employees');
  }

  Future<int> deleteEmployee(int id) async {
    final db = await database;
    return await db.delete('employees', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getEmployee(
      String username, String password) async {
    final db = await database;
    final result = await db.query(
      'employees',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
    );
    return result.isNotEmpty ? result.first : null;
  }
}

// Manager RabbitMQ Service
class ManagerRabbitMQService {
  late Client _client;
  late Channel _channel;
  final String textQueueName = 'manager text';
  final String imageQueueName = 'manager image';

  bool _isConnected = false;

  // Default local connection settings
  final String _host = 'localhost';
  final int _port = 15672; // 5671 if using TLS
  final String _username = 'guest';
  final String _password = 'guest';
  final String _vhost = '/'; // Default vhost

  Future<void> connect() async {
    try {
      // First verify RabbitMQ is running locally
      //await _verifyLocalServer();

      _client = Client(
          settings: ConnectionSettings(
            host: _host,
            port: _port,
            authProvider: PlainAuthenticator(_username, _password),
            virtualHost: _vhost,
            // For TLS:
            // tlsContext: SecurityContext.defaultContext,
          )
      );

      _channel = await _client!.channel();
      _isConnected = true;
      print('✅ Connected to local RabbitMQ');
    } catch (e) {
      throw Exception('Failed to connect to RabbitMQ: $e');
    }
  }

  Future<void> sendTextMessage(String message) async {
    try {
      final queue = await _channel.queue(textQueueName, durable: false);
      queue.publish(message);
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  Stream<String> receiveTextMessages() {
    final controller = StreamController<String>();

    _channel.queue(textQueueName, durable: false).then((queue) {
      queue.consume().then((consumer) {
        consumer.listen((message) {
          controller.add(message.payloadAsString);
          message.ack();
        });
      });
    }).catchError((error) {
      controller.addError(error);
    });

    return controller.stream;
  }

  Stream<String> receiveImageMessages() {
    final controller = StreamController<String>();

    _channel.queue(imageQueueName, durable: false).then((queue) {
      queue.consume().then((consumer) {
        consumer.listen((message) {
          controller.add(message.payloadAsString);
          message.ack();
        });
      });
    }).catchError((error) {
      controller.addError(error);
    });

    return controller.stream;
  }

  Future<void> disconnect() async {
    try {
      await _client.close();
    } catch (e) {
      throw Exception('Failed to disconnect: $e');
    }
  }
}

// Worker RabbitMQ Service
class WorkerRabbitMQService {
  late Client _client;
  late Channel _channel;

  final String textQueueName = 'worker1 text';
  final String imageQueueName = 'worker1 image';

  Future<void> connect() async {
    try {
      _client = Client(
        settings: ConnectionSettings(
          host: 'lionfish.rmq.cloudamqp.com',
          authProvider: PlainAuthenticator(
              'mwzrfgys', '1UksEm_rmQkrDkNi-SpNnYSpJluIlBW8'),
          virtualHost: 'mwzrfgys',
        ),
      );

      _channel = await _client.channel();
    } catch (e) {
      throw Exception('Failed to connect to RabbitMQ: $e');
    }
  }

  Stream<String> receiveTextMessages() {
    final controller = StreamController<String>();

    _channel.queue(textQueueName, durable: false).then((queue) {
      queue.consume().then((consumer) {
        consumer.listen((message) {
          controller.add(message.payloadAsString);
          message.ack();
        });
      });
    }).catchError((error) {
      controller.addError(error);
    });

    return controller.stream;
  }

  Stream<String> receiveImageMessages() {
    final controller = StreamController<String>();

    _channel.queue(imageQueueName, durable: false).then((queue) {
      queue.consume().then((consumer) {
        consumer.listen((message) {
          controller.add(message.payloadAsString);
          message.ack();
        });
      });
    }).catchError((error) {
      controller.addError(error);
    });

    return controller.stream;
  }

  Future<void> disconnect() async {
    try {
      await _client.close();
    } catch (e) {
      throw Exception('Failed to disconnect: $e');
    }
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _navigateToLogin();
  }

  void _navigateToLogin() async {
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Icon(
                Icons.security,
                size: 100,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Vigil Eye',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginPage extends StatelessWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(75),
              ),
              child: const Icon(
                Icons.login,
                size: 75,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ManagerLogin()),
                );
              },
              child: const Text('Login as Manager'),
              style: ElevatedButton.styleFrom(
                padding:
                const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                minimumSize: const Size(200, 50),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const EmployeeLogin()),
                );
              },
              child: const Text('Login as Employee'),
              style: ElevatedButton.styleFrom(
                padding:
                const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                minimumSize: const Size(200, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ManagerLogin extends StatefulWidget {
  const ManagerLogin({Key? key}) : super(key: key);

  @override
  State<ManagerLogin> createState() => _ManagerLoginState();
}

class _ManagerLoginState extends State<ManagerLogin> {
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login(BuildContext context) {
    if (_usernameController.text == 'admin' &&
        _passwordController.text == '1234') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ManagerDashboard()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect username or password')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manager Login')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Icon(
                Icons.admin_panel_settings,
                size: 50,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => _login(context),
              child: const Text('Login'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmployeeLogin extends StatefulWidget {
  const EmployeeLogin({Key? key}) : super(key: key);

  @override
  State<EmployeeLogin> createState() => _EmployeeLoginState();
}

class _EmployeeLoginState extends State<EmployeeLogin> {
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login(BuildContext context) async {
    final employee = await DatabaseHelper().getEmployee(
      _usernameController.text,
      _passwordController.text,
    );

    if (employee != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const EmployeeDashboard()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect username or password')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Employee Login')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Icon(
                Icons.person,
                size: 50,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => _login(context),
              child: const Text('Login'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ManagerDashboard extends StatelessWidget {
  const ManagerDashboard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manager Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginPage()),
                    (route) => false,
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(60),
              ),
              child: const Icon(
                Icons.dashboard,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            _buildDashboardButton(
              context,
              'Alarms',
              Icons.alarm,
              Colors.red,
                  () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ChatWindow(isManager: true),
                ),
              ),
            ),
            const SizedBox(height: 15),
            _buildDashboardButton(
              context,
              'Add Employee',
              Icons.person_add,
              Colors.green,
                  () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const AddEmployeePage()),
              ),
            ),
            const SizedBox(height: 15),
            _buildDashboardButton(
              context,
              'Remove Employee',
              Icons.person_remove,
              Colors.orange,
                  () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const RemoveEmployeePage()),
              ),
            ),
            const SizedBox(height: 15),
            _buildDashboardButton(
              context,
              'Manager Settings',
              Icons.settings,
              Colors.purple,
                  () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const ManagerSettingsPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardButton(
      BuildContext context,
      String title,
      IconData icon,
      Color color,
      VoidCallback onPressed,
      ) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmployeeDashboard extends StatelessWidget {
  const EmployeeDashboard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginPage()),
                    (route) => false,
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(60),
              ),
              child: const Icon(
                Icons.work,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: 200,
              height: 60,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChatWindow(isManager: false),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.alarm, color: Colors.white),
                    SizedBox(width: 10),
                    Text(
                      'Alarms',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
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

class ChatWindow extends StatefulWidget {
  final bool isManager;
  const ChatWindow({Key? key, required this.isManager}) : super(key: key);

  @override
  State<ChatWindow> createState() => _ChatWindowState();
}

class _ChatWindowState extends State<ChatWindow> {
  final List<Map<String, dynamic>> _messages = [];
  late ManagerRabbitMQService _managerService;
  late WorkerRabbitMQService _workerService;
  String? _managerPhoneNumber;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingAlarm = false;

  @override
  void initState() {
    super.initState();
    _loadManagerNumber();
  }

  Future<void> _loadManagerNumber() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _managerPhoneNumber = prefs.getString('manager_phone');
    });
  }

  Future<void> _initRabbitMQ() async {
    try {
      if (widget.isManager) {
        _managerService = ManagerRabbitMQService();
        await _managerService.connect();

        _managerService.receiveTextMessages().listen(
              (message) {
            if (mounted) {
              _handleNewMessage({
                'type': 'text',
                'content': message,
                'timestamp': DateTime.now(),
              });
            }
          },
          onError: (error) {
            debugPrint('Error receiving text messages: $error');
          },
        );

        _managerService.receiveImageMessages().listen(
              (image) {
            if (mounted) {
              _handleNewMessage({
                'type': 'image',
                'content': image,
                'timestamp': DateTime.now(),
              });
            }
          },
          onError: (error) {
            debugPrint('Error receiving image messages: $error');
          },
        );
      } else {
        _workerService = WorkerRabbitMQService();
        await _workerService.connect();

        _workerService.receiveTextMessages().listen(
              (message) {
            if (mounted) {
              _handleNewMessage({
                'type': 'text',
                'content': message,
                'timestamp': DateTime.now(),
              });
            }
          },
          onError: (error) {
            debugPrint('Error receiving text messages: $error');
          },
        );

        _workerService.receiveImageMessages().listen(
              (image) {
            if (mounted) {
              _handleNewMessage({
                'type': 'image',
                'content': image,
                'timestamp': DateTime.now(),
              });
            }
          },
          onError: (error) {
            debugPrint('Error receiving image messages: $error');
          },
        );
      }
    } catch (e) {
      debugPrint('Failed to initialize RabbitMQ: $e');
      // Don't show SnackBar here as it might cause issues
    }
  }

  Future<void> _handleNewMessage(Map<String, dynamic> message) async {
    await _playAlarmSound();
    await _triggerVibration();

    setState(() {
      _messages.add(message);
    });
  }

  Future<void> _playAlarmSound() async {
    if (_isPlayingAlarm) return;

    _isPlayingAlarm = true;
    try {
      // Use a system sound instead of asset
      await _audioPlayer.play(
          DeviceFileSource('/system/media/audio/notifications/Default.ogg'));
      await Future.delayed(const Duration(seconds: 2));
      await _audioPlayer.stop();
    } catch (e) {
      print('Error playing sound: $e');
      // Fallback - just vibrate if sound fails
    } finally {
      _isPlayingAlarm = false;
    }
  }

  Future<void> _triggerVibration() async {
    try {
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator ?? false) {
        await Vibration.vibrate(
          pattern: [500, 1000, 500, 1000],
          intensities: [128, 255, 128, 255],
        );
      }
    } catch (e) {
      debugPrint('Error with vibration: $e');
    }
  }

  Future<void> _callEmergency() async {
    const number = '123';
    final url = 'tel:$number';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch the dialer')),
      );
    }
  }

  Future<void> _callManager() async {
    if (_managerPhoneNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manager phone number not set')),
      );
      return;
    }
    final url = 'tel:$_managerPhoneNumber';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch the dialer')),
      );
    }
  }

  Future<void> _sendToManager(String message) async {
    if (_managerPhoneNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manager phone number not set')),
      );
      return;
    }
    try {
      final Telephony telephony = Telephony.instance;
      await telephony.sendSms(
        to: _managerPhoneNumber!,
        message: message,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SMS sent to manager successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send SMS: $e')),
      );
    }
  }

  void _showResponseOptions(
      BuildContext context, Map<String, dynamic> message) {
    // Added BuildContext
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Response Options',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.emergency, color: Colors.red),
              title: const Text('Call Emergency (123)'),
              onTap: () {
                Navigator.pop(context);
                _callEmergency();
              },
            ),
            ListTile(
              leading: const Icon(Icons.phone, color: Colors.blue),
              title: const Text('Call Manager'),
              onTap: () {
                Navigator.pop(context);
                _callManager();
              },
            ),
            ListTile(
              leading: const Icon(Icons.message, color: Colors.green),
              title: const Text('Send to Manager via SMS'),
              onTap: () {
                Navigator.pop(context);
                _sendToManager(message['content']);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    // Only disconnect if services were initialized
    try {
      if (widget.isManager) {
        _managerService.disconnect();
      } else {
        _workerService.disconnect();
      }
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isManager ? 'Manager Alarms' : 'Employee Alarms'),
        backgroundColor: widget.isManager ? Colors.blue : Colors.green,
      ),
      body: Column(
        children: [
          // Add connection status and button
          Container(
            padding: const EdgeInsets.all(10),
            color: Colors.grey[800],
            child: Row(
              children: [
                Icon(
                  Icons.cloud_off,
                  color: Colors.orange,
                ),
                const SizedBox(width: 10),
                const Text('Not connected to messaging service'),
                const Spacer(),
                ElevatedButton(
                  onPressed: _initRabbitMQ,
                  child: const Text('Connect'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 20),
                  Text(
                    'No alerts received yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.device_hub,
                              color: Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Raspberry Pi',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${message['timestamp'].hour}:${message['timestamp'].minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (message['type'] == 'text')
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.grey[800],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              message['content'],
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        if (message['type'] == 'image')
                          Container(
                            width: double.infinity,
                            height: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                base64.decode(message['content']),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        if (widget.isManager) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () =>
                                  _showResponseOptions(context, message),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                              ),
                              child: const Text(
                                'Respond',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ],
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

class AddEmployeePage extends StatefulWidget {
  const AddEmployeePage({Key? key}) : super(key: key);

  @override
  State<AddEmployeePage> createState() => _AddEmployeePageState();
}

class _AddEmployeePageState extends State<AddEmployeePage> {
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  File? _image;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final pickedFile =
    await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    }
  }

  Future<void> _addEmployee() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    try {
      final employee = {
        'username': _usernameController.text,
        'password': _passwordController.text,
        'image_path': _image?.path,
        'created_at': DateTime.now().toIso8601String(),
      };

      await DatabaseHelper().insertEmployee(employee);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Employee added successfully')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding employee: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Employee'),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(60),
                  border: Border.all(color: Colors.grey),
                ),
                child: _image != null
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(60),
                  child: Image.file(
                    _image!,
                    fit: BoxFit.cover,
                  ),
                )
                    : const Icon(
                  Icons.add_a_photo,
                  size: 50,
                  color: Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _addEmployee,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                child: const Text(
                  'Add Employee',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RemoveEmployeePage extends StatefulWidget {
  const RemoveEmployeePage({Key? key}) : super(key: key);

  @override
  State<RemoveEmployeePage> createState() => _RemoveEmployeePageState();
}

class _RemoveEmployeePageState extends State<RemoveEmployeePage> {
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    try {
      final employees = await DatabaseHelper().getAllEmployees();
      setState(() {
        _employees = employees;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading employees: $e')),
      );
    }
  }

  Future<void> _removeEmployee(int id, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Removal'),
        content: Text('Are you sure you want to remove employee "$username"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DatabaseHelper().deleteEmployee(id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee removed successfully')),
        );
        _loadEmployees(); // Reload the list
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing employee: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remove Employee'),
        backgroundColor: Colors.orange,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _employees.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: Colors.grey,
            ),
            SizedBox(height: 20),
            Text(
              'No employees found',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: _employees.length,
        itemBuilder: (context, index) {
          final employee = _employees[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue,
                backgroundImage: employee['image_path'] != null
                    ? FileImage(File(employee['image_path']))
                    : null,
                child: employee['image_path'] == null
                    ? const Icon(Icons.person, color: Colors.white)
                    : null,
              ),
              title: Text(
                employee['username'],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Created: ${DateTime.parse(employee['created_at']).toLocal().toString().split(' ')[0]}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _removeEmployee(
                  employee['id'],
                  employee['username'],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ManagerSettingsPage extends StatefulWidget {
  const ManagerSettingsPage({Key? key}) : super(key: key);

  @override
  State<ManagerSettingsPage> createState() => _ManagerSettingsPageState();
}

class _ManagerSettingsPageState extends State<ManagerSettingsPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _loadManagerDetails();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadManagerDetails() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('manager_name') ?? '';
      _phoneController.text = prefs.getString('manager_phone') ?? '';
    });
  }

  Future<void> _saveManagerDetails() async {
    if (_nameController.text.isEmpty || _phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter both name and phone number')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('manager_name', _nameController.text);
    await prefs.setString('manager_phone', _phoneController.text);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Manager details saved successfully')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manager Settings'),
        backgroundColor: Colors.purple,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.purple,
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Icon(
                Icons.settings,
                size: 50,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Manager Name',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Manager Phone Number',
                hintText: 'Enter with country code',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saveManagerDetails,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                ),
                child: const Text(
                  'Save Details',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}