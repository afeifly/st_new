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
  final int pref;
  final String channelDescription;
  final String subDeviceDescription;
  final String deviceDescription;
  final String sensorDescription;
  final int channelNumber;
  final int unit;
  final String unitText;
  final int resolution;
  final double min;
  final double max;
  final int deviceId;
  final int subDeviceId;
  final int sensorId;
  final int channelId;
  final int channelConfig;
  final int slaveAddress;
  final int deviceType;
  final List<int> deviceUniqueId;

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

  /// Opens a CSD file for reading
  Future<void> load(String filePath) async {
    _filePath = filePath;
    _file = await File(filePath).open();
    await _readFileInfo();
    await _readProtocolHeader();
    await _readChannelHeaders();

    // Read first 10 records as a test
    print('\nReading first 10 records:');
    final numChannels = _protocolHeader!.numOfChannels;
    final recordLength = CsdConstants.RECORD_ID_LENGTH +
        (CsdConstants.CHANNEL_VALUE_LENGTH * numChannels);

    // Calculate data start position
    final dataStartPosition = CsdConstants.CHANNEL_HEADERS_START +
        (CsdConstants.CHANNEL_HEADER_LENGTH * numChannels);

    await _file.setPosition(dataStartPosition);

    for (int record = 0; record < 10; record++) {
      var buffer = await _file.read(recordLength);
      var data = ByteData.sublistView(buffer);

      // Read record ID (first 4 bytes)
      final recordId = data.getInt32(0, Endian.big);
      print('\nRecord $record (ID: $recordId):');

      // Read values for each channel
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

    // Add debug printing
    print('\nFile Info Debug:');
    print('Version: ${_fileInfo!.version}');
    print('File Identifier: ${_fileInfo!.fileIdentifier}');
    print('Timestamp: ${_fileInfo!.timestamp}');
    print('Dummy: ${_fileInfo!.dummy}');
    print('Record Position: ${_fileInfo!.recordPosition}');
    print(
        'Raw header bytes: ${buffer.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
  }

  /// Reads the protocol header
  Future<void> _readProtocolHeader() async {
    if (_fileInfo == null) throw StateError('File info not loaded');

    await _file.setPosition(CsdConstants.PROTOCOL_HEADER_START);
    var buffer = await _file.read(CsdConstants.PROTOCOL_HEADER_LENGTH);
    var data = ByteData.sublistView(buffer);

    print('\nProtocol Header Debug - Raw Values:');
    print('Pref (0-7): ${data.getInt64(0, Endian.big)}');
    print('DeviceID (8-11): ${data.getInt32(8, Endian.big)}');
    print(
        'Description (14-141): "${utf8.decode(buffer.sublist(14, 142)).trim()}"');
    print(
        'TesterName (144-175): "${utf8.decode(buffer.sublist(144, 176)).trim()}"');
    print(
        'CompanyName (178-209): "${utf8.decode(buffer.sublist(178, 210)).trim()}"');
    print(
        'CompanyAddress (212-339): "${utf8.decode(buffer.sublist(212, 340)).trim()}"');
    print(
        'ServiceCompanyName (342-373): "${utf8.decode(buffer.sublist(342, 374)).trim()}"');
    print(
        'ServiceCompanyAddress (376-503): "${utf8.decode(buffer.sublist(376, 504)).trim()}"');
    print(
        'DeviceName (506-537): "${utf8.decode(buffer.sublist(506, 538)).trim()}"');
    print('CalibrationDate (538-545): ${data.getFloat64(538, Endian.big)}');
    print('NumOfDevices (3012-3015): ${data.getInt32(3012, Endian.big)}');
    print('NumOfChannels (3016-3019): ${data.getInt32(3016, Endian.big)}');
    print('NumOfSamples (3020-3023): ${data.getInt32(3020, Endian.big)}');
    print('SampleRate (3024-3027): ${data.getInt32(3024, Endian.big)}');
    print('SampleRateFactor (3028-3031): ${data.getInt32(3028, Endian.big)}');
    print('TimeOfFirstSample (3032-3039): ${data.getInt64(3032, Endian.big)}');
    print('StopTime (3040-3047): ${data.getInt64(3040, Endian.big)}');
    print('Status (3048-3051): ${data.getInt32(3048, Endian.big)}');
    print('FirmwareVersion (3052-3053): ${data.getInt16(3052, Endian.big)}');
    print('FirstSamplePointer (3054-3057): ${data.getInt32(3054, Endian.big)}');
    print('CRC (3058-3059): ${data.getInt16(3058, Endian.big)}');
    print('DeviceType (3060-3061): ${data.getInt16(3060, Endian.big)}');
    print('Origin (3062): ${buffer[3062]}');

    // Print first few bytes in hex for debugging
    print('\nFirst 32 bytes in hex:');
    print(buffer
        .sublist(0, 32)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' '));

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

    // Debug printing
    print('Pref: ${_protocolHeader!.pref}');
    print('DeviceID: ${_protocolHeader!.deviceId}');
    print('Description: ${_protocolHeader!.description}');
    print('NumOfDevices: ${_protocolHeader!.numOfDevices}');
    print('NumOfChannels: ${_protocolHeader!.numOfChannels}');
    print('TimeOfFirstSample: ${_protocolHeader!.timeOfFirstSample}');
    print('StopTime: ${_protocolHeader!.stopTime}');
    print('Status: ${_protocolHeader!.status}');
    print('FirstSamplePointer: ${_protocolHeader!.firstSamplePointer}');
  }

  /// Reads all channel headers
  Future<void> _readChannelHeaders() async {
    if (_protocolHeader == null) throw StateError('Protocol header not loaded');

    await _file.setPosition(CsdConstants.CHANNEL_HEADERS_START);
    _channelHeaders = [];

    for (int i = 0; i < _protocolHeader!.numOfChannels; i++) {
      var buffer = await _file.read(CsdConstants.CHANNEL_HEADER_LENGTH);
      var data = ByteData.sublistView(buffer);

      // Try-catch for UTF-8 decoding
      String safeUtf8Decode(List<int> bytes) {
        try {
          return utf8.decode(bytes).trim();
        } catch (e) {
          // Fallback to ASCII if UTF-8 fails
          return String.fromCharCodes(bytes).trim();
        }
      }

      print('\nChannel $i Header Debug:');
      print('Pref: ${data.getInt32(0, Endian.big)}');
      print('Channel Description: "${safeUtf8Decode(buffer.sublist(4, 36))}"');
      print(
          'SubDevice Description: "${safeUtf8Decode(buffer.sublist(36, 68))}"');
      print('Device Description: "${safeUtf8Decode(buffer.sublist(68, 100))}"');
      print(
          'Sensor Description: "${safeUtf8Decode(buffer.sublist(100, 132))}"');
      print('Channel Number: ${data.getInt32(132, Endian.big)}');
      print('Unit: ${data.getInt32(136, Endian.big)}');
      print('Unit Text: "${safeUtf8Decode(buffer.sublist(140, 172))}"');
      print('Resolution: ${data.getInt32(172, Endian.big)}');
      print('Min: ${data.getFloat64(176, Endian.big)}');
      print('Max: ${data.getFloat64(184, Endian.big)}');
      print('Device ID: ${data.getInt32(192, Endian.big)}');
      print('SubDevice ID: ${data.getInt32(196, Endian.big)}');
      print('Sensor ID: ${data.getInt32(200, Endian.big)}');
      print('Channel ID: ${data.getInt32(204, Endian.big)}');
      print('Channel Config: ${data.getInt32(208, Endian.big)}');
      print('Slave Address: ${data.getInt32(212, Endian.big)}');
      print('Device Type: ${data.getInt32(216, Endian.big)}');
      print(
          'Device Unique ID: ${buffer.sublist(220, 236).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

      _channelHeaders!.add(CsdChannelHeader(
        pref: data.getInt32(0, Endian.big),
        channelDescription: safeUtf8Decode(buffer.sublist(4, 36)),
        subDeviceDescription: safeUtf8Decode(buffer.sublist(36, 68)),
        deviceDescription: safeUtf8Decode(buffer.sublist(68, 100)),
        sensorDescription: safeUtf8Decode(buffer.sublist(100, 132)),
        channelNumber: data.getInt32(132, Endian.big),
        unit: data.getInt32(136, Endian.big),
        unitText: safeUtf8Decode(buffer.sublist(140, 172)),
        resolution: data.getInt32(172, Endian.big),
        min: data.getFloat64(176, Endian.big),
        max: data.getFloat64(184, Endian.big),
        deviceId: data.getInt32(192, Endian.big),
        subDeviceId: data.getInt32(196, Endian.big),
        sensorId: data.getInt32(200, Endian.big),
        channelId: data.getInt32(204, Endian.big),
        channelConfig: data.getInt32(208, Endian.big),
        slaveAddress: data.getInt32(212, Endian.big),
        deviceType: data.getInt32(216, Endian.big),
        deviceUniqueId: buffer.sublist(220, 236).toList(),
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

  /// Gets measurement data for all channels between start and end indices
  Future<List<List<double>>> getData(int start, int end) async {
    if (_protocolHeader == null) {
      throw StateError('File not loaded');
    }

    final numChannels = _protocolHeader!.numOfChannels;
    final recordLength = CsdConstants.RECORD_ID_LENGTH +
        (CsdConstants.CHANNEL_VALUE_LENGTH * numChannels);

    // Calculate the start position of data section
    final dataStartPosition = CsdConstants.CHANNEL_HEADERS_START +
        (CsdConstants.CHANNEL_HEADER_LENGTH * numChannels);

    // Initialize result array for each channel
    List<List<double>> result = List.generate(numChannels, (_) => []);

    // Read data for requested range
    for (int i = start; i <= end; i++) {
      final position = dataStartPosition + (i * recordLength);
      await _file.setPosition(position);

      // Read one complete record
      var buffer = await _file.read(recordLength);
      var data = ByteData.sublistView(buffer);

      // Skip the 4-byte record ID
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
}
