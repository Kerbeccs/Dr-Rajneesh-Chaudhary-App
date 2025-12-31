// Stub file for web - File operations are not available on web
// This file is only used when compiling for web

/// Stub File class for web compilation
/// This will never be instantiated on web since kIsWeb check prevents it
class File {
  final String path;
  File(this.path);
  
  Future<File> writeAsBytes(List<int> bytes, {bool flush = false}) async {
    throw UnsupportedError('File operations not supported on web');
  }
}

