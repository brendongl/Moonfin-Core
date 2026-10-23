import 'package:flutter/material.dart';

import '../widgets/admin_form_styles.dart';

/// A number box for a config value, kept within [min]..[max]. Empty or
/// unreadable text writes [fallback]. Hands back an int, or a double when
/// [decimal].
TextFormField adminNumberInput({
  required String text,
  required ValueChanged<num> onChanged,
  required num fallback,
  num min = 0,
  num? max,
  bool decimal = false,
  bool enabled = true,
  String? suffixText,
}) {
  return TextFormField(
    initialValue: text,
    enabled: enabled,
    decoration: adminInputDecoration(suffixText: suffixText),
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    onChanged: (value) {
      var n = num.tryParse(value.trim()) ?? fallback;
      if (n < min) n = min;
      if (max != null && n > max) n = max;
      onChanged(decimal ? n.toDouble() : n.toInt());
    },
  );
}
