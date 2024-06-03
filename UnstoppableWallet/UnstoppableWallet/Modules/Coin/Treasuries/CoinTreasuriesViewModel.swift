import Combine
import Foundation
import HsExtensions
import MarketKit

class CoinTreasuriesViewModel: ObservableObject {
    private let coin: Coin
    private let marketKit = App.shared.marketKit
    private let currencyManager = App.shared.currencyManager

    private var cancellables = Set<AnyCancellable>()
    private var tasks = Set<AnyTask>()

    private var internalState: State = .loading {
        didSet {
            DispatchQueue.main.async { [weak self] in
                self?.syncState()
            }
        }
    }

    @Published var state: State = .loading
    @Published var orderedAscending: Bool = false

    var filter: Filter = .all {
        didSet {
            syncState()
        }
    }

    init(coin: Coin) {
        self.coin = coin

        sync()
    }

    private func sync() {
        tasks = Set()

        if case .failed = state {
            internalState = .loading
        }

        Task { [weak self, marketKit, coin, currencyManager] in
            do {
                let treasuries = try await marketKit.treasuries(coinUid: coin.uid, currencyCode: currencyManager.baseCurrency.code)
                DispatchQueue.main.async { [weak self] in
                    self?.internalState = .loaded(treasuries)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.internalState = .failed(error)
                }
            }
        }.store(in: &tasks)
    }

    private func syncState() {
        switch internalState {
        case .loading:
            state = .loading
        case let .loaded(treasuries):
            let treasuries = treasuries
                .filter {
                    switch filter {
                    case .all: return true
                    case .public: return $0.type == .public
                    case .private: return $0.type == .private
                    case .etf: return $0.type == .etf
                    }
                }
                .sorted { lhsTreasury, rhsTreasury in
                    orderedAscending ? lhsTreasury.amount < rhsTreasury.amount : lhsTreasury.amount > rhsTreasury.amount
                }

            state = .loaded(treasuries)
        case let .failed(error):
            state = .failed(error)
        }
    }
}

extension CoinTreasuriesViewModel {
    var currency: Currency {
        currencyManager.baseCurrency
    }

    var coinCode: String {
        coin.code
    }

    var filters: [Filter] {
        Filter.allCases
    }

    func toggleSortBy() {
        orderedAscending = !orderedAscending
        syncState()
    }

    func refresh() async {
        sync()
    }
}

extension CoinTreasuriesViewModel {
    enum State {
        case loading
        case loaded(_ treasuries: [CoinTreasury])
        case failed(_ error: Error)
    }

    enum Filter: String, CaseIterable {
        case all
        case `public`
        case `private`
        case etf

        var title: String {
            switch self {
            case .all: return "coin_analytics.treasuries.filter.all".localized
            case .public: return "coin_analytics.treasuries.filter.public".localized
            case .private: return "coin_analytics.treasuries.filter.private".localized
            case .etf: return "coin_analytics.treasuries.filter.etf".localized
            }
        }
    }
}
