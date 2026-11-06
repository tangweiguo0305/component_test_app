class BlufiVersionResponse {
  final int bigVer;
  final int smallVer;

  const BlufiVersionResponse(this.bigVer, this.smallVer);

  String get versionString => 'V$bigVer.$smallVer';

  @override
  String toString() => versionString;
}
