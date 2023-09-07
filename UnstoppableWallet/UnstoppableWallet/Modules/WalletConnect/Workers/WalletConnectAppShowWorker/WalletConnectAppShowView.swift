import UIKit
import RxSwift
import RxCocoa
import ThemeKit
import WalletConnectSign
import ComponentKit

class WalletConnectAppShowView {
    private let disposeBag = DisposeBag()
    private let viewModel: WalletConnectAppShowViewModel
    private weak var parentViewController: UIViewController?

    init(viewModel: WalletConnectAppShowViewModel, parentViewController: UIViewController?) {
        self.viewModel = viewModel
        self.parentViewController = parentViewController

        subscribe(disposeBag, viewModel.showSessionRequestSignal) { [weak self] request in self?.handle(request: request) }
        subscribe(disposeBag, viewModel.openWalletConnectSignal) { [weak self] in self?.openWalletConnect(mode: $0) }
    }

    private func openWalletConnect(mode: WalletConnectAppShowViewModel.WalletConnectOpenMode) {
        switch mode {
        case .pair(let uri):
            switch WalletConnectUriHandler.uriVersion(uri: uri) {
            case 2:
                WalletConnectUriHandler.pair(uri: uri)
                        .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                        .observeOn(MainScheduler.instance)
                        .subscribe(onSuccess: { [weak self] in
                            self?.showPairedSuccessful()
                        }, onError: { [weak self] error in
                            self?.handle(error: error)
                        })
                        .disposed(by: disposeBag)
            default:
                handle(error: WalletConnectUriHandler.ConnectionError.wrongUri)
            }
        case .proposal(let proposal):
            processWalletConnectPair(proposal: proposal)
        case .errorDialog(let error):
            WalletConnectAppShowView.showWalletConnectError(error: error, sourceViewController: parentViewController)
        }
    }

    private func processWalletConnectPair(proposal: WalletConnectSign.Session.Proposal) {
        DispatchQueue.main.async { [weak self] in
            guard let viewController = WalletConnectMainModule.viewController(proposal: proposal, sourceViewController: self?.parentViewController?.visibleController) else {
                return
            }

            self?.parentViewController?.visibleController.present(viewController, animated: true)
        }
    }

    private func showPairedSuccessful() {
        HudHelper.instance.show(banner: .success(string: "Pairing successful. Please wait for a new session!"))
    }

    private func handle(error: Error) {
        HudHelper.instance.show(banner: .error(string: error.smartDescription))
    }

    private func handle(request: WalletConnectRequest) {
        guard let viewController = WalletConnectRequestModule.viewController(signService: App.shared.walletConnectSessionManager.service, request: request) else {
            return
        }

        parentViewController?.visibleController.present(ThemeNavigationController(rootViewController: viewController), animated: true)
    }

}

extension WalletConnectAppShowView {

    static func showWalletConnectError(error: WalletConnectOpenError, sourceViewController: UIViewController?) {
        let viewController: UIViewController

        switch error {
        case .noAccount:
            viewController = BottomSheetModule.viewController(
                    image: .local(image: UIImage(named: "wallet_connect_24")?.withTintColor(.themeJacob)),
                    title: "wallet_connect.title".localized,
                    items: [
                        .highlightedDescription(text: "wallet_connect.no_account.description".localized)
                    ],
                    buttons: [
                        .init(style: .yellow, title: "button.ok".localized)
                    ]
            )
        case .nonSupportedAccountType(let accountTypeDescription):
            viewController = BottomSheetModule.viewController(
                    image: .local(image: UIImage(named: "wallet_connect_24")?.withTintColor(.themeJacob)),
                    title: "wallet_connect.title".localized,
                    items: [
                        .highlightedDescription(text: "wallet_connect.non_supported_account.description".localized(accountTypeDescription))
                    ],
                    buttons: [
                        .init(style: .yellow, title: "wallet_connect.non_supported_account.switch".localized, actionType: .afterClose) { [weak sourceViewController] in
                            sourceViewController?.present(SwitchAccountModule.viewController(), animated: true)
                        },
                        .init(style: .transparent, title: "button.cancel".localized)
                    ]
            )
        case .unbackupedAccount(let account):
            viewController = BottomSheetModule.viewController(
                    image: .local(image: UIImage(named: "warning_2_24")?.withTintColor(.themeJacob)),
                    title: "backup_required.title".localized,
                    items: [
                        .highlightedDescription(text: "wallet_connect.unbackuped_account.description".localized(account.name))
                    ],
                    buttons: [
                        .init(style: .yellow, title: "backup_prompt.backup".localized, actionType: .afterClose) { [ weak sourceViewController] in
                            guard let viewController = BackupModule.manualViewController(account: account) else {
                                return
                            }

                            sourceViewController?.present(viewController, animated: true)
                        },
                        .init(style: .gray, title: "backup_prompt.backup_cloud".localized, imageName: "icloud_24", actionType: .afterClose) { [ weak sourceViewController] in
                            let viewController = BackupModule.cloudViewController(account: account)
                            sourceViewController?.present(viewController, animated: true)
                        },
                        .init(style: .transparent, title: "button.cancel".localized)
                    ]
            )
        }

        sourceViewController?.present(viewController, animated: true)
    }

    enum WalletConnectOpenError {
        case noAccount
        case nonSupportedAccountType(accountTypeDescription: String)
        case unbackupedAccount(account: Account)
    }

}

extension WalletConnectAppShowView: IDeepLinkHandler {

    func handle(deepLink: DeepLinkManager.DeepLink) {
        switch deepLink {
        case let .walletConnect(url):
            viewModel.onWalletConnectDeepLink(url: url)
        }
    }

}