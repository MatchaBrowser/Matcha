// Service worker de l'extension d'essai des tests unitaires : à la demande du script de contenu, il ouvre un onglet
// vide en arrière-plan.
browser.runtime.onMessage.addListener((message) => {
    if (message === "open-tab") {
        return browser.tabs.create({ url: "about:blank", active: false })
            .then((tab) => "created " + tab.id)
            .catch((error) => "error: " + error.message);
    }
});
