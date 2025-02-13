import 'dart:io';
import 'dart:typed_data';
import 'dart:convert'; // Add this import for UTF-8 support
import 'dart:math' as Math;

/// Constants for special data values and file structure in CSD files
class CsdConstants {
  // Special data values
  static const double DATA_INVALID = -9999;
  static const double DATA_OVERRANGE = -8888;
  static const double DATA_SENSOR_CHANGE = -8887;
  static const double DATA_UNIT_CHANGE = -8886;

  // File structure constants
  static const int FILE_HEADER_LENGTH = 34;
  static const int PROTOCOL_HEADER_LENGTH = 3552;
  static const int CHANNEL_HEADER_LENGTH = 918;

  // Header positions
  static const int PROTOCOL_HEADER_START = FILE_HEADER_LENGTH;
  static const int CHANNEL_HEADERS_START =
      PROTOCOL_HEADER_START + PROTOCOL_HEADER_LENGTH;

  // Record structure
  static const int RECORD_ID_LENGTH = 4;
  static const int CHANNEL_VALUE_LENGTH = 8;

  static const int DATA_START_OFFSET = 3586;
  static const int CHANNEL_HEADER_SIZE = 918;
}

/// Represents the file information header of a CSD file
class CsdFileInfo {
  final int version; // 4 bytes (0-3)
  final String fileIdentifier; // 10 bytes (4-13)
  final int timestamp; // 8 bytes (14-21)
  final int dummy; // 8 bytes (22-29)
  final int recordPosition; // 4 bytes (30-33)

  CsdFileInfo({
    required this.version,
    required this.fileIdentifier,
    required this.timestamp,
    required this.dummy,
    required this.recordPosition,
  });
}

/// Represents the protocol header of a CSD file
class CsdProtocolHeader {
  final int pref;
  final int deviceId;
  final String description;
  final String testerName;
  final String companyName;
  final String companyAddress;
  final String serviceCompanyName;
  final String serviceCompanyAddress;
  final String deviceName;
  final double calibrationDate;
  final int numOfDevices;
  final int numOfChannels;
  final int numOfSamples;
  final int sampleRate;
  final int sampleRateFactor;
  final int timeOfFirstSample;
  final int stopTime;
  final int status;
  final int firmwareVersion;
  final int firstSamplePointer;
  final int crc;
  final int deviceType;
  final int origin;

  CsdProtocolHeader({
    required this.pref,
    required this.deviceId,
    required this.description,
    required this.testerName,
    required this.companyName,
    required this.companyAddress,
    required this.serviceCompanyName,
    required this.serviceCompanyAddress,
    required this.deviceName,
    required this.calibrationDate,
    required this.numOfDevices,
    required this.numOfChannels,
    required this.numOfSamples,
    required this.sampleRate,
    required this.sampleRateFactor,
    required this.timeOfFirstSample,
    required this.stopTime,
    required this.status,
    required this.firmwareVersion,
    required this.firstSamplePointer,
    required this.crc,
    required this.deviceType,
    required this.origin,
  });
}

/// Represents a channel header in a CSD file
class CsdChannelHeader {
  final int pref; // long (8 bytes) - offset 0xe02
  final String
      channelDescription; // string (128 bytes) + short (2 bytes) for length
  final String
      subDeviceDescription; // string (128 bytes) + short (2 bytes) for length
  final String
      deviceDescription; // string (19 bytes) + short (2 bytes) for length
  final String
      sensorDescription; // string (19 bytes) + short (2 bytes) for length
  // Reserved 470 bytes
  final int channelNumber; // int (4 bytes) - offset 0x110e
  final int unit; // int (4 bytes)
  final String unitText; // string (58 bytes) + short (2 bytes) for length
  final int resolution; // int (4 bytes) - offset 0x1152
  final double min; // double (8 bytes)
  final double max; // double (8 bytes)
  final int deviceId; // int (4 bytes)
  final int subDeviceId; // int (4 bytes)
  final int sensorId; // int (4 bytes)
  final int channelId; // int (4 bytes)
  final int channelConfig; // byte (1 byte)
  final int slaveAddress; // unsigned char (1 byte)
  final int deviceType; // unsigned short (2 bytes)
  final List<int> deviceUniqueId; // byte[8]
  // Reserved 22 bytes
  // Total: 918 bytes

