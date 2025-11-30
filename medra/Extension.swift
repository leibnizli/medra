//
//  Extension.swift
//  medra
//
//  Created by admin on 2025/11/26.
//

#if os(iOS)
extension UIDevice {
    /// iOS App（含 iPhone/iPad）运行在 macOS（无需 Catalyst）
    static var isIPadAppRunningOnMac: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac
    }

    /// 非 iPad App 运行在 Mac（取反）
    static var isNotIPadAppRunningOnMac: Bool {
        !ProcessInfo.processInfo.isiOSAppOnMac
    }

    /// 是否 Mac Catalyst（App 是 Mac 原生 UI，不是 iOS App）
    static var isMacCatalyst: Bool {
        ProcessInfo.processInfo.isMacCatalystApp
    }

    /// 是否真机 iOS 设备
    static var isRunningOnRealIOSDevice: Bool {
        !(ProcessInfo.processInfo.isMacCatalystApp || ProcessInfo.processInfo.isiOSAppOnMac)
    }
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    static var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    static var isPortrait : Bool {
        UIDevice.current.orientation.isPortrait
    }
    
    static var width: CGFloat = UIScreen.main.bounds.width
    static var height: CGFloat = UIScreen.main.bounds.height
}
#endif
