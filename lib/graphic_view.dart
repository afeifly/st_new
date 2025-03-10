import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'csd_file_handler.dart';
import 'package:intl/intl.dart'; // Add this import for date formatting
import 'dart:math' as Math;
import 'dart:math';

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
  final int selectedChannel;
  final ValueChanged<int> onChannelChanged;
  final List<int> selectedChannels;
  final ValueChanged<List<int>>? onSelectedChannelsChanged;

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
    required this.selectedChannel,
    required this.onChannelChanged,
    this.selectedChannels = const [],
    this.onSelectedChannelsChanged,
  });

  @override
  State<GraphicView> createState() => _GraphicViewState();
}

class _GraphicViewState extends State<GraphicView> {
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

  // Add a map to store chart data for multiple channels
  Map<int, List<FlSpot>> _multiChannelData = {};
  // Add a list of chart colors
  final List<Color> _chartColors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.amber,
    Colors.indigo,
    Colors.cyan,
  ];

  @override
  void initState() {
    super.initState();
    _currentTimeRange = TimeRange.total;
    _rangeStartTime = widget.startTime;
    _initializeChart();
  }

  @override
  void didUpdateWidget(GraphicView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the selected channel changed, update the chart
    if (oldWidget.selectedChannel != widget.selectedChannel) {
      _prepareChartData(widget.selectedChannel);
    }
  }

  Future<void> _initializeChart() async {
    await _prepareChartData(widget.selectedChannel);
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
          rangeStart = DateTime(rangeStart.year, rangeStart.month,
              rangeStart.day, rangeStart.hour);
          rangeEnd = rangeStart.add(const Duration(hours: 1));
          break;
        case TimeRange.daily:
          rangeStart =
              DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
          rangeEnd = rangeStart.add(const Duration(days: 1));
          break;
        case TimeRange.monthly:
          rangeStart = DateTime(rangeStart.year, rangeStart.month, 1);
          rangeEnd = DateTime(rangeStart.year, rangeStart.month + 1, 1)
              .subtract(const Duration(days: 1));
          break;
        case TimeRange.total:
          rangeStart = widget.startTime;
          rangeEnd = csdFile.getStopTime();
          break;
      }

      // Calculate indices based on sample rate
      final startIndex = ((rangeStart.difference(widget.startTime).inSeconds) /
              widget.sampleRate)
          .floor();
      final endIndex = ((rangeEnd.difference(widget.startTime).inSeconds) /
              widget.sampleRate)
          .floor();

      // Ensure indices are within bounds
      final actualStartIndex = startIndex.clamp(0, totalSamples - 1);
      final actualEndIndex = endIndex.clamp(0, totalSamples - 1);

      if (actualStartIndex >= actualEndIndex) {
        throw Exception('Invalid time range');
      }

      // Calculate sampling step to limit number of points
      final rangeSamples = actualEndIndex - actualStartIndex + 1;
      _samplingStep = (rangeSamples / maxDisplayPoints).ceil();
      _samplingStep = Math.max(_samplingStep, 1);

      // Get data with adjusted sampling
      final channelData = await csdFile.getDataWithSampling(
        actualStartIndex,
        actualEndIndex,
        samplingStep: _samplingStep, // Add this parameter to CsdFileHandler
      );

      setState(() {
        // Clear previous data
        _multiChannelData.clear();

        // Determine which channels to process
        List<int> channelsToProcess = widget.selectedChannels.isNotEmpty
            ? widget.selectedChannels
            : [channelIndex]; // Fall back to single channel if none selected

        _minY = double.infinity;
        _maxY = double.negativeInfinity;

        // Process each selected channel
        for (int channel in channelsToProcess) {
          if (channel >= channelData.length) continue;

          List<List<FlSpot>> segments = [[]];
          int currentSegment = 0;

          // Process each data point for this channel
          for (int i = 0; i < channelData[channel].length; i++) {
            final value = channelData[channel][i];

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

          // Store the data for this channel
          _multiChannelData[channel] =
              segments.expand((segment) => segment).toList();
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

        // For backward compatibility, also update _chartData with the primary channel data
        _chartData = _multiChannelData[channelIndex] ?? [const FlSpot(0, 0)];
      });

      await csdFile.close();
    } catch (e, stack) {
      setState(() {
        _chartData = [const FlSpot(0, 0)];
        _multiChannelData.clear();
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
    final timeOffset = Duration(seconds: (value * 3600).round());
    final dateTime =
        _rangeStartTime?.add(timeOffset) ?? widget.startTime.add(timeOffset);

    // For monthly view, add extra check for first day
    if (_currentTimeRange == TimeRange.monthly) {
      // Skip label if it's too close to the start and not exactly at day 1
      if (value < _calculateXAxisInterval() * 0.5 && dateTime.day != 1) {
        return ''; // Return empty string to skip this label
      }
      // For first day of month, show full month name
      if (dateTime.day == 1) {
        return DateFormat('MMMM\nd').format(dateTime);
      }
      // For other days, show MM-dd format
      return DateFormat('MM-dd').format(dateTime);
    }

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
    int resolution = widget.resolutions[widget.selectedChannel];
    if (resolution <= 0) return value.toInt().toString();
    return value.toStringAsFixed(resolution);
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
                title: const Text('Hourly View'),
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
      await _prepareChartData(widget.selectedChannel);
    }
  }

  double _calculateXAxisInterval() {
    // Adjust intervals based on time range
    return switch (_currentTimeRange) {
      TimeRange.hour => 0.25, // 15-minute intervals
      TimeRange.daily => 2.0, // 2-hour intervals
      TimeRange.monthly => 24.0, // 1-day intervals
      TimeRange.total => Math.max(
          24.0,
          (_chartData.isEmpty ? 1 : _chartData.last.x) /
              10), // 10 intervals total
    };
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
        // For hourly view, check if any data exists in the previous hour
        if (!forward && newStartTime != null) {
          final hourStart = newStartTime;
          final hourEnd = hourStart.add(const Duration(hours: 1));
          // Allow going back if the previous hour contains the data start time
          if (hourEnd.isAfter(widget.startTime) &&
              hourStart.isBefore(widget.startTime)) {
            newStartTime = DateTime(
              widget.startTime.year,
              widget.startTime.month,
              widget.startTime.day,
              widget.startTime.hour,
            );
          }
        }
      case TimeRange.daily:
        newStartTime = _rangeStartTime?.add(
          Duration(days: forward ? 1 : -1),
        );
      case TimeRange.monthly:
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
      // For going back, check if the end of the new range includes data
      if (!forward) {
        final rangeEnd = switch (_currentTimeRange) {
          TimeRange.hour => newStartTime.add(const Duration(hours: 1)),
          TimeRange.daily => newStartTime.add(const Duration(days: 1)),
          TimeRange.monthly => DateTime(
              newStartTime.year,
              newStartTime.month + 1,
              1,
            ),
          TimeRange.total => stopTime,
        };

        if (rangeEnd.isBefore(widget.startTime)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Already at the beginning of data')),
          );
          return;
        }
      } else if (newStartTime.isAfter(stopTime)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Already at the end of data')),
        );
        return;
      }

      setState(() {
        _rangeStartTime = newStartTime;
      });
      await _prepareChartData(widget.selectedChannel);
    }
  }

  Widget _buildChart(List<FlSpot> data, int channelIndex) {
    final min = widget.channelMins[channelIndex];
    final max = widget.channelMaxs[channelIndex];

    // Calculate y-axis range with reasonable bounds
    double minY, maxY;
    if (min == max || (min == 0 && max == 0)) {
      // If min equals max or both are zero, create a range around the value
      final baseValue = min == 0 ? 0 : min;
      minY = baseValue - 50;
      maxY = baseValue + 50;
    } else {
      // Calculate nice number ranges
      final range = max - min;
      final absMin = min.abs();
      final absMax = max.abs();
      final maxAbs = Math.max(absMin, absMax);

      // Determine the appropriate scale
      double scale;
      if (maxAbs >= 100) {
        scale = 10.0;
      } else if (maxAbs >= 10) {
        scale = 5.0;
      } else if (maxAbs >= 1) {
        scale = 1.0;
      } else {
        scale = 0.1;
      }

      // Round to nice numbers
      minY = (min / scale).floor() * scale;
      maxY = (max / scale).ceil() * scale;

      // Add padding if range is too small
      if ((maxY - minY) < scale) {
        minY -= scale;
        maxY += scale;
      }
    }

    // Calculate x-axis range based on current time range
    double minX = 0;
    double maxX = switch (_currentTimeRange) {
      TimeRange.hour => 1.0, // 1 hour
      TimeRange.daily => 24.0, // 24 hours
      TimeRange.monthly => (_rangeStartTime!
              .add(Duration(
                  days: DateTime(
                          _rangeStartTime!.year, _rangeStartTime!.month + 1, 0)
                      .day))
              .difference(_rangeStartTime!)
              .inHours)
          .toDouble(), // Full month in hours
      TimeRange.total => data.isEmpty ? 1 : data.last.x,
    };

    // Determine which channels to display
    List<int> channelsToDisplay = widget.selectedChannels.isNotEmpty
        ? widget.selectedChannels
        : [channelIndex]; // Fall back to single channel if none selected

    // Check if all selected channels have the same unit
    String? commonUnit;
    bool sameUnit = true;
    if (channelsToDisplay.length > 1) {
      commonUnit = widget.unitTexts[channelsToDisplay.first];
      for (int i = 1; i < channelsToDisplay.length; i++) {
        if (widget.unitTexts[channelsToDisplay[i]] != commonUnit) {
          sameUnit = false;
          break;
        }
      }
    } else {
      commonUnit = widget.unitTexts[channelIndex];
    }

    // Prepare line bars data for each channel
    List<LineChartBarData> lineBars = [];
    for (int i = 0; i < channelsToDisplay.length; i++) {
      final channel = channelsToDisplay[i];
      // Skip channels with different units
      if (!sameUnit && channel != channelIndex) continue;

      final channelData = _multiChannelData[channel] ?? [];
      if (channelData.isEmpty) continue;

      // Use a different color for each channel
      final colorIndex = i % _chartColors.length;

      lineBars.add(
        LineChartBarData(
          spots: channelData,
          isCurved: false, // Disable curve for better performance
          color: _chartColors[colorIndex],
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
          preventCurveOverShooting: true,
          isStrokeCapRound: true,
        ),
      );
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
                // Skip the first label if it's too close to the axis
                if (value == data.first.x &&
                    value < _calculateXAxisInterval() * 0.5) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    _formatXAxisLabel(value),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
              interval: Math.max(0.1, _calculateXAxisInterval()),
              reservedSize: 40,
            ),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: Text(commonUnit ?? ''),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              interval: Math.max(0.1, (maxY - minY) / 5),
              getTitlesWidget: (value, meta) {
                // Skip the bottom value to prevent overlap with x-axis
                if (value == minY) {
                  return const SizedBox.shrink();
                }
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
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(color: Colors.grey),
            bottom: BorderSide(color: Colors.grey),
            top: BorderSide(
                color: Colors.transparent), // Make top border transparent
            right: BorderSide(
                color: Colors.transparent), // Make right border transparent
          ),
        ),
        minX: minX,
        maxX: maxX,
        minY: minY.isFinite ? minY : 0,
        maxY: maxY.isFinite ? maxY : 1,
        lineBarsData: lineBars.isEmpty
            ? [
                LineChartBarData(
                  spots: data,
                  isCurved: false,
                  color: Colors.blue,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                  preventCurveOverShooting: true,
                  isStrokeCapRound: true,
                ),
              ]
            : lineBars,
        lineTouchData: LineTouchData(
          enabled: true,
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
                final timeInHours = touchedSpot.x;
                // Calculate time based on _rangeStartTime instead of widget.startTime
                final DateTime time = _rangeStartTime!
                    .add(Duration(seconds: (timeInHours * 3600).round()));
                final timeStr = _fullFormatter.format(time);

                // Find which channel this spot belongs to
                int spotChannel = channelIndex;
                if (touchedSpot.barIndex < channelsToDisplay.length) {
                  spotChannel = channelsToDisplay[touchedSpot.barIndex];
                }

                return LineTooltipItem(
                  '$timeStr\n'
                  '${widget.channelDescriptions[spotChannel]}: ${_formatValue(value)} ${widget.unitTexts[spotChannel]}',
                  TextStyle(
                    color: _chartColors[
                        touchedSpot.barIndex % _chartColors.length],
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
                      strokeColor: barData.color ?? Colors.blue,
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

  // Add this method to show channel selection dialog
  Future<void> _showChannelSelectionDialog() async {
    // Group channels by unit
    Map<String, List<int>> channelsByUnit = {};
    for (int i = 0; i < widget.numChannels; i++) {
      final unit = widget.unitTexts[i];
      if (!channelsByUnit.containsKey(unit)) {
        channelsByUnit[unit] = [];
      }
      channelsByUnit[unit]!.add(i);
    }

    // Create a temporary list to track selections
    List<int> tempSelectedChannels = List.from(widget.selectedChannels.isEmpty
        ? [widget.selectedChannel]
        : widget.selectedChannels);
    String? selectedUnit = tempSelectedChannels.isNotEmpty
        ? widget.unitTexts[tempSelectedChannels.first]
        : null;

    final result = await showDialog<List<int>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Select Channels'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select channels with the same unit to display together:',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    if (selectedUnit != null) ...[
                      Chip(
                        label: Text('Unit: $selectedUnit'),
                        backgroundColor: Colors.blue.withOpacity(0.2),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: widget.numChannels,
                        itemBuilder: (context, index) {
                          final unit = widget.unitTexts[index];
                          final isEnabled =
                              selectedUnit == null || unit == selectedUnit;

                          return CheckboxListTile(
                            title: Text(widget.channelDescriptions[index]),
                            subtitle: Text('Unit: ${widget.unitTexts[index]}'),
                            value: tempSelectedChannels.contains(index),
                            activeColor: isEnabled ? Colors.blue : Colors.grey,
                            enabled: isEnabled,
                            onChanged: isEnabled
                                ? (bool? value) {
                                    setState(() {
                                      if (value == true) {
                                        // If this is the first selection, set the selected unit
                                        if (tempSelectedChannels.isEmpty) {
                                          selectedUnit = unit;
                                        }
                                        tempSelectedChannels.add(index);
                                      } else {
                                        tempSelectedChannels.remove(index);
                                        // If no channels are selected, reset the selected unit
                                        if (tempSelectedChannels.isEmpty) {
                                          selectedUnit = null;
                                        }
                                      }
                                    });
                                  }
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, tempSelectedChannels),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      // If no channels were selected, default to the current channel
      final selectedChannels =
          result.isEmpty ? [widget.selectedChannel] : result;

      // Call the callback to update the parent widget
      if (selectedChannels.length == 1) {
        // For a single channel, just update the selected channel
        widget.onChannelChanged(selectedChannels.first);
        // Also clear the selected channels list
        if (widget.onSelectedChannelsChanged != null) {
          widget.onSelectedChannelsChanged!([]);
        }
      } else if (selectedChannels.isNotEmpty) {
        // For multiple channels, update both the primary channel and the selected channels list
        widget.onChannelChanged(selectedChannels.first);

        if (widget.onSelectedChannelsChanged != null) {
          widget.onSelectedChannelsChanged!(selectedChannels);
        }

        // Show a confirmation message
        final scaffold = ScaffoldMessenger.of(context);
        scaffold.showSnackBar(
          SnackBar(
            content: Text('Selected ${selectedChannels.length} channels'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Update the chart with the selected channels
      setState(() {});
      await _prepareChartData(widget.selectedChannel);
    }
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
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: _showChannelSelectionDialog,
                          icon: const Icon(Icons.multiline_chart),
                          label: const Text('Select Channels'),
                        ),
                      ],
                    ),
                  ],
                ),
                // Display selected channels as chips
                if (widget.selectedChannels.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text(
                          'Selected: ',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        ...widget.selectedChannels.map((channelIndex) {
                          final colorIndex =
                              widget.selectedChannels.indexOf(channelIndex) %
                                  _chartColors.length;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text(
                                widget.channelDescriptions[channelIndex],
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _chartColors[colorIndex],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              backgroundColor:
                                  _chartColors[colorIndex].withOpacity(0.1),
                              side: BorderSide(color: _chartColors[colorIndex]),
                              visualDensity: VisualDensity.compact,
                              labelPadding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],
                Expanded(
                  child: Stack(
                    children: [
                      if (_isLoading)
                        const Center(
                          child: CircularProgressIndicator(),
                        ),
                      SizedBox(
                        width: double.infinity,
                        height: double.infinity,
                        child: _chartData.length <= 1
                            ? const Center(
                                child: Text('No data available'),
                              )
                            : _buildChart(_chartData, widget.selectedChannel),
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
