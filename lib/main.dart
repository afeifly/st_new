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
      title: 'CSD Utility',
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
  String? _lastDirectory;

  // Add this method to format values based on resolution
  String _formatValue(dynamic value, int resolution) {
    if (value is! num) return value.toString();
    if (resolution <= 0) return value.toInt().toString();
    return value.toStringAsFixed(resolution);
  }

  // Add this helper method to format min-max range
  String _formatMinMaxRange(int channelIndex) {
    final min = _channelMins[channelIndex];
    final max = _channelMaxs[channelIndex];
    final unit = _unitTexts[channelIndex];

    return '(${_formatValue(min, _resolutions[channelIndex])} - ${_formatValue(max, _resolutions[channelIndex])}) $unit';
  }

  Future<void> _openAndReadCsdFile() async {
    setState(() {
      _showChart = false;
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csd'],
        initialDirectory: _lastDirectory,
      );

      if (result == null) {
        setState(() {
          _fileInfo = 'No file selected';
        });
        return;
      }

      String filePath = result.files.single.path!;
      _lastLoadedFilePath = filePath;

      File file = File(filePath);
      if (!await file.exists()) {
        setState(() {
          _fileInfo = 'Error: File does not exist at path: $filePath';
        });
        return;
      }

      try {
        await file.openRead().first;
      } catch (e) {
        setState(() {
          _fileInfo =
              'Error: Cannot read file (permission denied)\nPath: $filePath\nError: $e';
        });
        return;
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

        if (firstTenRecords.isEmpty ||
            firstTenRecords.any((channelData) => channelData.isEmpty)) {
          setState(() {
            _fileInfo = '''
Number of channels: $_numChannels          Sample rate: ${protocolHeader.sampleRate}
Number of records: ${protocolHeader.numOfSamples}
Time period: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(_startTime!)} - ${DateFormat('yyyy-MM-dd HH:mm:ss').format(stopTime)}

Warning: No valid data available in the file.''';
          });
          return;
        }

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
Number of channels: $_numChannels          Sample rate: ${protocolHeader.sampleRate}
Number of records: ${protocolHeader.numOfSamples}
Time period: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(_startTime!)} - ${DateFormat('yyyy-MM-dd HH:mm:ss').format(stopTime)}''';
        });
      } catch (e) {
        print('Error in CsdFileHandler.load(): $e');
        setState(() {
          _fileInfo = '''
Error loading file:
Path: $filePath
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

      if (chartRecords.isEmpty || chartRecords[channelIndex].isEmpty) {
        throw Exception('No valid chart data available.');
      }

      setState(() {
        _chartData = List.generate(100, (index) {
          double timeInSeconds = index.toDouble();
          double value = chartRecords[channelIndex][index];
          return FlSpot(timeInSeconds, value);
        });
      });

      await csdFile.close();
    } catch (e, stackTrace) {
      print('Error preparing chart data: $e');
      print('Stack trace: $stackTrace');
    }
  }

  // Add this method to fix the file
  Future<void> _fixFileData() async {
    if (_lastLoadedFilePath == null) return;

    try {
      var file = File(_lastLoadedFilePath!);
      var fileSize = await file.length();

      // Calculate the actual number of samples based on file size and channel count
      final headerSize = CsdConstants.CHANNEL_HEADERS_START +
          (CsdConstants.CHANNEL_HEADER_LENGTH * _numChannels);
      final recordLength = CsdConstants.RECORD_ID_LENGTH +
          (CsdConstants.CHANNEL_VALUE_LENGTH * _numChannels);
      final dataSize = fileSize - headerSize;
      final actualSamples = (dataSize / recordLength).floor();

      var csdFile = CsdFileHandler();
      await csdFile.load(_lastLoadedFilePath!);

      await csdFile.fixSampleCount(_lastLoadedFilePath!, actualSamples);
      // Calculate actual min/max values for each channel
      final channelRanges = await csdFile.calculateChannelRanges();

      // Update each channel's min/max values in the file
      for (int i = 0; i < _numChannels; i++) {
        final (min, max) = channelRanges[i];
        await csdFile.updateChannelRange(i, min, max);
      }

      // Format and display the ranges
      String rangeInfo = '\n\nChannel value ranges:';
      for (int i = 0; i < _numChannels; i++) {
        final (min, max) = channelRanges[i];
        final resolution = _resolutions[i];
        final formattedMin = _formatValue(min, resolution);
        final formattedMax = _formatValue(max, resolution);
        rangeInfo +=
            '\n${_channelDescriptions[i]}: $formattedMin to $formattedMax ${_unitTexts[i]}';
      }

      await csdFile.close();

      setState(() {
        _fileInfo += rangeInfo;
      });

      await _reloadCurrentFile();
    } catch (e) {
      setState(() {
        _fileInfo += '\n\nError trying to fix file: $e';
      });
    }
  }

  // Add this new method to reload the current file without file picker
  Future<void> _reloadCurrentFile() async {
    if (_lastLoadedFilePath == null) return;

    try {
      var csdFile = CsdFileHandler();
      await csdFile.load(_lastLoadedFilePath!);
      final protocolHeader = csdFile.getProtocolHeader();

      // Store values before setState
      final newStartTime = csdFile.getStartTime();
      final newNumChannels = csdFile.getNumOfChannels();
      final newStopTime = csdFile.getStopTime();
      final newResolutions = csdFile.getResolutions();
      final newChannelDescriptions = csdFile.getChannelDescriptions();
      final newUnitTexts = csdFile.getUnitTexts();
      final newSampleRate = protocolHeader.sampleRate;
      final newChannelMins = csdFile.getChannelMins();
      final newChannelMaxs = csdFile.getChannelMaxs();

      // Get first ten records safely
      List<List<double>> firstTenRecords = [];
      try {
        firstTenRecords = await csdFile.getDataWithSampling(0, 9);
      } catch (e) {
        print('Warning: Could not read first ten records: $e');
      }

      // Close the file before setState
      await csdFile.close();

      // Update state only once with all new values
      setState(() {
        _startTime = newStartTime;
        _numChannels = newNumChannels;
        _resolutions = newResolutions;
        _channelDescriptions = newChannelDescriptions;
        _unitTexts = newUnitTexts;
        _sampleRate = newSampleRate;
        _channelMins = newChannelMins;
        _channelMaxs = newChannelMaxs;

        _fileInfo = '''
Number of channels: $_numChannels          Sample rate: ${protocolHeader.sampleRate}
Number of records: ${protocolHeader.numOfSamples}
Time period: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(newStartTime)} - ${DateFormat('yyyy-MM-dd HH:mm:ss').format(newStopTime)}''';

        if (firstTenRecords.isNotEmpty) {
          _recordData = List.generate(10, (recordIndex) {
            final timestamp =
                newStartTime.add(Duration(seconds: recordIndex * _sampleRate));
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
        }
      });
    } catch (e) {
      print('Error reloading file: $e');
      setState(() {
        _fileInfo += '\n\nError reloading file: $e';
      });
    }
  }

  // Add method to load last directory on init
  @override
  void initState() {
    super.initState();
    _loadLastDirectory();
  }

  Future<void> _loadLastDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastDirectory = prefs.getString('lastDirectory');
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool hasError = _fileInfo.contains('Error') ||
        _fileInfo.contains('Warning: No valid data');

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _lastLoadedFilePath == null
                      ? _openAndReadCsdFile
                      : _closeFile,
                  icon: Icon(_lastLoadedFilePath == null
                      ? Icons.folder_open
                      : Icons.close),
                  label: Text(
                      _lastLoadedFilePath == null ? 'Open File' : 'Close File'),
                ),
                if (_lastLoadedFilePath != null && !hasError) ...[
                  const SizedBox(width: 16),
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
                  if (_showChart) ...[
                    const SizedBox(width: 16),
                    SizedBox(
                      height: 36, // Match other button heights
                      child: ElevatedButton(
                        onPressed: null,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          backgroundColor: Colors.transparent,
                          elevation: 0, // Remove button shadow
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _selectedChannel,
                            isDense: true,
                            items: List.generate(
                              _numChannels,
                              (index) => DropdownMenuItem(
                                value: index,
                                child: Text(
                                  _channelDescriptions[index],
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedChannel = value;
                                });
                                if (_showChart) {
                                  setState(() {});
                                }
                              }
                            },
                            icon: const Icon(Icons.arrow_drop_down, size: 20),
                            elevation: 3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _showChart && _lastLoadedFilePath != null && !hasError
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
                      selectedChannel: _selectedChannel,
                      onChannelChanged: (value) {
                        setState(() {
                          _selectedChannel = value;
                        });
                      },
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
                        _buildFileInfo(),
                        if (_recordData.isNotEmpty && !hasError) ...[
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
                                        label: Tooltip(
                                          message: _formatMinMaxRange(index),
                                          child: Text(
                                            '${_channelDescriptions[index]}\n(${_unitTexts[index]})',
                                            textAlign: TextAlign.center,
                                          ),
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

  // Modify the file info section in the build method
  Widget _buildFileInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(_fileInfo),
        ),
        if (_fileInfo.contains('Warning: No valid data')) ...[
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _fixFileData,
            icon: const Icon(Icons.build),
            label: const Text('Fix File'),
          ),
        ],
      ],
    );
  }
}
