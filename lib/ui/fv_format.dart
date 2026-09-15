String brMoney(num? value) {
  final v = (value ?? 0).toDouble();
  final neg = v < 0;
  final fixed = v.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final dec = parts[1];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
  }
  return '${neg ? '-' : ''}R\$ ${buf.toString()},$dec';
}

String fmtEstoque(num? value) {
  final v = (value ?? 0).toDouble();
  return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
}

String? produtoFotoUrlCompleta(String base, String? fotoUrl) {
  final f = (fotoUrl ?? '').trim();
  if (f.isEmpty) return null;
  if (f.startsWith('http://') || f.startsWith('https://')) return f;
  final b = base.replaceFirst(RegExp(r'/+$'), '');
  final path = f.startsWith('/') ? f : '/$f';
  return '$b$path';
}
