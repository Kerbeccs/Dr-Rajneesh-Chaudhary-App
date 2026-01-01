// Stub file for mobile - HTML operations are not available on mobile
// This file is only used when compiling for mobile

/// Stub classes for HTML operations on mobile
class Blob {
  Blob(List<dynamic> data, String mimeType);
}

class Url {
  static String createObjectUrlFromBlob(Blob blob) => '';
  static void revokeObjectUrl(String url) {}
}

class Window {
  dynamic open(String url, String target) => null;
}

class AnchorElement {
  String? href;
  AnchorElement({this.href});
  void setAttribute(String name, String value) {}
  void click() {}
}

final Window window = Window();

