import 'response/blufi_scan_result.dart';
import 'response/blufi_status_response.dart';
import 'response/blufi_version_response.dart';

// 状态码
const int blufiStatusSuccess = 0;
const int blufiCodeInvalidNotification = -1000;
const int blufiCodeCatchException = -1001;
const int blufiCodeWriteDataFailed = -1002;
const int blufiCodeInvalidData = -1003;
const int blufiCodeNegPostFailed = -2000;
const int blufiCodeNegErrDevKey = -2001;
const int blufiCodeNegErrSecurity = -2002;
const int blufiCodeNegErrSetSecurity = -2003;
const int blufiCodeConfInvalidOpmode = -3000;
const int blufiCodeConfErrSetOpmode = -3001;
const int blufiCodeConfErrPostSta = -3002;
const int blufiCodeConfErrPostSoftAP = -3003;
const int blufiCodeGattWriteTimeout = -4000;

/// BluFi 回调接口，继承后按需覆写
abstract class BlufiCallback {
  /// GATT 服务发现完成，可以开始发送 BluFi 数据包
  /// [status] 为 0 表示成功，非 0 表示失败（服务或特征未找到）
  /// [writeCharFound] / [notifyCharFound] 表示对应特征是否找到
  void onGattPrepared(int status,
      {bool writeCharFound = false, bool notifyCharFound = false}) {}

  /// 收到 GATT 通知原始数据，返回 true 表示已消费，不再走默认解析
  bool onGattNotification(int pkgType, int subType, List<int> data) => false;

  /// 收到设备错误码
  void onError(int errCode) {}

  /// 安全协商结果
  void onNegotiateSecurityResult(int status) {}

  /// 配网参数发送结果
  void onPostConfigureParams(int status) {}

  /// 收到设备版本
  void onDeviceVersionResponse(int status, BlufiVersionResponse? response) {}

  /// 收到设备 Wi-Fi 状态
  void onDeviceStatusResponse(int status, BlufiStatusResponse? response) {}

  /// 收到设备扫描到的 Wi-Fi 列表
  void onDeviceScanResult(int status, List<BlufiScanResult> results) {}

  /// 自定义数据发送结果
  void onPostCustomDataResult(int status, List<int> data) {}

  /// 收到设备发来的自定义数据
  void onReceiveCustomData(int status, List<int> data) {}
}