  CsdChannelHeader({
    required this.pref,
    required this.channelDescription,
    required this.subDeviceDescription,
    required this.deviceDescription,
    required this.sensorDescription,
    required this.channelNumber,
    required this.unit,
    required this.unitText,
    required this.resolution,
    required this.min,
    required this.max,
    required this.deviceId,
    required this.subDeviceId,
    required this.sensorId,
    required this.channelId,
    required this.channelConfig,
    required this.slaveAddress,
    required this.deviceType,
    required this.deviceUniqueId,
  });
}

/// Main class to handle CSD files
class CsdFileHandler {
  late final String _filePath;
  late final RandomAccessFile _file;
  CsdFileInfo? _fileInfo;
  CsdProtocolHeader? _protocolHeader;
  List<CsdChannelHeader>? _channelHeaders;

  // Add this constant
  static const int MAX_DISPLAY_SAMPLES = 3000;

  /// Opens a CSD file for reading
  Future<void> load(String filePath) async {
    _filePath = filePath;
    print('Opening file: $_filePath');
    _file = await File(filePath).open();

    print('Reading file info...');
    await _readFileInfo();

    print('Reading protocol header...');
    await _readProtocolHeader();

    print('Reading channel headers...');
    await _readChannelHeaders();

    print('Reading initial data records...');
    final numChannels = _protocolHeader!.numOfChannels;
    final recordLength = CsdConstants.RECORD_ID_LENGTH +
        (CsdConstants.CHANNEL_VALUE_LENGTH * numChannels);

    final dataStartPosition = CsdConstants.CHANNEL_HEADERS_START +
        (CsdConstants.CHANNEL_HEADER_LENGTH * numChannels);

    print('Data start position: $dataStartPosition');
    await _file.setPosition(dataStartPosition);

    Future<Uint8List> debugRead(int length) async {
      var buffer = await _file.read(length);
      print(
          'Read ${buffer.length} bytes at position ${await _file.position()}');
      return Uint8List.fromList(buffer);
    }

    for (int record = 0; record < 10; record++) {
      print('\nReading record $record...');
      var buffer = await debugRead(recordLength);
      var data = ByteData.sublistView(buffer);

      final recordId = data.getInt32(0, Endian.big);
      print('Record ID: $recordId');

      for (int channel = 0; channel < numChannels; channel++) {
        final valueOffset = CsdConstants.RECORD_ID_LENGTH +
            (channel * CsdConstants.CHANNEL_VALUE_LENGTH);
        final value = data.getFloat64(valueOffset, Endian.big);
        print('  Channel $channel: $value');
      }
    }
  }

  /// Reads the file information header
  Future<void> _readFileInfo() async {
    await _file.setPosition(0);
    var buffer = await _file.read(CsdConstants.FILE_HEADER_LENGTH);
    var data = ByteData.sublistView(buffer);

    _fileInfo = CsdFileInfo(
      version: data.getInt32(0, Endian.big),
      fileIdentifier: utf8.decode(buffer.sublist(4, 14)),
      timestamp: data.getInt64(14, Endian.big),
      dummy: data.getInt64(22, Endian.big),
      recordPosition: data.getInt32(30, Endian.big),
    );
  }

  /// Reads the protocol header
  Future<void> _readProtocolHeader() async {
    if (_fileInfo == null) throw StateError('File info not loaded');

    await _file.setPosition(CsdConstants.PROTOCOL_HEADER_START);
    var buffer = await _file.read(CsdConstants.PROTOCOL_HEADER_LENGTH);
    var data = ByteData.sublistView(buffer);
    _protocolHeader = CsdProtocolHeader(
      pref: data.getInt64(0, Endian.big), // long (8 bytes)
      deviceId: data.getInt32(8, Endian.big), // int (4 bytes)
      description:
          utf8.decode(buffer.sublist(14, 142)).trim(), // string (128 bytes)
      testerName:
          utf8.decode(buffer.sublist(144, 176)).trim(), // string (32 bytes)
      companyName:
          utf8.decode(buffer.sublist(178, 210)).trim(), // string (32 bytes)
      companyAddress:
          utf8.decode(buffer.sublist(212, 340)).trim(), // string (128 bytes)
      serviceCompanyName:
          utf8.decode(buffer.sublist(342, 374)).trim(), // string (32 bytes)
      serviceCompanyAddress:
          utf8.decode(buffer.sublist(376, 504)).trim(), // string (128 bytes)
      deviceName:
          utf8.decode(buffer.sublist(506, 538)).trim(), // string (32 bytes)
      calibrationDate: data.getFloat64(538, Endian.big), // double (8 bytes)
      // Reserved 2466 bytes
      numOfDevices: data.getInt32(3012, Endian.big), // 3046 - 34
      numOfChannels: data.getInt32(3016, Endian.big), // 3050 - 34
      numOfSamples: data.getInt32(3020, Endian.big), // 3054 - 34
      sampleRate: data.getInt32(3024, Endian.big), // 3058 - 34
      sampleRateFactor: data.getInt32(3028, Endian.big),
      timeOfFirstSample: data.getInt64(3032, Endian.big),
      stopTime: data.getInt64(3040, Endian.big),
      status: data.getInt32(3048, Endian.big),
      firmwareVersion: data.getInt16(3052, Endian.big),
      firstSamplePointer: data.getInt32(3054, Endian.big),
      crc: data.getInt16(3058, Endian.big),
      deviceType: data.getInt16(3060, Endian.big),
      origin: buffer[3062], // byte (1 byte)
      // Reserved 489 bytes
    );
  }

