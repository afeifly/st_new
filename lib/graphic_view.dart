import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'csd_file_handler.dart';
import 'package:intl/intl.dart'; // Add this import for date formatting
import 'dart:math' as Math;

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

  @override
  void initState() {
    super.initState();
    _initializeChart();
  }

  Future<void> _initializeChart() async {
    await _prepareChartData(_selectedChannel);
  }

  Future<void> _prepareChartData(int channelIndex) async {
    try {
      print('Starting _prepareChartData for channel $channelIndex');
      var csdFile = CsdFileHandler();
      print('Created CsdFileHandler');

      await csdFile.load(widget.filePath);
      print('Loaded file');

      final totalSamples = csdFile.getProtocolHeader().numOfSamples;
      _samplingStep = totalSamples > CsdFileHandler.MAX_DISPLAY_SAMPLES
          ? (totalSamples / CsdFileHandler.MAX_DISPLAY_SAMPLES).ceil()
          : 1;

      print('\nSampling information:');
      print('Total samples: $totalSamples');
      print('Sampling step: $_samplingStep');
      print('Sample rate: ${widget.sampleRate} seconds');
      print('Start time: ${widget.startTime}');

      var chartRecords = await csdFile.getDataWithSampling(0, totalSamples - 1);
      print('Finished reading data. Records length: ${chartRecords.length}');

      if (!mounted) return;

      _minY = widget.channelMins[channelIndex];
      _maxY = widget.channelMaxs[channelIndex];
      print('Set min/max: $_minY to $_maxY');

      double padding = (_maxY - _minY) * 0.1;
      _minY -= padding;
      _maxY += padding;

      if (!mounted) return;

      print('Creating chart data points...');
      final newChartData =
          List.generate(chartRecords[channelIndex].length, (index) {
        double timeInSeconds =
            (index * _samplingStep) * widget.sampleRate.toDouble();
        double value = chartRecords[channelIndex][index];
        return FlSpot(timeInSeconds, value);
      });
      print('Created ${newChartData.length} data points');

      setState(() {
        _chartData = newChartData;
      });
      print('Updated state with new chart data');

      print('Time range: 0 to ${_chartData.last.x} seconds');
      print('Start time: ${_getTimeString(0)}');
      print('End time: ${_getTimeString(_chartData.last.x)}');

      await csdFile.close();
      print('Closed file');
    } catch (e, stackTrace) {
      print('Error preparing chart data: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _chartData = [const FlSpot(0, 0)];
          _minY = 0;
          _maxY = 1;
        });
      }
    }
  }

  String _getTimeString(double value) {
    final DateTime time =
        widget.startTime.add(Duration(milliseconds: (value * 1000).toInt()));

    // For the first point, always show full date and time
    if (value == 0) {
      _lastDate = DateTime(time.year, time.month, time.day);
      return _fullFormatter.format(time);
    }

    // Allow 15 minutes tolerance around target hours (00:00, 06:00, 12:00, 18:00)
    final int minutesIntoDay = time.hour * 60 + time.minute;
    final targetHours = [0, 6, 12, 18];

    for (int targetHour in targetHours) {
      int targetMinutes = targetHour * 60;
      // Increase tolerance to 15 minutes to catch more points
      if ((minutesIntoDay - targetMinutes).abs() <= 15) {
        final DateTime currentDate = DateTime(time.year, time.month, time.day);
        if (_lastDate != currentDate) {
          _lastDate = currentDate;
          return _fullFormatter.format(time);
        }
        return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      }
    }

    return '';
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

  @override
  Widget build(BuildContext context) {
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
            child: _chartData.length <= 1
                ? const Center(child: CircularProgressIndicator())
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        horizontalInterval: (_maxY - _minY) / 5,
                        verticalInterval: _chartData.last.x / 10,
                      ),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          axisNameWidget: const SizedBox.shrink(),
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            interval: 3600 * 6, // 6 hours in seconds
                            getTitlesWidget: (value, meta) {
                              String timeStr = _getTimeString(value);
                              if (timeStr.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return SizedBox(
                                width: timeStr.length > 8 ? 140 : 80,
                                child: Text(
                                  timeStr,
                                  style: const TextStyle(fontSize: 10),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          axisNameWidget:
                              Text(widget.unitTexts[_selectedChannel]),
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 50,
                            interval: (_maxY - _minY) / 5,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                _formatValue(value),
                                style: const TextStyle(fontSize: 10),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: true),
                      minX: 0,
                      maxX: _chartData.last.x,
                      minY: _minY,
                      maxY: _maxY,
                      lineBarsData: [
                        LineChartBarData(
                          spots: _chartData,
                          isCurved: true,
                          curveSmoothness: 0.3,
                          color: Colors.blue,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(show: false),
                          preventCurveOverShooting: true,
                          isStrokeCapRound: true,
                        ),
                      ],
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
                              final timeInSeconds = touchedSpot.x;
                              // Always use full date/time format for tooltip
                              final DateTime time = widget.startTime.add(
                                  Duration(
                                      milliseconds:
                                          (timeInSeconds * 1000).toInt()));
                              final timeStr = _fullFormatter.format(time);
                              return LineTooltipItem(
                                '$timeStr\n'
                                '${_formatValue(value)} ${widget.unitTexts[_selectedChannel]}',
                                const TextStyle(
                                  color: Colors.black87,
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
                  ),
          ),
        ),
      ],
    );
  }
}
