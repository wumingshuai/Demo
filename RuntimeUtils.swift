//
//  RuntimeUtils.swift
//  Mac
//
//  Created by 吴明帅 on 2017/4/13.
//  Copyright © 2017年 Mac. All rights reserved.
//

import UIKit

// MARK: 觉醒协议
/// 实现此协议以代替 +load 和 +initialize， NSObject 类 已经默认实现此协议， 子类重写此方法即可
protocol Awarable {
    /**
     注意几个使用点：
     1. awake() 可能不止执行一次, 子类调用时会调用父类的awake；可以根据 self 的类型来判断
     2. 实现 awake() 方法要用 class func 不要用 static func，static func 不能被 override
     e.g.
     
     class Foo {
        ...
     }
     
     extension Foo: Awarable {
        class func awake() {
            guard self.description() == "Foo" else { retrun }
            do something ...
        }
     }
     
     class Bar: Foo {
        ...
     }
     
     extension Bar {
        override class func awake() {
            guard self.description() == "Bar" else { retrun }
            do something ...
        }
     }
     */
    static func awake()
}

// MARK: - 运行时工具
class RuntimeUtils {
    enum MethodType {
        case instance, `class`
    }
    
    /// swizzle 方法， 可以处理 实例方法 和 类方法 的交换 或 添加
    ///
    /// - Parameters:
    ///   - origSel: 原方法selector
    ///   - swizzleSel: 替换方法的selector
    ///   - targetClass: 目标类型
    ///   - type: 方法类型  实例方法 / 类方法； 默认是 实例方法
    static func swizzle(method origSel: Selector, with swizzleSel: Selector, for targetClass: AnyClass, type: MethodType = .instance) {
        guard let swizzleM = type.getMethod(targetClass, swizzleSel) else { return }
        guard let finalClass = type.finalClass(targetClass) else { return }
        
        if let origM = type.getMethod(targetClass, origSel) {
            if class_addMethod(finalClass, origSel, method_getImplementation(swizzleM), method_getTypeEncoding(swizzleM)) {
                class_replaceMethod(finalClass, swizzleSel, method_getImplementation(origM), method_getTypeEncoding(origM))
            } else {
                method_exchangeImplementations(origM, swizzleM)
            }
        } else {
            class_addMethod(finalClass, origSel, method_getImplementation(swizzleM), method_getTypeEncoding(swizzleM))
        }
    }
}

// MARK: - 私有方法
// MARK: 对 RuntimeUtils.MethodType 扩展，方便区分 instance 方法 和 class 方法
extension RuntimeUtils.MethodType {
    fileprivate var getMethod: (AnyClass, Selector) -> Method? {
        return self == .instance ? class_getInstanceMethod : class_getClassMethod
    }
    
    fileprivate var finalClass: (AnyClass) -> AnyClass? {
        switch self {
        case .instance:
            return { return $0 }
        case .class:
            return { return objc_getMetaClass(class_getName($0)) as? AnyClass }
        }
    }
}

// MARK: 类型觉醒的实现
extension RuntimeUtils {
    // 请在didFinishLaunching中掉用此方法
    static func classesAwake() {
        // 获取所有的 Class
        let count = Int(objc_getClassList(nil, 0))
        let classes = UnsafeMutablePointer<AnyClass>.allocate(capacity: count)
        let autoreleasingClasses = AutoreleasingUnsafeMutablePointer<AnyClass>(classes)
        objc_getClassList(autoreleasingClasses, Int32(count))
        // 遍历 class list
        for i in 0 ..< count {
            let target: AnyClass = classes[i]
            // 注：！！！
            /* 此实现有问题： NSObject及其子类， 实现 Awarable 的类型不会被调用，只有实现 Awarable 的子类会正常调用 awake() 方法； swift class 没有此Bug
             e.g. :
             extension UIScrollView: Awarable {
                class func awake() {
                    这个方法不会在 self == UIScrollView 时 调用， 只会在 self 是 UIScrollView 子类时调用
                }
             }
             
             extension UITableView {
                override class func awake() {
                    这个方法会背正常调用
                }
             }
             
             extension UIScreenEdgePanGestureRecognizer: Awarable {
                class func awake() {
                    因为 UIScreenEdgePanGestureRecognizer 没有子类，这个方法不会被调用
                }
             }
             
             ！！！解决方案： 默认让 NSObject 实现 Awarable， 给 awake() 方法一个空实现， 可以确保 NSObject 的子类 都可以正常的调用 awake() 方法； 同时不影响 swift 类型
             */
            (target as? Awarable.Type)?.awake()
        }
        classes.deallocate()
    }
}

// MARK: - NSObject 实现 Awarable 协议
extension NSObject: Awarable {
    /// 默认让 NSObject 实现 Awarable， 给 awake() 方法一个空实现， 可以确保 NSObject 的子类 都可以正常的调用 awake() 方法
    @objc class func awake() {}
}
