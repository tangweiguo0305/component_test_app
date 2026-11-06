// BluFi 协议常量定义

const String kBlufiServiceUuid = '0000ffff-0000-1000-8000-00805f9b34fb';
const String kBlufiWriteCharUuid = '0000ff01-0000-1000-8000-00805f9b34fb';
const String kBlufiNotifyCharUuid = '0000ff02-0000-1000-8000-00805f9b34fb';
const String kBlufiNotifyDescriptorUuid =
    '00002902-0000-1000-8000-00805f9b34fb';

const int kDefaultPackageLength = 20;
const int kPackageHeaderLength = 4;
const int kMinPackageLength = 20;
const int kGattWriteTimeout = 5000;

const int kDirectionOutput = 0;
const int kDirectionInput = 1;

const int kOpModeNull = 0x00;
const int kOpModeSta = 0x01;
const int kOpModeSoftAP = 0x02;
const int kOpModeStaSoftAP = 0x03;

const int kSoftAPSecurityOpen = 0x00;
const int kSoftAPSecurityWEP = 0x01;
const int kSoftAPSecurityWPA = 0x02;
const int kSoftAPSecurityWPA2 = 0x03;
const int kSoftAPSecurityWPAWPA2 = 0x04;

// 包类型
class PackageType {
  static const int ctrl = 0x00;
  static const int data = 0x01;
}

// Ctrl 子类型
class CtrlSubType {
  static const int ack = 0x00;
  static const int setSecMode = 0x01;
  static const int setOpMode = 0x02;
  static const int connectWifi = 0x03;
  static const int disconnectWifi = 0x04;
  static const int getWifiStatus = 0x05;
  static const int deauthenticate = 0x06;
  static const int getVersion = 0x07;
  static const int closeConnection = 0x08;
  static const int getWifiList = 0x09;
}

// Data 子类型
class DataSubType {
  static const int neg = 0x00;
  static const int staWifiBssid = 0x01;
  static const int staWifiSsid = 0x02;
  static const int staWifiPassword = 0x03;
  static const int softAPWifiSsid = 0x04;
  static const int softAPWifiPassword = 0x05;
  static const int softAPMaxConnectionCount = 0x06;
  static const int softAPAuthMode = 0x07;
  static const int softAPChannel = 0x08;
  static const int username = 0x09;
  static const int caCertification = 0x0a;
  static const int clientCertification = 0x0b;
  static const int serverCertification = 0x0c;
  static const int clientPrivateKey = 0x0d;
  static const int serverPrivateKey = 0x0e;
  static const int wifiConnectionState = 0x0f;
  static const int version = 0x10;
  static const int wifiList = 0x11;
  static const int error = 0x12;
  static const int customData = 0x13;
}
