import Foundation
import UIKit
import RxSwift
import RxCocoa

extension UIViewController {

    // キーボードが現れたときに、テキストフィールドをスクロールする
    // https://qiita.com/gamako/items/160460ddb8b39e394ebe
    func bindScrollTextFieldWhenShowKeyboard() {

        var disposeBag: DisposeBag? = DisposeBag()

        // この関数内で完結するように、dealloc時にdisposeしてくれる仕組みを用意する
        rx.deallocating
            .subscribe(onNext: { _ in
                disposeBag = nil
            })
            .disposed(by: disposeBag!)

        // viewAppearの間だけUIKeyboardが発行するNotificationを受け取るObserbaleを作る
        viewAppearedObservable()
            .flatMapLatest { event -> Observable<(Bool, Notification)> in
                if event {
                    // notificationは、(true=表示/false=非表示, NSNotification)のタプルで次のObservableに渡す
                    return Observable.of(
                        NotificationCenter.default.rx.notification(Notification.Name.UIKeyboardWillShow)
                            .map { (true, $0)},
                        NotificationCenter.default.rx.notification(Notification.Name.UIKeyboardWillHide)
                            .map { (false, $0)}
                        ).merge()
                } else {
                    return Observable<(Bool, Notification)>.empty()
                }
            }
            .subscribe (onNext: { [weak self] (isShow: Bool, notification: Notification) in
                // notificationに対して、適切にスクロールする処理
                guard let `self` = self else { return }
                if isShow {
                    self.keyboardWillBeShown(notification: notification)
                } else {
                    self.restoreScrollViewSize(notification: notification)
                }
            })
            .disposed(by: disposeBag!)
    }

    /// キーボード表示時にTextFieldの位置を変更
    private func keyboardWillBeShown(notification: Notification) {

        guard let textField = self.view.currentFirstResponder() as? UIView,
            let scrollView = textField.findSuperView(ofType: UIScrollView.self),
            let userInfo = notification.userInfo,
            let keyboardFrame = userInfo[UIKeyboardFrameEndUserInfoKey] as? CGRect,
            let animationDuration = userInfo[UIKeyboardAnimationDurationUserInfoKey] as? NSNumber
            else { return }

        scrollView.contentInset = UIEdgeInsets.zero
        scrollView.scrollIndicatorInsets = UIEdgeInsets.zero

        // textFieldの画面上の絶対座標
        let textFieldAbsPoint = textField.absPoint

        // 画面サイズ
        let screenSize = UIScreen.main.bounds.size

        // textFieldの底の位置の座標
        let textPosition = textFieldAbsPoint.y + textField.frame.height

        // キーボード位置
        let keyboardPosition = screenSize.height - keyboardFrame.size.height

        // 移動判定
        if textPosition >= keyboardPosition {

            // 移動距離
            let offsetY = textPosition - keyboardPosition

            // 移動
            UIView.animate(withDuration: TimeInterval(truncating: animationDuration)) {
                let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: offsetY, right: 0)
                scrollView.contentInset = contentInsets
                scrollView.scrollIndicatorInsets = contentInsets
                scrollView.contentOffset = CGPoint(x: 0, y: offsetY)
            }
        }
    }

    /// TextFieldを元の位置に戻す
    private func restoreScrollViewSize(notification: Notification) {
        guard let textField = self.view.currentFirstResponder() as? UIView,
            let scrollView = textField.findSuperView(ofType: UIScrollView.self) else { return }

        scrollView.contentInset = UIEdgeInsets.zero
        scrollView.scrollIndicatorInsets = UIEdgeInsets.zero
    }
}

extension UIView {

    // 親ビューをたどってFirstResponderを探す
    func currentFirstResponder() -> UIResponder? {
        if self.isFirstResponder {
            return self
        }

        for view in self.subviews {
            if let responder = view.currentFirstResponder() {
                return responder
            }
        }

        return nil
    }

    // 任意の型の親ビューを探す
    // 親をたどってScrollViewを探す場合などに使用する
    func findSuperView<T>(ofType: T.Type) -> T? {
        if let superView = self.superview {
            switch superView {
            case let superView as T:
                return superView
            default:
                return superView.findSuperView(ofType: ofType)
            }
        }

        return nil
    }

    /// 画面中の絶対座標
    var absPoint: CGPoint {
        var point = CGPoint(x: self.frame.origin.x, y: self.frame.origin.y)

        if let superview = self.superview {
            let addPoint = superview.absPoint
            point = CGPoint(x: point.x + addPoint.x, y: point.y + addPoint.y)
        }

        return point
    }
}

// http://blog.sgr-ksmt.org/2016/04/23/viewcontroller_trigger/
extension UIViewController {

    /// trigger event
    private func trigger(selector: Selector) -> Observable<Void> {
        return rx.sentMessage(selector).map { _ in () }.share(replay: 1)
    }

    var viewDidAppearTrigger: Observable<Void> {
        return trigger(selector: #selector(self.viewDidAppear(_:)))
    }

    var viewDidDisappearTrigger: Observable<Void> {
        return trigger(selector: #selector(self.viewDidDisappear(_:)))
    }

    func viewAppearedObservable() -> Observable<Bool> {
        return Observable.of(
            viewDidAppearTrigger.map { true } ,
            viewDidDisappearTrigger.map { false }
            )
            .merge()
    }
}
