import Foundation
import Observation

/// Reprise d'une page (onglet, aperçu, mini-fenêtre) dont le processus s'est arrêté (tâche 5.7,
/// `NavigationCoordinator+Crash`). WebKit efface l'adresse et le titre de la vue web juste après avoir prévenu le
/// délégué : de l'arrêt jusqu'à la fin du chargement suivant, l'onglet garde les siens (`isRecovering`). Après des
/// arrêts répétés, la page montre un message et ne se recharge plus d'elle-même (`isShowingProblem`).
@MainActor
@Observable
final class PageCrashRecovery {
    /// Page suivie : relue à la fin du rechargement.
    @ObservationIgnored weak var page: BrowserTab?
    /// Message « Cette page a rencontré un problème » affiché par-dessus la page, jusqu'à ce qu'on la recharge.
    private(set) var isShowingProblem = false
    /// Vrai de l'arrêt du processus jusqu'à la fin du chargement suivant (terminé ou échoué) ou la libération de la vue.
    @ObservationIgnored private(set) var isRecovering = false
    @ObservationIgnored private var counter = PageCrashCounter()

    /// Le processus de la page vient de s'arrêter, à `date` : renvoie le nombre d'arrêts récents, celui-ci compris.
    func processDidTerminate(at date: Date) -> Int {
        isRecovering = true
        return counter.record(at: date)
    }

    /// Arrêts répétés : la page attend que l'utilisateur la recharge.
    func showProblem() {
        if !isShowingProblem {
            isShowingProblem = true
        }
    }

    /// Rechargement ou autre navigation demandés : le message part tout de suite ; l'adresse et le titre de l'onglet
    /// restent protégés jusqu'à la fin du chargement.
    func pageWillNavigate() {
        if isShowingProblem {
            isShowingProblem = false
        }
    }

    /// Chargement terminé ou échoué, vue web libérée : l'onglet suit de nouveau sa vue web. Les arrêts récents restent
    /// comptés.
    func end() {
        pageWillNavigate()
        guard isRecovering else {
            return
        }
        isRecovering = false
        page?.syncWithWebView()
    }
}