  /// Reads all channel headers
  Future<void> _readChannelHeaders() async {
    if (_protocolHeader == null) throw StateError('Protocol header not loaded');

    await _file.setPosition(CsdConstants.CHANNEL_HEADERS_START);
    _channelHeaders = [];

    for (int i = 0; i < _protocolHeader!.numOfChannels; i++) {
      var rawBuffer = await _file.read(CsdConstants.CHANNEL_HEADER_LENGTH);
      var buffer = Uint8List.fromList(rawBuffer);
      var data = ByteData.sublistView(buffer);

      // Read string lengths and data
      int pos = 8; // Start after pref (8 bytes)

      int channelDescLen = data.getInt16(pos, Endian.big);
      pos += 2;
      String channelDesc = safeUtf8Decode(
          buffer.sublist(pos, pos + channelDescLen),
          defaultValue: 'Channel $i');
      pos += 128; // Fixed length for channel description

      int subDeviceDescLen = data.getInt16(pos, Endian.big);
      pos += 2;
      String subDeviceDesc =
          safeUtf8Decode(buffer.sublist(pos, pos + subDeviceDescLen));
      pos += 128;

      int deviceDescLen = data.getInt16(pos, Endian.big);
      pos += 2;
      String deviceDesc =
          safeUtf8Decode(buffer.sublist(pos, pos + deviceDescLen));
      pos += 19;

      int sensorDescLen = data.getInt16(pos, Endian.big);
      pos += 2;
      String sensorDesc =
          safeUtf8Decode(buffer.sublist(pos, pos + sensorDescLen));
      pos += 19;

      pos += 470; // Skip reserved bytes

      // Now at offset 0x110e (channelNumber)
      int channelNumber = data.getInt32(pos, Endian.big);
      pos += 4;

      int unit = data.getInt32(pos, Endian.big);
      pos += 4;

      int unitTextLen = data.getInt16(pos, Endian.big);
      pos += 2;
      String unitText = safeUtf8Decode(buffer.sublist(pos, pos + unitTextLen),
          defaultValue: 'Unknown');
      pos += 58;

      // Now at offset 0x1152 (resolution)
      _channelHeaders!.add(CsdChannelHeader(
        pref: data.getInt64(0, Endian.big),
        channelDescription: channelDesc,
        subDeviceDescription: subDeviceDesc,
        deviceDescription: deviceDesc,
        sensorDescription: sensorDesc,
        channelNumber: channelNumber,
        unit: unit,
        unitText: unitText,
        resolution: data.getInt32(pos, Endian.big), // 0x1152
        min: data.getFloat64(pos + 4, Endian.big),
        max: data.getFloat64(pos + 12, Endian.big),
        deviceId: data.getInt32(pos + 20, Endian.big),
        subDeviceId: data.getInt32(pos + 24, Endian.big),
        sensorId: data.getInt32(pos + 28, Endian.big),
        channelId: data.getInt32(pos + 32, Endian.big),
        channelConfig: buffer[pos + 36], // 1 byte
        slaveAddress: buffer[pos + 37], // 1 byte
        deviceType: data.getInt16(pos + 38, Endian.big), // 2 bytes
        deviceUniqueId: buffer.sublist(pos + 40, pos + 48).toList(), // 8 bytes
      ));
    }
  }

  /// Gets the start time of the measurements
  DateTime getStartTime() {
    if (_protocolHeader == null) {
      throw StateError('File not loaded');
    }
    return DateTime.fromMillisecondsSinceEpoch(
        _protocolHeader!.timeOfFirstSample);
  }

  /// Gets the stop time of the measurements
  DateTime getStopTime() {
    if (_protocolHeader == null) {
      throw StateError('File not loaded');
    }
    return DateTime.fromMillisecondsSinceEpoch(_protocolHeader!.stopTime);
  }

