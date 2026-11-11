import 'package:flutter/material.dart';

/// 專門針對 Samsung Galaxy Z Fold 系列（外前屏 + 展開內大屏）及響應式屏幕的輔助判斷工具
class FoldUtils {
  /// 是否為 Samsung Z Fold 外部前屏幕（或極窄手機）
  /// Z Fold 前屏特點：寬度通常介乎 360dp ~ 415dp 之間，高度比非常長（>2.0:1）
  static bool isCoverScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width < 430;
  }

  /// 是否為 Samsung Z Fold 展開後的內部大屏幕（或接近 1:1 / 4:3 / 6:5 的折疊平板屏）
  /// Z Fold 內屏特點：寬度通常在 620dp ~ 960dp，長寬比接近正方形（0.75 ~ 1.45）
  static bool isFoldUnfolded(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final ratio = size.width / (size.height > 0 ? size.height : 1);
    final isUnfoldedWidth = size.width >= 580 && size.width <= 1100;
    final isSquareRatio = ratio >= 0.75 && ratio <= 1.45;
    return isUnfoldedWidth && isSquareRatio;
  }

  /// 是否為寬屏幕（包含 Z Fold 展開大屏、iPad 平板或桌面寬度）
  static bool isWideOrExpanded(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width >= 620;
  }

  /// 獲取根據屏幕形態推薦的自適應橫向 Padding
  static double getHorizontalPadding(BuildContext context) {
    if (isCoverScreen(context)) {
      return 12.0; // 前屏極窄，使用 12dp 避免壓縮
    } else if (isFoldUnfolded(context)) {
      return 20.0; // 內屏大屏，大氣邊距
    } else {
      return 24.0; // 桌面或大平板
    }
  }

  /// 獲取自適應字體縮放
  static double getTitleFontSize(BuildContext context) {
    if (isCoverScreen(context)) return 15.0;
    if (isFoldUnfolded(context)) return 18.0;
    return 19.0;
  }
}
