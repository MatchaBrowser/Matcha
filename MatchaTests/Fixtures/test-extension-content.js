// Script de contenu de l'extension d'essai des tests unitaires : il marque la page, que le test relit ; sur une page
// « #matcha-open-tab », il demande au service worker d'ouvrir un onglet.
document.body.dataset.matchaExtension = "1";
if (location.hash === "#matcha-open-tab") {
    browser.runtime.sendMessage("open-tab").then((reply) => {
        document.body.dataset.reply = String(reply);
    }).catch((error) => {
        document.body.dataset.reply = "error: " + error;
    });
}
