import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'csd_file_handler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'graphic_view.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as Math;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

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
  CsdProtocolHeader? protocolHeader;
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
  int _currentPage = 0;
  static const int _recordsPerPage = 10;
  bool _isLoadingRecords = false;
  int _totalPages = 0;
  double _sliderPosition = 0.0;
  int _actualSamples = 0;
  bool _isExporting = false;
  double _exportProgress = 0.0;
  List<int> _selectedChannels = [];

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
      _sliderPosition = 0.0;
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
        protocolHeader = csdFile.getProtocolHeader();
        _lastLoadedFilePath = filePath;
        _startTime = csdFile.getStartTime();
        _numChannels = csdFile.getNumOfChannels();
        var stopTime = csdFile.getStopTime();
        _resolutions = csdFile.getResolutions();
        _channelDescriptions = csdFile.getChannelDescriptions();
        _unitTexts = csdFile.getUnitTexts();
        _sampleRate = protocolHeader!.sampleRate;
        _channelMins = csdFile.getChannelMins();
        _channelMaxs = csdFile.getChannelMaxs();

        // Calculate total pages
        _totalPages = (protocolHeader!.numOfSamples + _recordsPerPage - 1) ~/
            _recordsPerPage;

        // Calculate actual samples once when opening file
        final fileSize = await file.length();
        final headerSize = CsdConstants.CHANNEL_HEADERS_START +
            (CsdConstants.CHANNEL_HEADER_LENGTH * _numChannels);
        final recordLength = CsdConstants.RECORD_ID_LENGTH +
            (CsdConstants.CHANNEL_VALUE_LENGTH * _numChannels);
        final dataSize = fileSize - headerSize;
        _actualSamples = (dataSize / recordLength).floor();

        setState(() {
          _fileInfo = '''
Number of channels: $_numChannels          Sample rate: ${protocolHeader!.sampleRate}
Number of records: ${protocolHeader!.numOfSamples}
Time period: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(_startTime!)} - ${DateFormat('yyyy-MM-dd HH:mm:ss').format(stopTime)}''';
          _currentPage = 0;
          _recordData.clear();
        });

        // Load first page of records
        await _loadRecordPage(0);
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
      _sliderPosition = 0.0;
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

      // Update protocol header with new sample count
      protocolHeader = await csdFile.getProtocolHeader();
      _totalPages = (actualSamples + _recordsPerPage - 1) ~/ _recordsPerPage;
      _actualSamples = actualSamples;

      setState(() {
        _fileInfo += rangeInfo;
        // Update the file info to reflect the fix
        _fileInfo = _fileInfo.replaceFirst(
            'Number of records: ', 'Number of records (fixed): ');
      });

      // Reload the file to update all the data
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

  Future<void> _loadRecordPage(int page) async {
    if (_isLoadingRecords || _lastLoadedFilePath == null) return;

    setState(() {
      _isLoadingRecords = true;
      _sliderPosition = _totalPages > 1 ? page / (_totalPages - 1) : 0.0;
    });

    try {
      var csdFile = CsdFileHandler();
      await csdFile.load(_lastLoadedFilePath!);

      final totalRecords = csdFile.getProtocolHeader().numOfSamples;
      final startIndex = page * _recordsPerPage;
      final endIndex =
          Math.min(startIndex + _recordsPerPage - 1, totalRecords - 1);

      // Check if we have valid indices
      if (startIndex > endIndex || startIndex >= totalRecords) {
        throw Exception('Invalid page range');
      }

      var pageRecords = await csdFile.getDataWithSampling(startIndex, endIndex);

      if (pageRecords.isNotEmpty) {
        // Calculate actual number of records for this page
        final recordCount = endIndex - startIndex + 1;

        setState(() {
          _recordData = List.generate(recordCount, (recordIndex) {
            final timestamp = _startTime!.add(
              Duration(seconds: (startIndex + recordIndex) * _sampleRate),
            );
            return {
              'Record': DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp),
              ...Map.fromEntries(
                List.generate(
                  _numChannels,
                  (channelIndex) => MapEntry(
                    'Channel ${channelIndex}',
                    _formatValue(
                      pageRecords[channelIndex][recordIndex],
                      _resolutions[channelIndex],
                    ),
                  ),
                ),
              ),
            };
          });
          _currentPage = page;
        });
      }

      await csdFile.close();
    } catch (e) {
      print('Error loading records: $e');
    } finally {
      setState(() {
        _isLoadingRecords = false;
      });
    }
  }

  void _handleSliderChange(double value) {
    setState(() {
      _sliderPosition = value;
    });
    // Calculate page from slider position
    final targetPage = (value * (_totalPages - 1)).round();
    if (targetPage != _currentPage) {
      _loadRecordPage(targetPage);
    }
  }

  // Add this method to check if record count is valid
  bool _hasRecordCountMismatch() {
    if (_lastLoadedFilePath == null) return false;

    final fileSize = File(_lastLoadedFilePath!).lengthSync();
    final headerSize = CsdConstants.CHANNEL_HEADERS_START +
        (CsdConstants.CHANNEL_HEADER_LENGTH * _numChannels);
    final recordLength = CsdConstants.RECORD_ID_LENGTH +
        (CsdConstants.CHANNEL_VALUE_LENGTH * _numChannels);
    final dataSize = fileSize - headerSize;
    final actualSamples = (dataSize / recordLength).floor();

    return actualSamples != _totalPages * _recordsPerPage;
  }

  // Add method to export data to CSV
  Future<void> _exportToCSV() async {
    if (_lastLoadedFilePath == null) return;

    try {
      // Ask user for save location
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save CSV File',
        fileName: '${path.basenameWithoutExtension(_lastLoadedFilePath!)}.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (outputPath == null) return; // User cancelled

      // Add .csv extension if not present
      if (!outputPath.toLowerCase().endsWith('.csv')) {
        outputPath += '.csv';
      }

      setState(() {
        _isExporting = true;
        _exportProgress = 0.0;
      });

      // Open the CSD file
      var csdFile = CsdFileHandler();
      await csdFile.load(_lastLoadedFilePath!);

      // Get file info
      final numChannels = csdFile.getProtocolHeader().numOfChannels;
      final protocolSamples = csdFile.getProtocolHeader().numOfSamples;
      final channelDescriptions = csdFile.getChannelDescriptions();
      final unitTexts = csdFile.getUnitTexts();
      final resolutions = csdFile.getResolutions();
      final startTime = csdFile.getStartTime();
      final sampleRate = csdFile.getProtocolHeader().sampleRate;

      // Calculate actual number of samples based on file size
      final file = File(_lastLoadedFilePath!);
      final fileSize = await file.length();
      final headerSize = CsdConstants.CHANNEL_HEADERS_START +
          (CsdConstants.CHANNEL_HEADER_LENGTH * numChannels);
      final recordLength = CsdConstants.RECORD_ID_LENGTH +
          (CsdConstants.CHANNEL_VALUE_LENGTH * numChannels);
      final dataSize = fileSize - headerSize;
      final actualSamples = (dataSize / recordLength).floor();

      // Use the smaller of the two to avoid errors
      final totalSamples = Math.min(protocolSamples, actualSamples);

      // Create and open output file
      final outputFile = File(outputPath);
      final sink = outputFile.openWrite();

      // Write header row
      final headerRow = [
        'Timestamp',
        ...List.generate(numChannels,
            (i) => _escapeCSV('${channelDescriptions[i]} (${unitTexts[i]})'))
      ];
      sink.writeln(headerRow.join(','));

      // Process in batches
      const batchSize = 1000;
      final totalBatches = (totalSamples / batchSize).ceil();

      for (int batch = 0; batch < totalBatches; batch++) {
        final startIndex = batch * batchSize;
        final endIndex =
            Math.min((batch + 1) * batchSize - 1, totalSamples - 1);

        // Update progress
        setState(() {
          _exportProgress = batch / totalBatches;
        });

        try {
          // Get batch data
          final batchData =
              await csdFile.getDataWithSampling(startIndex, endIndex);

          // Check if we got valid data
          if (batchData.isEmpty || batchData[0].isEmpty) {
            continue;
          }

          // Process each record in the batch
          for (int i = 0; i < batchData[0].length; i++) {
            final recordIndex = startIndex + i;
            final timestamp =
                startTime.add(Duration(seconds: recordIndex * sampleRate));
            final formattedTimestamp =
                DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);

            // Format values for each channel
            final values = List.generate(
                numChannels,
                (channel) => _escapeCSV(
                    _formatValue(batchData[channel][i], resolutions[channel])));

            // Write record to CSV
            sink.writeln([_escapeCSV(formattedTimestamp), ...values].join(','));
          }
        } catch (e) {
          print('Error processing batch $batch: $e');
          // Continue with next batch
        }

        // Allow UI to update
        await Future.delayed(const Duration(milliseconds: 1));
      }

      // Close files
      await sink.flush();
      await sink.close();
      await csdFile.close();

      setState(() {
        _isExporting = false;
        _exportProgress = 1.0;
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export completed: $outputPath'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      print('Error exporting to CSV: $e');
      setState(() {
        _isExporting = false;
      });

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Helper method to properly escape CSV values
  String _escapeCSV(String value) {
    // If the value contains commas, newlines, or quotes, wrap it in quotes
    if (value.contains(',') || value.contains('\n') || value.contains('"')) {
      // Double up any quotes in the value
      value = value.replaceAll('"', '""');
      // Wrap the value in quotes
      return '"$value"';
    }
    return value;
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
                        // Clear selected channels when toggling back from chart view
                        if (!_showChart) {
                          _selectedChannels = [];
                        }
                      });
                    },
                    icon:
                        Icon(_showChart ? Icons.arrow_back : Icons.show_chart),
                    label: Text(_showChart ? 'Back to Info' : 'Show Chart'),
                  ),
                  // Only show Export to CSV button when not in chart view
                  if (!_showChart) ...[
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _isExporting ? null : _exportToCSV,
                      icon: _isExporting
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: _exportProgress,
                              ),
                            )
                          : const Icon(Icons.download),
                      label:
                          Text(_isExporting ? 'Exporting...' : 'Export to CSV'),
                    ),
                  ],
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
                                  // Reset selected channels when changing the primary channel
                                  _selectedChannels = [];
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
                      selectedChannels:
                          _selectedChannels, // Pass selected channels
                      onChannelChanged: (value) {
                        setState(() {
                          _selectedChannel = value;
                        });
                      },
                      onSelectedChannelsChanged: (channels) {
                        setState(() {
                          _selectedChannels = channels;
                        });
                      },
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_lastLoadedFilePath != null) ...[
                          const Text(
                            'File Information:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildFileInfo(),
                        ],
                        if (_recordData.isNotEmpty && !hasError) ...[
                          const SizedBox(height: 20),
                          Expanded(
                            child: _buildRecordsTable(),
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

  // Update the file info display
  Widget _buildFileInfo() {
    if (_lastLoadedFilePath == null) return const SizedBox.shrink();

    // Use protocol header's numOfSamples instead of calculating from pages
    final needsFix = (_actualSamples - protocolHeader!.numOfSamples).abs() > 1;

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Number of channels: $_numChannels          Sample rate: $_sampleRate',
                  ),
                  if (needsFix)
                    ElevatedButton.icon(
                      onPressed: _fixFileData,
                      icon: const Icon(Icons.build, color: Colors.white),
                      label: const Text('Fix File'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
              Row(
                children: [
                  const Text(
                    'Number of records: ',
                  ),
                  Text(
                    '${protocolHeader!.numOfSamples}',
                    style: TextStyle(
                      color: needsFix ? Colors.red : null,
                      fontWeight: needsFix ? FontWeight.bold : null,
                    ),
                  ),
                  if (needsFix) ...[
                    Text(
                      ' (actual: $_actualSamples)',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                'Time period: ${_startTime != null ? DateFormat('yyyy-MM-dd HH:mm:ss').format(_startTime!) : ""} - ${_startTime != null ? DateFormat('yyyy-MM-dd HH:mm:ss').format(_startTime!.add(Duration(seconds: (_totalPages * _recordsPerPage - 1) * _sampleRate))) : ""}',
              ),
            ],
          ),
        ),
        if (_fileInfo.contains('Warning: No valid data')) ...[
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _fixFileData,
            icon: const Icon(Icons.build, color: Colors.white),
            label: const Text('Fix File'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRecordsTable() {
    final ScrollController horizontalController = ScrollController();
    final double columnSpacing = 24.0; // Reduced from 56.0

    // Define fixed column widths
    final double timestampWidth = 160.0; // For datetime
    final double channelWidth = 120.0; // For channel values

    final List<DataColumn> columns = [
      DataColumn(
        label: Container(
          width: timestampWidth,
          child: const Text(
            'Timestamp',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      ...List.generate(
        _numChannels,
        (index) => DataColumn(
          label: Container(
            width: channelWidth,
            child: Tooltip(
              message: _formatMinMaxRange(index),
              child: Text(
                '${_channelDescriptions[index]}\n(${_unitTexts[index]})',
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Records:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.first_page),
              onPressed: _currentPage > 0 && !_isLoadingRecords
                  ? () => _loadRecordPage(0)
                  : null,
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                  trackHeight: 4,
                  activeTrackColor: Colors.blue,
                  inactiveTrackColor: Colors.blue.withOpacity(0.3),
                  thumbColor: Colors.blue,
                  overlayColor: Colors.blue.withOpacity(0.3),
                ),
                child: Slider(
                  value: _sliderPosition,
                  onChanged: !_isLoadingRecords ? _handleSliderChange : null,
                  min: 0.0,
                  max: 1.0,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.last_page),
              onPressed: _currentPage < _totalPages - 1 && !_isLoadingRecords
                  ? () => _loadRecordPage(_totalPages - 1)
                  : null,
            ),
            const SizedBox(width: 16),
            if (_startTime != null)
              Text(
                DateFormat('yyyy-MM-dd HH:mm:ss').format(
                  _startTime!.add(Duration(
                      seconds: (_sliderPosition *
                              (_totalPages - 1) *
                              _recordsPerPage *
                              _sampleRate)
                          .round())),
                ),
                style: const TextStyle(fontSize: 14),
              ),
            const SizedBox(width: 16),
            Text(
              'Page ${_currentPage + 1}/$_totalPages',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: horizontalController,
                scrollDirection: Axis.horizontal,
                child: Column(
                  children: [
                    DataTable(
                      headingRowHeight: 56,
                      dataRowHeight: 0,
                      columnSpacing: columnSpacing,
                      horizontalMargin: 12, // Reduced margin
                      columns: columns,
                      rows: const [],
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                          headingRowHeight: 0,
                          dataRowHeight: 48,
                          columnSpacing: columnSpacing,
                          horizontalMargin: 12, // Same margin as header
                          columns: List.generate(
                            columns.length,
                            (index) => DataColumn(
                              label: Container(
                                width:
                                    index == 0 ? timestampWidth : channelWidth,
                                child: const SizedBox.shrink(),
                              ),
                            ),
                          ),
                          rows: _recordData.map((record) {
                            return DataRow(
                              cells: record.entries.map((entry) {
                                return DataCell(
                                  Container(
                                    width: entry.key == 'Record'
                                        ? timestampWidth
                                        : channelWidth,
                                    alignment: Alignment.center,
                                    child: Text(
                                      entry.value.toString(),
                                      style: const TextStyle(fontSize: 14),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoadingRecords)
                const Center(
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
