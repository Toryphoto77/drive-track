/// v0.1.9 个人页总里程格式化。
///
/// 根因：旧代码用 `'${km.toStringAsFixed(1)} km'` 直接拼进统计卡，
/// 数字与单位之间是普通空格，窄栏里 Text 默认可换行，长数字
/// （如 123456.7 km）会在空格处折成两行。
/// 本文件只做格式化，不做截断；不换行由调用方配合
/// FittedBox(scaleDown) + maxLines: 1 + softWrap: false 实现：
/// 数字先按千分位分组变短，再在栏宽内自适应缩小字号，单位始终
/// 跟在数字同一行，不会被挤到下一行。
library;

/// 公里数 → “12,345.6 km”式字符串（一位小数，整数部分千分位分组）。
/// [km] 为公里数（调用方传入 distanceM / 1000）。
String formatDistanceKm(double km) {
  final fixed = km.toStringAsFixed(1); // 如 "123456.7"
  final parts = fixed.split('.');
  final intPart = parts[0];
  final sign = intPart.startsWith('-') ? '-' : '';
  final digits = sign.isEmpty ? intPart : intPart.substring(1);
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '$sign${buf}${parts.length > 1 ? '.${parts[1]}' : ''} km';
}
