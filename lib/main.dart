import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'csd_file_handler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'graphic_view.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CSD Handler',
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
  bool _showChart = false;
  int _selectedChannel = 0;
  int _numChannels = 0;
  List<FlSpot> _chartData = [];
  DateTime? _startTime;
  String? _lastLoadedFilePath;
  List<int> _resolutions = [];
  List<String> _channelDescriptions = [];
  List<String> _unitTexts = [];
  int _sampleRate = 1;
  List<double> _channelMins = [];
  List<double> _channelMaxs = [];

  // Add this method to format values based on resolution
  String _formatValue(dynamic value, int resolution) {
    if (value is! num) return value.toString();
    if (resolution <= 0) return value.toInt().toString();
    return value.toStringAsFixed(resolution);
  }

  Future<void> _openAndReadCsdFile() async {
    setState(() {
      _showChart = false;
    });

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
      _lastLoadedFilePath = filePath;
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
        final protocolHeader = csdFile.getProtocolHeader();
        _lastLoadedFilePath = filePath;
        _startTime = csdFile.getStartTime();
        _numChannels = csdFile.getNumOfChannels();
        var stopTime = csdFile.getStopTime();
        var firstTenRecords = await csdFile.getDataWithSampling(0, 9);
        _resolutions = csdFile.getResolutions();
        _channelDescriptions = csdFile.getChannelDescriptions();
        _unitTexts = csdFile.getUnitTexts();
        _sampleRate = protocolHeader.sampleRate;

        // Get min/max values for each channel
        _channelMins = csdFile.getChannelMins();
        _channelMaxs = csdFile.getChannelMaxs();

        _recordData = List.generate(10, (recordIndex) {
          // Calculate timestamp using sampleRate
          final timestamp =
              _startTime!.add(Duration(seconds: recordIndex * _sampleRate));
          return {
            'Record': DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp),
            ...Map.fromEntries(
              List.generate(
                _numChannels,
                (channelIndex) => MapEntry(
                  'Channel ${channelIndex}',
                  _formatValue(
                    firstTenRecords[channelIndex][recordIndex],
                    _resolutions[channelIndex],
                  ),
                ),
              ),
            ),
          };
        });

        setState(() {
          _fileInfo = '''
File Information:
Number of channels: $_numChannels
Number of records: ${protocolHeader.numOfSamples}
Sample rate: ${protocolHeader.sampleRate} 
Start time: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(_startTime!)}
Stop time: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(stopTime)}''';
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

  Future<void> _closeFile() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('filePath');
    setState(() {
      _fileInfo = 'No file loaded';
      _recordData.clear();
      _showChart = false;
      _lastLoadedFilePath = null;
      _chartData.clear();
      _startTime = null;
      _numChannels = 0;
      _resolutions.clear();
      _channelDescriptions.clear();
      _unitTexts.clear();
      _sampleRate = 1;
      _channelMins.clear();
      _channelMaxs.clear();
    });
  }

  void _prepareChartData(int channelIndex) async {
    if (_startTime == null) return;

    var csdFile = CsdFileHandler();
    try {
      await csdFile.load(_lastLoadedFilePath!);
      var chartRecords = await csdFile.getDataWithSampling(0, 99);

      // Add debug prints
      print('Preparing chart data for channel: $channelIndex');
      print('Chart records length: ${chartRecords.length}');
      print('First few values: ${chartRecords[channelIndex].take(5)}');

      setState(() {
        _chartData = List.generate(100, (index) {
          double timeInSeconds = index.toDouble();
          double value = chartRecords[channelIndex][index];
          return FlSpot(timeInSeconds, value);
        });
      });

      // Add debug print
      print('Chart data points: ${_chartData.take(5)}');

      await csdFile.close();
    } catch (e, stackTrace) {
      print('Error preparing chart data: $e');
      print('Stack trace: $stackTrace');
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
            Row(
              children: [
                PopupMenuButton<String>(
                  onSelected: (String value) {
                    if (value == 'open') {
                      _openAndReadCsdFile();
                    } else if (value == 'close') {
                      _closeFile();
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'open',
                      child: ListTile(
                        leading: Icon(Icons.folder_open),
                        title: Text('Open CSD File'),
                      ),
                    ),
                    if (_lastLoadedFilePath != null)
                      const PopupMenuItem<String>(
                        value: 'close',
                        child: ListTile(
                          leading: Icon(Icons.close),
                          title: Text('Close File'),
                        ),
                      ),
                  ],
                  child: ElevatedButton.icon(
                    onPressed: null, // Disable direct button action
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open File'),
                  ),
                ),
                const SizedBox(width: 16),
                if (_lastLoadedFilePath != null) ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showChart = !_showChart;
                      });
                    },
                    icon:
                        Icon(_showChart ? Icons.arrow_back : Icons.show_chart),
                    label: Text(_showChart ? 'Back to Info' : 'Show Chart'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _showChart && _lastLoadedFilePath != null
                  ? GraphicView(
                      filePath: _lastLoadedFilePath!,
                      startTime: _startTime!,
                      numChannels: _numChannels,
                      resolutions: _resolutions,
                      channelDescriptions: _channelDescriptions,
                      unitTexts: _unitTexts,
                      sampleRate: _sampleRate,
                      channelMins: _channelMins,
                      channelMaxs: _channelMaxs,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'File Information:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
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
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
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
                                        label: Text(
                                          '${_channelDescriptions[index]}\n(${_unitTexts[index]})',
                                          textAlign: TextAlign.center,
                                        ),
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
                                                    ? entry.value
                                                        .toStringAsFixed(6)
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
          ],
        ),
      ),
    );
  }
}
