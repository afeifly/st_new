import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'csd_file_handler.dart';
import 'package:intl/intl.dart'; // Add this import for date formatting
import 'dart:math' as Math;

// Add these enums at the top of the file
enum TimeRange {
  hour,
  daily,
  monthly,
  total,
}

class GraphicView extends StatefulWidget {
  final String filePath;
  final DateTime startTime;
  final int numChannels;
  final List<int> resolutions;
  final List<String> channelDescriptions;
  final List<String> unitTexts;
  final int sampleRate;
  final List<double> channelMins;
  final List<double> channelMaxs;

  const GraphicView({
    super.key,
    required this.filePath,
    required this.startTime,
    required this.numChannels,
    required this.resolutions,
    required this.channelDescriptions,
    required this.unitTexts,
    required this.sampleRate,
    required this.channelMins,
    required this.channelMaxs,
  });

  @override
  State<GraphicView> createState() => _GraphicViewState();
}

class _GraphicViewState extends State<GraphicView> {
  int _selectedChannel = 0;
  List<FlSpot> _chartData = [const FlSpot(0, 0)];
  final DateFormat _fullFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');
  final DateFormat _timeFormatter = DateFormat('HH:mm:ss');
  DateTime? _lastDate;
  double _minY = 0;
  double _maxY = 0;
  bool _isLongLabel = false;
  int _samplingStep = 1;
  TimeRange _currentTimeRange = TimeRange.total;
  DateTime? _rangeStartTime;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentTimeRange = TimeRange.total; // Start with total view
    _rangeStartTime = widget.startTime; // Initialize range start time
    _initializeChart();
  }

  Future<void> _initializeChart() async {
    await _prepareChartData(_selectedChannel);
  }

  // Add this method to calculate the time-aligned range
  Future<(DateTime, DateTime)> _getAlignedTimeRange(TimeRange range) async {
    final startTime = widget.startTime;
    var csdFile = CsdFileHandler();
    await csdFile.load(widget.filePath);
    final stopTime = csdFile.getStopTime();
    await csdFile.close();

    switch (range) {
      case TimeRange.hour:
        // Align to the start of the hour
        final hourStart = DateTime(
          startTime.year,
          startTime.month,
          startTime.day,
          startTime.hour,
        );
        final hourEnd = hourStart.add(const Duration(hours: 1));
        return (hourStart, hourEnd);

      case TimeRange.daily:
        final dayStart = DateTime(
          startTime.year,
          startTime.month,
          startTime.day,
        );
        final dayEnd = dayStart.add(const Duration(days: 1));
        return (dayStart, dayEnd);

      case TimeRange.monthly:
        final monthStart = DateTime(
          startTime.year,
          startTime.month,
          1,
        );
        final monthEnd = DateTime(
          startTime.year,
          startTime.month + 1,
          1,
        );
        return (monthStart, monthEnd);

      case TimeRange.total:
        return (startTime, stopTime);
    }
  }

  Future<void> _prepareChartData(int channelIndex) async {
    setState(() {
      _isLoading = true;
    });

    try {
      print('Starting to prepare chart data for channel $channelIndex');
      var csdFile = CsdFileHandler();
      await csdFile.load(widget.filePath);

      final totalSamples = csdFile.getProtocolHeader().numOfSamples;

      // Calculate maximum points to display based on screen width
      final screenWidth = MediaQuery.of(context).size.width;
      final maxDisplayPoints = screenWidth ~/ 2; // 1 point per 2 pixels

      DateTime rangeStart = _rangeStartTime ?? widget.startTime;
      DateTime rangeEnd;

      // Calculate range end based on current view
      switch (_currentTimeRange) {
        case TimeRange.hour:
          rangeEnd = rangeStart.add(const Duration(hours: 1));
        case TimeRange.daily:
          rangeEnd = rangeStart.add(const Duration(days: 1));
        case TimeRange.monthly:
          rangeEnd = DateTime(
            rangeStart.year,
            rangeStart.month + 1,
            1,
          );
        case TimeRange.total:
          rangeStart = widget.startTime;
          rangeEnd = csdFile.getStopTime();
      }

      print('Range start: $rangeStart');
      print('Range end: $rangeEnd');

      // Calculate indices based on sample rate
      final startIndex = ((rangeStart.difference(widget.startTime).inSeconds) /
              widget.sampleRate)
          .floor();
      final endIndex = ((rangeEnd.difference(widget.startTime).inSeconds) /
              widget.sampleRate)
          .floor();

      print('Initial indices - Start: $startIndex, End: $endIndex');

      // Ensure indices are within bounds
      final actualStartIndex = startIndex.clamp(0, totalSamples - 1);
      final actualEndIndex = endIndex.clamp(0, totalSamples - 1);

      print('Clamped indices - Start: $actualStartIndex, End: $actualEndIndex');

      if (actualStartIndex >= actualEndIndex) {
        print('Invalid index range');
        throw Exception('Invalid time range');
      }

      // Calculate sampling step to limit number of points
      final rangeSamples = actualEndIndex - actualStartIndex + 1;
      _samplingStep = (rangeSamples / maxDisplayPoints).ceil();
      _samplingStep = Math.max(_samplingStep, 1);

      print('Range samples: $rangeSamples');
      print('Sampling step: $_samplingStep');

      // Get data with adjusted sampling
      final channelData = await csdFile.getDataWithSampling(
        actualStartIndex,
        actualEndIndex,
        samplingStep: _samplingStep, // Add this parameter to CsdFileHandler
      );

      setState(() {
        List<List<FlSpot>> segments = [[]];
        int currentSegment = 0;
        _minY = double.infinity;
        _maxY = double.negativeInfinity;

        // Process each data point
        for (int i = 0; i < channelData[channelIndex].length; i++) {
          final value = channelData[channelIndex][i];

          // Handle special values
          if (value == -9999.0 || value == -8888.0) {
            // Use actual special values
            if (segments[currentSegment].isNotEmpty) {
              segments.add([]);
              currentSegment++;
            }
            continue;
          }

          final timeOffset = Duration(
              seconds:
                  (actualStartIndex + i * _samplingStep) * widget.sampleRate);
          final pointTime = widget.startTime.add(timeOffset);
          final x = pointTime.difference(rangeStart).inSeconds / 3600.0;

          segments[currentSegment].add(FlSpot(x, value));

          if (value != -7777.0) {
            // Assuming -7777.0 is DATA_SENSOR_CHANGE
            _minY = Math.min(_minY, value);
            _maxY = Math.max(_maxY, value);
          }
        }

        // Add padding to Y-axis range
        if (_minY != double.infinity && _maxY != double.negativeInfinity) {
          final yRange = _maxY - _minY;
          _minY -= yRange * 0.1;
          _maxY += yRange * 0.1;
        } else {
          // Set default range if no valid data points
          _minY = 0;
          _maxY = 1;
        }

        // Update chart data
        _chartData = segments.expand((segment) => segment).toList();
        print('Created ${_chartData.length} chart points');
      });

      await csdFile.close();
    } catch (e, stack) {
      print('Error preparing chart data: $e');
      print('Stack trace: $stack');
      setState(() {
        _chartData = [const FlSpot(0, 0)];
        _minY = 0;
        _maxY = 1;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Add this helper method to format x-axis labels based on time range
  String _formatXAxisLabel(double value) {
    // Convert hours to seconds and consider sample rate
    final timeOffset =
        Duration(seconds: (value * 3600).round()); // value is in hours
    final dateTime =
        _rangeStartTime?.add(timeOffset) ?? widget.startTime.add(timeOffset);

    // Add debug print for label formatting
    print(
        'Formatting label for value $value -> ${_timeFormatter.format(dateTime)}');

    return switch (_currentTimeRange) {
      TimeRange.hour => _timeFormatter.format(dateTime),
      TimeRange.daily => _timeFormatter.format(dateTime),
      TimeRange.monthly => DateFormat('MM-dd').format(dateTime),
      TimeRange.total => DateFormat('MM-dd\nHH:mm').format(dateTime),
    };
  }

  String _getTimeString(double value) {
    final DateTime time =
        widget.startTime.add(Duration(milliseconds: (value * 1000).toInt()));

    // For the first point, always show full date and time
    if (value == 0) {
      _lastDate = DateTime(time.year, time.month, time.day);
      return _fullFormatter.format(time);
    }

    // Check if the date has changed
    final DateTime currentDate = DateTime(time.year, time.month, time.day);
    if (_lastDate != currentDate) {
      _lastDate = currentDate;
      return _fullFormatter.format(time);
    }

    // Otherwise, just show the time
    return _timeFormatter.format(time);
  }

  String _formatValue(double value) {
    int resolution = widget.resolutions[_selectedChannel];
    if (resolution <= 0) return value.toInt().toString();
    return value.toStringAsFixed(resolution);
  }

  void _onChannelChanged(int? value) {
    if (value == null) return;

    // Print channel info before changing
    print('\nChanging to channel: $value');
    print('Channel description: ${widget.channelDescriptions[value]}');
    print('Channel min: ${widget.channelMins[value]}');
    print('Channel max: ${widget.channelMaxs[value]}');
    print('Channel unit: ${widget.unitTexts[value]}\n');

    setState(() {
      _selectedChannel = value;
    });
    _prepareChartData(_selectedChannel);
  }

  Future<void> _showTimeRangeDialog() async {
    final result = await showDialog<TimeRange>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Time Range'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Last Hour'),
                leading: const Icon(Icons.access_time),
                onTap: () => Navigator.pop(context, TimeRange.hour),
              ),
              ListTile(
                title: const Text('Daily View'),
                leading: const Icon(Icons.calendar_today),
                onTap: () => Navigator.pop(context, TimeRange.daily),
              ),
              ListTile(
                title: const Text('Monthly View'),
                leading: const Icon(Icons.calendar_month),
                onTap: () => Navigator.pop(context, TimeRange.monthly),
              ),
              ListTile(
                title: const Text('Total View'),
                leading: const Icon(Icons.all_inclusive),
                onTap: () => Navigator.pop(context, TimeRange.total),
              ),
            ],
          ),
        );
      },
    );

    if (result != null && result != _currentTimeRange) {
      final (rangeStart, _) = await _getAlignedTimeRange(result);
      setState(() {
        _currentTimeRange = result;
        _rangeStartTime = rangeStart;
      });
      await _prepareChartData(_selectedChannel);
    }
  }

  double _calculateXAxisInterval() {
    // Always provide a minimum interval
    const double MIN_INTERVAL = 0.1; // 6 minutes

    if (_chartData.isEmpty || _chartData.length == 1) {
      return MIN_INTERVAL;
    }

    // Calculate total hours considering sample rate
    double totalHours = (_chartData.last.x - _chartData.first.x);

    if (totalHours <= 0) {
      return MIN_INTERVAL;
    }

    // Calculate intervals based on time range and sample rate
    double interval = switch (_currentTimeRange) {
      TimeRange.hour => Math.max(MIN_INTERVAL, 0.25), // 15-minute intervals
      TimeRange.daily => Math.max(2.0, totalHours / 12), // 12 intervals per day
      TimeRange.monthly =>
        Math.max(24.0, totalHours / 30), // 30 intervals per month
      TimeRange.total => Math.max(24.0, totalHours / 10), // 10 intervals total
    };

    print('Time range: ${_currentTimeRange.name}');
    print('Total hours: $totalHours');
    print('Calculated interval: $interval');

    return interval;
  }

  // Add these methods to handle time range navigation
  Future<void> _moveTimeRange(bool forward) async {
    var csdFile = CsdFileHandler();
    await csdFile.load(widget.filePath);
    final stopTime = csdFile.getStopTime();
    await csdFile.close();

    DateTime? newStartTime;
    switch (_currentTimeRange) {
      case TimeRange.hour:
        newStartTime = _rangeStartTime?.add(
          Duration(hours: forward ? 1 : -1),
        );
      case TimeRange.daily:
        newStartTime = _rangeStartTime?.add(
          Duration(days: forward ? 1 : -1),
        );
      case TimeRange.monthly:
        // Add or subtract one month
        if (_rangeStartTime != null) {
          if (forward) {
            newStartTime = DateTime(
              _rangeStartTime!.year,
              _rangeStartTime!.month + 1,
              1,
            );
          } else {
            newStartTime = DateTime(
              _rangeStartTime!.year,
              _rangeStartTime!.month - 1,
              1,
            );
          }
        }
      case TimeRange.total:
        return; // No navigation in total view
    }

    // Check if the new time is within valid range
    if (newStartTime != null) {
      if (newStartTime.isBefore(widget.startTime)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Already at the beginning of data')),
        );
        return;
      }
      if (newStartTime.isAfter(stopTime)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Already at the end of data')),
        );
        return;
      }

      setState(() {
        _rangeStartTime = newStartTime;
      });
      await _prepareChartData(_selectedChannel);
    }
  }

  Widget _buildChart(List<FlSpot> data, int channelIndex) {
    final min = widget.channelMins[channelIndex];
    final max = widget.channelMaxs[channelIndex];

    // Calculate y-axis range
    double minY, maxY;
    if (min == max || (min == 0 && max == 0)) {
      // If min equals max or both are zero, create a range around the value
      final baseValue = min == 0 ? 0 : min;
      minY = baseValue - 50; // Extend 50 units below
      maxY = baseValue + 50; // Extend 50 units above
    } else {
      // Add 10% padding to min/max for better visualization
      final range = max - min;
      final padding = range * 0.1;
      minY = min - padding;
      maxY = max + padding;
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: (maxY - minY) / 5,
          verticalInterval: _calculateXAxisInterval(),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (data.isEmpty) return const SizedBox.shrink();
                return Text(
                  _formatXAxisLabel(value),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10),
                );
              },
              interval: Math.max(0.1, _calculateXAxisInterval()),
              reservedSize: 40,
            ),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: Text(widget.unitTexts[channelIndex]),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              interval: Math.max(0.1, (maxY - minY) / 5),
              getTitlesWidget: (value, meta) {
                return Text(
                  _formatValue(value),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true),
        minX: data.isEmpty ? 0 : data.first.x,
        maxX: data.isEmpty ? 1 : data.last.x,
        minY: minY.isFinite ? minY : 0,
        maxY: maxY.isFinite ? maxY : 1,
        lineBarsData: [
          LineChartBarData(
            spots: data,
            isCurved: false, // Disable curve for better performance
            color: Colors.blue,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
            preventCurveOverShooting: true,
            isStrokeCapRound: true,
          ),
        ],
        lineTouchData: LineTouchData(
          enabled: true,
          touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
            if (event is FlTapUpEvent) {
              _showTimeRangeDialog();
            }
          },
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipPadding: const EdgeInsets.all(8),
            tooltipBorder: BorderSide(
              color: Colors.blueGrey.withOpacity(0.8),
              width: 1,
            ),
            tooltipRoundedRadius: 8,
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((LineBarSpot touchedSpot) {
                final value = touchedSpot.y;
                final timeInSeconds = touchedSpot.x;
                // Always use full date/time format for tooltip
                final DateTime time = widget.startTime.add(
                    Duration(milliseconds: (timeInSeconds * 1000).toInt()));
                final timeStr = _fullFormatter.format(time);
                return LineTooltipItem(
                  '$timeStr\n'
                  '${_formatValue(value)} ${widget.unitTexts[channelIndex]}',
                  const TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                );
              }).toList();
            },
          ),
          getTouchedSpotIndicator:
              (LineChartBarData barData, List<int> spotIndexes) {
            return spotIndexes.map((spotIndex) {
              return TouchedSpotIndicatorData(
                FlLine(
                  color: Colors.black45,
                  strokeWidth: 2,
                  dashArray: [5, 5],
                ),
                FlDotData(
                  getDotPainter: (spot, percent, barData, index) {
                    return FlDotCirclePainter(
                      radius: 4,
                      color: Colors.white,
                      strokeWidth: 2,
                      strokeColor: Colors.blue,
                    );
                  },
                ),
              );
            }).toList();
          },
          handleBuiltInTouches: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate the available width for the chart
    final double chartWidth =
        MediaQuery.of(context).size.width - 32; // Padding adjustment
    final int maxLabels =
        (chartWidth / 80).floor(); // Estimate max labels based on label width

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select Channel: ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<int>(
                value: _selectedChannel,
                items: List.generate(
                  widget.numChannels,
                  (index) => DropdownMenuItem(
                    value: index,
                    child: Text(
                      widget.channelDescriptions[index],
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
                onChanged: _onChannelChanged,
                underline: Container(),
                borderRadius: BorderRadius.circular(8),
                dropdownColor: Colors.grey[50],
                elevation: 3,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // Time range controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Time Range: ${_currentTimeRange.name.toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        if (_currentTimeRange != TimeRange.total) ...[
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => _moveTimeRange(false),
                            tooltip: 'Previous ${_currentTimeRange.name}',
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: () => _moveTimeRange(true),
                            tooltip: 'Next ${_currentTimeRange.name}',
                          ),
                          const SizedBox(width: 8),
                        ],
                        TextButton.icon(
                          onPressed: _showTimeRangeDialog,
                          icon: const Icon(Icons.access_time),
                          label: const Text('Change Range'),
                        ),
                      ],
                    ),
                  ],
                ),
                Expanded(
                  child: Stack(
                    children: [
                      if (_isLoading)
                        const Center(
                          child: CircularProgressIndicator(),
                        ),
                      if (!_isLoading && _chartData.length > 1)
                        Positioned.fill(
                          bottom: 40, // Height of x-axis labels
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: _showTimeRangeDialog,
                              child: Container(
                                color: Colors.transparent,
                                height: 40,
                                margin: const EdgeInsets.only(top: 8),
                              ),
                            ),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        height: double.infinity,
                        child: _chartData.length <= 1
                            ? const Center(
                                child: Text('No data available'),
                              )
                            : _buildChart(_chartData, _selectedChannel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
