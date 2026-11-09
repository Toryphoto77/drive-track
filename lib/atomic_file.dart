import 'dart:io';

/// 原子写文件：先写同目录临时文件并 flush 到磁盘，再 rename 覆盖目标。
/// 同一文件系统内 rename 是原子的：进程被杀 / 断电时目标文件要么是
/// 旧的完整内容，要么是新的完整内容，不会出现写了一半的 JSON。
Future<void> writeStringAtomic(String path, String content) async {
  final tmp = File('$path.tmp');
  await tmp.writeAsString(content, flush: true);
  await tmp.rename(path);
}

/// 同步版本，供不能 await 的少数场景使用。
void writeStringAtomicSync(String path, String content) {
  final tmp = File('$path.tmp');
  tmp.writeAsStringSync(content, flush: true);
  tmp.renameSync(path);
}

/// 串行化异步临界区：同一个 [AsyncMutex] 上的 [run] 按调用顺序依次
/// 执行，避免“读索引 → await → 写索引”交错造成的丢更新。
class AsyncMutex {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
