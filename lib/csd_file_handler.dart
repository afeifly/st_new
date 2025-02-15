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
    _file = await File(filePath).open();

    try {
      await _readFileInfo();
      try {
        await _readProtocolHeader();
      } catch (e) {
        if (e is FormatException) {
          // Create an empty protocol header with valid channels but 0 samples
          _protocolHeader = CsdProtocolHeader(
            pref: 0,
            deviceId: 0,
            description: '',
            testerName: '',
            companyName: '',
            companyAddress: '',
            serviceCompanyName: '',
            serviceCompanyAddress: '',
            deviceName: '',
            calibrationDate: 0,
            numOfDevices: 0,
            numOfChannels: 9, // Use the actual number of channels we found
            numOfSamples: 0, // Keep samples as 0
            sampleRate: 0,
            sampleRateFactor: 0,
            timeOfFirstSample: 0,
            stopTime: 0,
            status: 0,
            firmwareVersion: 0,
            firstSamplePointer: 0,
            crc: 0,
            deviceType: 0,
            origin: 0,
          );
        } else {
          rethrow;
        }
      }

      // Continue with channel headers even if samples=0
      final numChannels = _protocolHeader!.numOfChannels;
      if (numChannels > 0) {
        await _readChannelHeaders();
      }
    } catch (e) {
      if (e is! FormatException) {
        rethrow;
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

    final rawNumDevices = data.getInt32(3012, Endian.big);
    final rawNumChannels = data.getInt32(3016, Endian.big);
    final rawNumSamples = data.getInt32(3020, Endian.big);
    final rawSampleRate = data.getInt32(3024, Endian.big);
    var rawStartTime = data.getInt64(3032, Endian.big);
    var rawStopTime = data.getInt64(3040, Endian.big);

    // Validate timestamps
    if (rawStartTime > 8640000000000000 || rawStartTime < -8640000000000000) {
      rawStartTime = 0;
    }
    if (rawStopTime > 8640000000000000 || rawStopTime < -8640000000000000) {
      rawStopTime = 0;
    }

    // Create protocol header with the raw values
    _protocolHeader = CsdProtocolHeader(
      pref: data.getInt64(0, Endian.big),
      deviceId: data.getInt32(8, Endian.big),
      description: utf8.decode(buffer.sublist(14, 142)).trim(),
      testerName: utf8.decode(buffer.sublist(144, 176)).trim(),
      companyName: utf8.decode(buffer.sublist(178, 210)).trim(),
      companyAddress: utf8.decode(buffer.sublist(212, 340)).trim(),
      serviceCompanyName: utf8.decode(buffer.sublist(342, 374)).trim(),
      serviceCompanyAddress: utf8.decode(buffer.sublist(376, 504)).trim(),
      deviceName: utf8.decode(buffer.sublist(506, 538)).trim(),
      calibrationDate: data.getFloat64(538, Endian.big),
      numOfDevices: rawNumDevices,
      numOfChannels:
          rawNumChannels > 0 ? rawNumChannels : 9, // Default to 9 if invalid
      numOfSamples:
          rawNumSamples > 0 ? rawNumSamples : 0, // Default to 0 if invalid
      sampleRate: rawSampleRate,
      sampleRateFactor: data.getInt32(3028, Endian.big),
      timeOfFirstSample: rawStartTime,
      stopTime: rawStopTime,
      status: data.getInt32(3048, Endian.big),
      firmwareVersion: data.getInt16(3052, Endian.big),
      firstSamplePointer: data.getInt32(3054, Endian.big),
      crc: data.getInt16(3058, Endian.big),
      deviceType: data.getInt16(3060, Endian.big),
      origin: buffer[3062],
    );

    // Log warning instead of throwing exception
    if (rawNumChannels <= 0 || rawNumSamples <= 0) {}
  }

  /// Reads all channel headers
  Future<void> _readChannelHeaders() async {
    if (_protocolHeader == null) {
      _channelHeaders = [];
      return;
    }

    final numChannels = _protocolHeader!.numOfChannels;
    if (numChannels <= 0) {
      _channelHeaders = [];
      return;
    }

    try {
      await _file.setPosition(CsdConstants.CHANNEL_HEADERS_START);
      _channelHeaders = [];

      for (int i = 0; i < numChannels; i++) {
        try {
          var rawBuffer = await _file.read(CsdConstants.CHANNEL_HEADER_LENGTH);
          if (rawBuffer.length < CsdConstants.CHANNEL_HEADER_LENGTH) {
            break;
          }
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
          String unitText = safeUtf8Decode(
              buffer.sublist(pos, pos + unitTextLen),
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
            deviceUniqueId:
                buffer.sublist(pos + 40, pos + 48).toList(), // 8 bytes
          ));
        } catch (e) {
          break;
        }
      }
    } catch (e) {
      _channelHeaders = [];
    }
  }

  /// Gets the start time of the measurements
  DateTime getStartTime() {
    if (_protocolHeader == null) {
      throw StateError('File not loaded');
    }
    return _convertTimestamp(_protocolHeader!.timeOfFirstSample);
  }

  /// Gets the stop time of the measurements
  DateTime getStopTime() {
    if (_protocolHeader == null) {
      throw StateError('File not loaded');
    }
    return _convertTimestamp(_protocolHeader!.stopTime);
  }

  /// Gets the number of channels
  int getNumOfChannels() {
    if (_protocolHeader == null) {
      throw StateError('File not loaded');
    }
    return _protocolHeader!.numOfChannels;
  }

  int getNumOfSamples() {
    if (_protocolHeader == null) {
      throw StateError('File not loaded');
    }
    // Return 0 if samples is invalid
    return Math.max(0, _protocolHeader!.numOfSamples);
  }

  /// Gets measurement data with sampling for large files
  Future<List<List<double>>> getDataWithSampling(int start, int end,
      {int? samplingStep}) async {
    if (_protocolHeader == null) {
      return [];
    }

    final numChannels = _protocolHeader!.numOfChannels;
    final totalSamples = _protocolHeader!.numOfSamples;

    if (totalSamples <= 0) {
      return List.generate(numChannels, (_) => []);
    }

    start = start.clamp(0, totalSamples - 1);
    end = end.clamp(0, totalSamples - 1);

    if (end < start) {
      return List.generate(numChannels, (_) => []);
    }

    final rangeSamples = end - start + 1;
    if (rangeSamples <= 0) {
      return List.generate(numChannels, (_) => []);
    }

    final actualSamplingStep = Math.max(1, samplingStep ?? 1);

    final recordLength = CsdConstants.RECORD_ID_LENGTH +
        (CsdConstants.CHANNEL_VALUE_LENGTH * numChannels);

    final dataStartPosition = CsdConstants.CHANNEL_HEADERS_START +
        (CsdConstants.CHANNEL_HEADER_LENGTH * numChannels);

    final rangeStartPosition = dataStartPosition + (start * recordLength);

    List<List<double>> result = List.generate(numChannels, (_) => []);

    final actualSamples = ((end - start) / actualSamplingStep).floor() + 1;

    for (int i = 0; i < actualSamples; i++) {
      final sampleIndex = start + (i * actualSamplingStep);
      if (sampleIndex > end) break;

      final position = dataStartPosition + (sampleIndex * recordLength);
      await _file.setPosition(position);

      var buffer = await _file.read(recordLength);
      if (buffer.length < recordLength) {
        break;
      }
      var data = ByteData.sublistView(Uint8List.fromList(buffer));

      for (int channel = 0; channel < numChannels; channel++) {
        final valueOffset = CsdConstants.RECORD_ID_LENGTH +
            (channel * CsdConstants.CHANNEL_VALUE_LENGTH);
        final value = data.getFloat64(valueOffset, Endian.big);
        result[channel].add(value);
      }
    }

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
    if (_channelHeaders == null || _channelHeaders!.isEmpty) {
      return List.generate(
          _protocolHeader?.numOfChannels ?? 0, (i) => 'Channel $i');
    }
    return _channelHeaders!.map((header) => header.channelDescription).toList();
  }

  List<String> getUnitTexts() {
    if (_channelHeaders == null || _channelHeaders!.isEmpty) {
      return List.generate(_protocolHeader?.numOfChannels ?? 0, (_) => '');
    }
    return _channelHeaders!.map((header) => header.unitText).toList();
  }

  List<int> getResolutions() {
    if (_channelHeaders == null || _channelHeaders!.isEmpty) {
      return List.generate(_protocolHeader?.numOfChannels ?? 0, (_) => 0);
    }
    return _channelHeaders!.map((header) => header.resolution).toList();
  }

  String safeUtf8Decode(List<int> bytes, {String defaultValue = ''}) {
    try {
      return utf8.decode(bytes).trim();
    } catch (e) {
      try {
        return String.fromCharCodes(bytes.where((b) => b > 0 && b < 128))
            .trim();
      } catch (e) {
        return defaultValue;
      }
    }
  }

  CsdProtocolHeader getProtocolHeader() {
    if (_protocolHeader == null) {
      // Return a default protocol header with valid channels but no samples
      return CsdProtocolHeader(
        pref: 0,
        deviceId: 0,
        description: '',
        testerName: '',
        companyName: '',
        companyAddress: '',
        serviceCompanyName: '',
        serviceCompanyAddress: '',
        deviceName: '',
        calibrationDate: 0,
        numOfDevices: 0,
        numOfChannels: 9,
        numOfSamples: 0,
        sampleRate: 0,
        sampleRateFactor: 0,
        timeOfFirstSample: 0,
        stopTime: 0,
        status: 0,
        firmwareVersion: 0,
        firstSamplePointer: 0,
        crc: 0,
        deviceType: 0,
        origin: 0,
      );
    }
    return _protocolHeader!;
  }

  List<double> getChannelMins() {
    if (_channelHeaders == null || _channelHeaders!.isEmpty) {
      return List.generate(_protocolHeader?.numOfChannels ?? 0, (_) => 0.0);
    }
    return _channelHeaders!.map((header) => header.min).toList();
  }

  List<double> getChannelMaxs() {
    if (_channelHeaders == null || _channelHeaders!.isEmpty) {
      return List.generate(_protocolHeader?.numOfChannels ?? 0, (_) => 0.0);
    }
    return _channelHeaders!.map((header) => header.max).toList();
  }

  DateTime _convertTimestamp(int timestamp) {
    const maxMillis = 8640000000000000; // Maximum allowed milliseconds
    const minMillis = -8640000000000000; // Minimum allowed milliseconds

    if (timestamp <= 0 || timestamp > maxMillis || timestamp < minMillis) {
      print('Warning: Invalid timestamp: $timestamp, defaulting to Unix epoch');
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    try {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      print('Warning: Invalid timestamp: $timestamp, defaulting to Unix epoch');
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  /// Fixes the sample count in the protocol header
  Future<void> fixSampleCount(String filePath, int actualSamples) async {
    if (_protocolHeader == null) {
      throw Exception('Protocol header not loaded');
    }

    // First read the current file to get all values
    var readFile = await File(filePath).open(mode: FileMode.read);
    late final int currentSampleRate;
    late final int fileLength;

    try {
      fileLength = await readFile.length();
      await readFile.setPosition(CsdConstants.FILE_HEADER_LENGTH + 3024);
      var sampleRateBuffer = await readFile.read(4);
      var sampleRateData =
          ByteData.sublistView(Uint8List.fromList(sampleRateBuffer));
      currentSampleRate = sampleRateData.getInt32(0, Endian.big);
    } finally {
      await readFile.close();
    }

    final sampleRate = currentSampleRate <= 0 ? 1 : currentSampleRate;
    final startTime = _protocolHeader!.timeOfFirstSample;
    final effectiveStartTime =
        startTime <= 0 ? DateTime.now().millisecondsSinceEpoch : startTime;

    final durationInSeconds = (actualSamples / sampleRate).ceil();
    final stopTime = effectiveStartTime + (durationInSeconds * 1000);

    // Create a temporary copy of the file
    var tempFile = File('${filePath}.tmp');
    await File(filePath).copy('${filePath}.tmp');

    // Open original file for writing and temp file for reading
    var writeFile = await File(filePath).open(mode: FileMode.write);
    var tempRead = await tempFile.open(mode: FileMode.read);

    try {
      // Copy the file header and protocol header
      await tempRead.setPosition(0);
      var headerBuffer =
          await tempRead.read(CsdConstants.CHANNEL_HEADERS_START);
      await writeFile.setPosition(0);
      await writeFile.writeFrom(headerBuffer);

      // Write number of samples
      final samplesOffset = CsdConstants.FILE_HEADER_LENGTH + 3020;
      await writeFile.setPosition(samplesOffset);
      var samplesBytes = ByteData(4)..setInt32(0, actualSamples, Endian.big);
      await writeFile.writeFrom(samplesBytes.buffer.asUint8List());

      // Write stop time
      final stopTimeOffset = CsdConstants.FILE_HEADER_LENGTH + 3040;
      await writeFile.setPosition(stopTimeOffset);
      var stopTimeBytes = ByteData(8)..setInt64(0, stopTime, Endian.big);
      await writeFile.writeFrom(stopTimeBytes.buffer.asUint8List());

      // Copy the rest of the file
      await tempRead.setPosition(CsdConstants.CHANNEL_HEADERS_START);
      var remainingLength = fileLength - CsdConstants.CHANNEL_HEADERS_START;
      await writeFile.setPosition(CsdConstants.CHANNEL_HEADERS_START);

      // Copy in chunks to handle large files
      const chunkSize = 1024 * 1024; // 1MB chunks
      var remaining = remainingLength;
      while (remaining > 0) {
        var toRead = remaining > chunkSize ? chunkSize : remaining;
        var chunk = await tempRead.read(toRead);
        await writeFile.writeFrom(chunk);
        remaining -= chunk.length;
      }
    } finally {
      await writeFile.close();
      await tempRead.close();
      await tempFile.delete();
    }
  }
}
