import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'csd_file_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CSD File Reader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _fileInfo = 'No file loaded';
  List<Map<String, dynamic>> _recordData = [];

  Future<void> _openAndReadCsdFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csd'],
      );

      if (result == null) {
        print('No file selected');
        setState(() {
          _fileInfo = 'No file selected';
        });
        return;
      }

      String filePath = result.files.single.path!;
      print('Selected file path: $filePath');

      File file = File(filePath);
      if (!await file.exists()) {
        setState(() {
          _fileInfo = 'Error: File does not exist at path: $filePath';
        });
        return;
      }

      int fileSize = await file.length();
      print('File size: ${fileSize} bytes');

      try {
        await file.openRead().first;
        print('File is readable');
      } catch (e) {
        print('File permission error: $e');
        setState(() {
          _fileInfo =
              'Error: Cannot read file (permission denied)\nPath: $filePath\nError: $e';
        });
        return;
      }

      try {
        var bytes = await file.openRead().take(10).toList();
        print('First few bytes: $bytes');
      } catch (e) {
        print('Error reading file content: $e');
      }

      var csdFile = CsdFileHandler();
      try {
        await csdFile.load(filePath);
        print('File loaded successfully');

        var channels = csdFile.getNumOfChannels();
        var startTime = csdFile.getStartTime();
        var stopTime = csdFile.getStopTime();
        var firstTenRecords = await csdFile.getData(0, 9);

        _recordData = List.generate(10, (recordIndex) {
          final timestamp = startTime.add(Duration(seconds: recordIndex));
          return {
            'Record': timestamp.toString(),
            ...Map.fromEntries(
              List.generate(
                channels,
                (channelIndex) => MapEntry(
                  'Channel ${channelIndex}',
                  firstTenRecords[channelIndex][recordIndex],
                ),
              ),
            ),
          };
        });

        setState(() {
          _fileInfo = '''
File Information:
Number of channels: $channels
Start time: $startTime
Stop time: $stopTime''';
        });
      } catch (e) {
        print('Error in CsdFileHandler.load(): $e');
        setState(() {
          _fileInfo = '''
Error loading file:
Path: $filePath
File size: $fileSize bytes
Error: $e
Stack trace: ${StackTrace.current}''';
        });
        return;
      }

      await csdFile.close();
    } catch (e, stackTrace) {
      print('Error: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _fileInfo = '''
Error occurred:
$e

Stack trace:
$stackTrace''';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('CSD File Reader'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              onPressed: _openAndReadCsdFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open CSD File'),
            ),
            const SizedBox(height: 20),
            const Text(
              'File Information:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_fileInfo),
            ),
            if (_recordData.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'First 10 Records:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columns: [
                        const DataColumn(label: Text('Timestamp')),
                        ...List.generate(
                          _recordData.first.length - 1,
                          (index) => DataColumn(
                            label: Text('Channel $index'),
                          ),
                        ),
                      ],
                      rows: _recordData.map((record) {
                        return DataRow(
                          cells: record.entries.map((entry) {
                            return DataCell(
                              Text(
                                entry.key == 'Record'
                                    ? entry.value
                                    : (entry.value is double
                                        ? entry.value.toStringAsFixed(6)
                                        : entry.value.toString()),
                              ),
                            );
                          }).toList(),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
