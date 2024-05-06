import BigInt
import Combine
import EvmKit
import Foundation
import MarketKit
import RxSwift

class EvmPreSendHandler {
    private let token: Token
    private let adapter: ISendEthereumAdapter & IBalanceAdapter

    private let balanceStateSubject = PassthroughSubject<AdapterState, Never>()
    private let balanceDataSubject = PassthroughSubject<BalanceData, Never>()

    private let disposeBag = DisposeBag()

    init(token: Token, adapter: ISendEthereumAdapter & IBalanceAdapter) {
        self.token = token
        self.adapter = adapter

        adapter.balanceStateUpdatedObservable
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe { [weak self] state in
                self?.balanceStateSubject.send(state)
            }
            .disposed(by: disposeBag)

        adapter.balanceDataUpdatedObservable
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe { [weak self] balanceData in
                self?.balanceDataSubject.send(balanceData)
            }
            .disposed(by: disposeBag)
    }
}

extension EvmPreSendHandler: IPreSendHandler {
    var balanceState: AdapterState {
        adapter.balanceState
    }

    var balanceStatePublisher: AnyPublisher<AdapterState, Never> {
        balanceStateSubject.eraseToAnyPublisher()
    }

    var balanceData: BalanceData {
        adapter.balanceData
    }

    var balanceDataPublisher: AnyPublisher<BalanceData, Never> {
        balanceDataSubject.eraseToAnyPublisher()
    }

    func sendData(amount: Decimal, address: String, memo _: String?) -> SendData? {
        guard let evmAmount = BigUInt(amount.hs.roundedString(decimal: token.decimals)) else {
            return nil
        }

        guard let evmAddress = try? EvmKit.Address(hex: address) else {
            return nil
        }

        let transactionData = adapter.transactionData(amount: evmAmount, address: evmAddress)

        return .evm(blockchainType: token.blockchainType, transactionData: transactionData)
    }
}