  /// Gets the number of channels
  int getNumOfChannels() {
    if (_protocolHeader == null) {
      throw StateError('File not loaded');
    }
    return _protocolHeader!.numOfChannels;
  }

  /// Gets measurement data with sampling for large files
  Future<List<List<double>>> getDataWithSampling(int start, int end) async {
    if (_protocolHeader == null) {
      throw StateError('File not loaded');
    }

    final totalSamples = _protocolHeader!.numOfSamples;
    print('Total samples in file: $totalSamples');

    // Calculate sampling step
    int samplingStep = 1;
    if (totalSamples > MAX_DISPLAY_SAMPLES) {
      samplingStep = (totalSamples / MAX_DISPLAY_SAMPLES).ceil();
    }
    print('Using sampling step: $samplingStep');

    final numChannels = _protocolHeader!.numOfChannels;
    final recordLength = CsdConstants.RECORD_ID_LENGTH +
        (CsdConstants.CHANNEL_VALUE_LENGTH * numChannels);

    final dataStartPosition = CsdConstants.CHANNEL_HEADERS_START +
        (CsdConstants.CHANNEL_HEADER_LENGTH * numChannels);
    print('Data starts at position: $dataStartPosition');

    List<List<double>> result = List.generate(numChannels, (_) => []);

    final actualSamples = (totalSamples / samplingStep).floor();
    print('Will read $actualSamples samples');

    int progressCounter = 0;
    final progressInterval = actualSamples ~/ 10; // Report progress every 10%

    for (int i = 0; i < totalSamples; i += samplingStep) {
      if (progressCounter % progressInterval == 0) {
        print(
            'Reading progress: ${(progressCounter / actualSamples * 100).toStringAsFixed(1)}%');
      }
      progressCounter++;

      final position = dataStartPosition + (i * recordLength);
      await _file.setPosition(position);

      var buffer = await _file.read(recordLength);
      var data = ByteData.sublistView(Uint8List.fromList(buffer));

      for (int channel = 0; channel < numChannels; channel++) {
        final valueOffset = CsdConstants.RECORD_ID_LENGTH +
            (channel * CsdConstants.CHANNEL_VALUE_LENGTH);
        final value = data.getFloat64(valueOffset, Endian.big);
        result[channel].add(value);
      }
    }

    print('Finished reading data');
    return result;
  }

  /// Gets measurement data for a specific channel between start and end indices
  Future<List<double>> getData4Channel(
      int channelNo, int start, int end) async {
    if (_protocolHeader == null) {
      throw StateError('File not loaded');
    }
    if (channelNo >= _protocolHeader!.numOfChannels) {
      throw RangeError('Invalid channel number');
    }
    // TODO: Implement channel-specific data reading logic
    return [];
  }

  /// Closes the file
  Future<void> close() async {
    await _file.close();
  }

  List<String> getChannelDescriptions() {
    if (_channelHeaders == null) {
      throw StateError('Channel headers not loaded');
    }
    return _channelHeaders!.map((header) => header.channelDescription).toList();
  }

  List<String> getUnitTexts() {
    if (_channelHeaders == null) {
      throw StateError('Channel headers not loaded');
    }
    return _channelHeaders!.map((header) => header.unitText).toList();
  }

  List<int> getResolutions() {
    if (_channelHeaders == null) {
      throw StateError('Channel headers not loaded');
    }
    return _channelHeaders!.map((header) => header.resolution).toList();
  }

  String safeUtf8Decode(List<int> bytes, {String defaultValue = ''}) {
    try {
      return utf8.decode(bytes).trim();
    } catch (e) {
      print('Warning: UTF-8 decode failed, falling back to ASCII');
      try {
        return String.fromCharCodes(bytes.where((b) => b > 0 && b < 128))
            .trim();
      } catch (e) {
        print('Warning: ASCII decode failed, returning default value');
        return defaultValue;
      }
    }
  }

  CsdProtocolHeader getProtocolHeader() {
    if (_protocolHeader == null) {
      throw StateError('Protocol header not loaded');
    }
    return _protocolHeader!;
  }

  List<double> getChannelMins() {
    if (_channelHeaders == null) {
      throw StateError('Channel headers not loaded');
    }
    return _channelHeaders!.map((header) => header.min).toList();
  }

  List<double> getChannelMaxs() {
    if (_channelHeaders == null) {
      throw StateError('Channel headers not loaded');
    }
    return _channelHeaders!.map((header) => header.max).toList();
  }
}
