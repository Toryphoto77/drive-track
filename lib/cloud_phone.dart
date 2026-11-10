/// 云端手机号：国家或地区代码 + 国际格式。
///
/// CloudBase 短信登录要求号码带国家码，并且国家码与号码之间有一个空格，
/// 例如 `+86 13800000000`、`+852 51234567`。不是只支持中国大陆。
class PhoneCountry {
  final String dial;
  final String nameZh;
  final String nameEn;

  const PhoneCountry(this.dial, this.nameZh, this.nameEn);

  String label(bool zh) => zh ? '$nameZh $dial' : '$nameEn $dial';
}

/// 常用国家与地区。拨号码按长度从长到短匹配，避免 `+852` 被拆成 `+85`。
const List<PhoneCountry> kPhoneCountryCodes = [
  PhoneCountry('+86', '中国大陆', 'Mainland China'),
  PhoneCountry('+852', '中国香港', 'Hong Kong'),
  PhoneCountry('+853', '中国澳门', 'Macao'),
  PhoneCountry('+886', '中国台湾', 'Taiwan'),
  PhoneCountry('+81', '日本', 'Japan'),
  PhoneCountry('+82', '韩国', 'South Korea'),
  PhoneCountry('+65', '新加坡', 'Singapore'),
  PhoneCountry('+60', '马来西亚', 'Malaysia'),
  PhoneCountry('+66', '泰国', 'Thailand'),
  PhoneCountry('+84', '越南', 'Vietnam'),
  PhoneCountry('+62', '印度尼西亚', 'Indonesia'),
  PhoneCountry('+63', '菲律宾', 'Philippines'),
  PhoneCountry('+91', '印度', 'India'),
  PhoneCountry('+61', '澳大利亚', 'Australia'),
  PhoneCountry('+64', '新西兰', 'New Zealand'),
  PhoneCountry('+44', '英国', 'United Kingdom'),
  PhoneCountry('+49', '德国', 'Germany'),
  PhoneCountry('+33', '法国', 'France'),
  PhoneCountry('+39', '意大利', 'Italy'),
  PhoneCountry('+34', '西班牙', 'Spain'),
  PhoneCountry('+7', '俄罗斯', 'Russia'),
  PhoneCountry('+971', '阿联酋', 'United Arab Emirates'),
  PhoneCountry('+1', '美国 / 加拿大', 'United States / Canada'),
];

/// 默认中国大陆，用户可以改选其它国家或地区。
const String kDefaultPhoneDialCode = '+86';

/// 把区号和本地号码拼成 CloudBase 要的国际格式。
///
/// [rawLocal] 可以带空格、短横线或括号。已经带 `+` 或 `00` 时，保留用户
/// 写上的国家码，不再套用 [dialCode]。区号无效且号码本身没有国家码时，
/// 才补 `+86`。
String formatCloudPhoneNumber(String dialCode, String rawLocal) {
  final localRaw = rawLocal.trim();
  if (localRaw.startsWith('+') || localRaw.startsWith('00')) {
    return normalizeCloudPhoneNumber(localRaw);
  }
  final dial = dialCode.trim();
  if (!RegExp(r'^\+\d{1,4}$').hasMatch(dial)) {
    return normalizeCloudPhoneNumber(localRaw);
  }
  var local = localRaw.replaceAll(RegExp(r'[\s\-().]'), '');
  final dialDigits = dial.substring(1);
  if (local.startsWith(dialDigits) &&
      local.length - dialDigits.length >= 6) {
    local = local.substring(dialDigits.length);
  }
  local = local.replaceAll(RegExp(r'\D'), '');
  if (local.isEmpty) return '';
  return '$dial $local';
}

/// 规范成 `+区号 号码`。
///
/// 号码里已经有国家码（`+` 或 `00`）时按该国家码拆开，不改成 +86。
/// 只有完全没有国家码时才补 `+86`。
String normalizeCloudPhoneNumber(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final relaxed = trimmed
      .replaceAll(RegExp(r'[\-().]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final spaced = RegExp(r'^\+(\d{1,4}) (\d{6,15})$').firstMatch(relaxed);
  if (spaced != null) return '+${spaced.group(1)} ${spaced.group(2)}';

  var compact = trimmed.replaceAll(RegExp(r'[\s\-().]'), '');
  if (compact.startsWith('00')) compact = '+${compact.substring(2)}';
  if (!compact.startsWith('+')) {
    final digits = compact.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return '+86 $digits';
  }
  final digits = compact.substring(1).replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  PhoneCountry? best;
  for (final country in kPhoneCountryCodes) {
    final dialDigits = country.dial.substring(1);
    if (!digits.startsWith(dialDigits)) continue;
    if (digits.length - dialDigits.length < 6) continue;
    if (best == null || dialDigits.length > best.dial.length - 1) {
      best = country;
    }
  }
  if (best == null) return '';
  return '${best.dial} ${digits.substring(best.dial.length - 1)}';
}

/// CloudBase 短信接口接受的形态：`+`、1–4 位国家码、一个空格、6–15 位号码。
bool isValidCloudPhoneNumber(String phone) =>
    RegExp(r'^\+\d{1,4} \d{6,15}$').hasMatch(phone.trim());
