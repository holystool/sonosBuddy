import SwiftUI

// MARK: - 品牌色彩系统
/// 与 App Icon 保持一致的配色方案
extension Color {
    /// 品牌主色：#FF6B00（与图标橙色圆环一致）
    static let brand = Color(red: 1.0, green: 0.42, blue: 0.0)
    
    /// 品牌深色背景：#1C1C1E（与图标背景一致）
    static let brandBackground = Color(red: 0.11, green: 0.11, blue: 0.12)
    
    /// 品牌深色背景（更深）：#0A0A0A
    static let brandBackgroundDeep = Color(red: 0.04, green: 0.04, blue: 0.04)
    
    /// 品牌次级色：用于次要强调
    static let brandSecondary = Color(red: 1.0, green: 0.55, blue: 0.28)
}
