// main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'firebase_options.dart'; // FlutterFire CLIで生成されたファイル

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // アプリのルート
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quiz App with ReseMara Prevention',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  // メインページ
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FlutterSecureStorage secureStorage = FlutterSecureStorage();
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final Uuid uuid = Uuid();

  String? deviceId;
  bool isFirstLaunch = false;
  bool isBanned = false;

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    try {
      // 匿名認証でサインイン
      UserCredential userCredential = await auth.signInAnonymously();
      User? user = userCredential.user;
      print('Signed in anonymously as user: ${user?.uid}');

      // KeychainからデバイスIDを読み込む
      String? storedDeviceId = await secureStorage.read(key: 'deviceId');
      print('Stored deviceId: $storedDeviceId');

      if (storedDeviceId == null) {
        // 初回起動の場合、UUIDを生成して保存
        String newDeviceId = uuid.v4();
        await secureStorage.write(key: 'deviceId', value: newDeviceId);
        print('Generated new deviceId: $newDeviceId');

        setState(() {
          deviceId = newDeviceId;
          isFirstLaunch = true;
        });

        // FirestoreにデバイスIDを保存
        await firestore.collection('bannedUsers').doc(newDeviceId).set({
          'banned': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        print('Created Firestore document for deviceId: $newDeviceId');
      } else {
        // 2回目以降の起動
        setState(() {
          deviceId = storedDeviceId;
          isFirstLaunch = false;
        });
        print('Existing deviceId: $storedDeviceId');

        // Firestoreでユーザーがバンされているか確認
        DocumentSnapshot userDoc =
            await firestore.collection('bannedUsers').doc(storedDeviceId).get();
        if (userDoc.exists) {
          bool banned = userDoc.get('banned') ?? false;
          print('DeviceId $storedDeviceId is banned: $banned');
          setState(() {
            isBanned = banned;
          });
        } else {
          // ドキュメントが存在しない場合、新しく作成
          await firestore.collection('bannedUsers').doc(storedDeviceId).set({
            'banned': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
          print('Re-created Firestore document for deviceId: $storedDeviceId');
        }
      }
    } catch (e) {
      print('Error initializing user: $e');
      // エラー時の処理（必要に応じてUIを更新）
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ユーザーの初期化中にエラーが発生しました。')),
      );
    }
  }

  Future<void> _handleQuizResult(bool isCorrect) async {
    if (!isCorrect) {
      if (deviceId != null) {
        try {
          // Firestoreでバンフラグを更新
          await firestore.collection('bannedUsers').doc(deviceId).update({
            'banned': true,
            'bannedAt': FieldValue.serverTimestamp(),
          });
          print(
              'Updated Firestore document for deviceId: $deviceId to banned.');

          setState(() {
            isBanned = true;
          });

          // バンメッセージを表示
          _showBannedDialog();
        } catch (e) {
          print('Error updating Firestore document: $e');
          // エラー時の処理（ユーザーに通知）
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('エラーが発生しました。再試行してください。')),
          );
        }
      } else {
        print('deviceId is null. Cannot update Firestore.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラーが発生しました。再試行してください。')),
        );
      }
    } else {
      // 正解時の処理（必要に応じて実装）
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('正解！おめでとうございます！')),
      );
    }
  }

  void _showBannedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('アクセス制限'),
          content: Text('もう一度間違えています。アプリをプレイできません。'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // アプリを閉じる場合は以下のコメントを外してください
                // import 'dart:io';
                // exit(0);
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _startQuiz() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => QuizPage(onQuizResult: _handleQuizResult)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isBanned) {
      return Scaffold(
        appBar: AppBar(
          title: Text('アクセス制限'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'もう一度間違えています。アプリをプレイできません。',
                style: TextStyle(fontSize: 18, color: Colors.red),
                textAlign: TextAlign.center,
              ),
              ElevatedButton(
                  onPressed: () async {
                    // すべてのキーを削除
                    await secureStorage.deleteAll();
                  },
                  child: Text('データをリセットする'))
            ],
          ),
        ),
      );
    }

    if (deviceId == null) {
      // ユーザー情報の初期化中
      return Scaffold(
        appBar: AppBar(
          title: Text('読み込み中'),
        ),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('クイズアプリ'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: _startQuiz,
          child: Text('クイズを始める'),
        ),
      ),
    );
  }
}

class QuizPage extends StatefulWidget {
  final Function(bool) onQuizResult;

  QuizPage({required this.onQuizResult});

  @override
  _QuizPageState createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  // シンプルなクイズの例
  String question = 'FlutterはGoogleによって開発されましたか？';
  List<String> options = ['はい', 'いいえ'];
  int correctOption = 0;
  int selectedOption = -1;

  void _submitAnswer() {
    if (selectedOption == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('回答を選択してください')),
      );
      return;
    }

    bool isCorrect = selectedOption == correctOption;
    widget.onQuizResult(isCorrect);

    if (isCorrect) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text('クイズ'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                question,
                style: TextStyle(fontSize: 20),
              ),
              SizedBox(height: 20),
              ...List.generate(options.length, (index) {
                return RadioListTile<int>(
                  title: Text(options[index]),
                  value: index,
                  groupValue: selectedOption,
                  onChanged: (int? value) {
                    setState(() {
                      selectedOption = value!;
                    });
                  },
                );
              }),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _submitAnswer,
                child: Text('回答する'),
              ),
            ],
          ),
        ));
  }
}
