import 'package:flutter/material.dart';

class InutilLogo extends StatelessWidget {
  const InutilLogo({this.size = 40, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icons/inutil_icon.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
    );
  }
}
