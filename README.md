# LED Colors for Sailfish OS

*[Version française plus bas](#version-française)*

Pick the color of the notification LED per event and per app, and use night mode to keep the LED dark during set hours. Made for Sailfish OS phones with an RGB notification LED (developed and tested on the Jolla Phone 2026).

## Features

- One color per event: missed calls, SMS, e-mails, other notifications
- One color per app (Signal, WhatsApp, Element, Twitch...), picked from the list of installed apps
- Screen off: pending notifications blink one after the other, each in its own color; unlocking the phone clears them
- Night mode: a time range (it can span midnight) with no notification LED. Notifications received meanwhile are either shown afterwards if still unread, or ignored. The charging and battery lights can be turned off too
- A single switch puts the phone's own LED behaviour back
- English, French, German, Finnish

Colors are limited to the seven that the LED can blink reliably: red, green, blue, yellow, cyan, magenta, white.

## Installation

No computer, terminal or developer mode needed:

1. On the phone, open *Settings > Untrusted software* and allow it (Sailfish asks for this once for any app that does not come from the Jolla Store).
2. In the phone's browser, open https://github.com/Alzareus/harbour-ledcolor/releases/latest/download/harbour-ledcolor.noarch.rpm
3. When the download finishes, tap it (or open it from the *Files* app) and confirm the installation.

Updating works the same way: download the latest version and install it over the current one.

Over SSH, for developers: `devel-su pkcon install-local harbour-ledcolor.noarch.rpm`

This app is not in the Jolla Store: it needs to install an LED pattern file for mce and a user service, which Store rules do not allow.

## How it works

Nothing on the phone is ever rewritten, and the app never restarts system services on its own.

- At installation, the package adds one static file, `/etc/mce/89-harbour-ledcolor.ini`, with 14 fixed LED patterns (7 preview patterns, 7 notification colors). The install script then reloads mce once and checks that mce answers within 15 seconds. If it does not, the file is removed, mce is restored, and the service is not enabled.
- A **user** service (`harbour-ledcolor-notifywatch`, never root) watches notifications and switches the matching color pattern on and off over D-Bus.
- To stop the phone's own patterns (SMS, e-mail...) from showing their stock color at the same time, the service turns them off through mce's own per-pattern setting. It records which ones it turned off, and turns them back on when it stops, crashes, is disabled from the app, or when the package is removed.
- The service does nothing during the first two minutes after boot, and systemd gives up after 5 failed starts in 10 minutes.

Logs: `journalctl -t harbour-ledcolor -f`

## Emergency stop

```sh
touch ~/.config/harbour-ledcolor/disabled
systemctl --user restart harbour-ledcolor-notifywatch
```

The service then restores the stock LED behaviour and stays idle. Delete the file to re-enable it. To remove the only system file the package adds: `devel-su rm /etc/mce/89-harbour-ledcolor.ini`.

## Building

The package is plain QML and shell, so the Sailfish SDK is not required:

```sh
sudo apt install rpm      # or: sudo dnf install rpm-build
./build.sh                # -> build/harbour-ledcolor-<version>-1.noarch.rpm
```

Every push is built by GitHub Actions. To publish a new build, bump `Release:` (or `Version:`) in `rpm/harbour-ledcolor.spec` and run `./publish.sh "what changed"`: it commits, pushes and tags `v<Version>-<Release>`, and the workflow publishes a release with the RPM attached.

## Known limitations

- mce has a single e-mail pattern, so two mail accounts cannot have different colors.
- SMS, calls and e-mails are recognised from the notification category. If one of them is not detected on your device, the log shows the category that was received; please open an issue with that line.

## License

GPL-3.0-or-later, see [LICENSE](LICENSE).

---

## Version française

Choisissez la couleur de la LED de notification par événement et par application, et utilisez le mode nuit pour garder la LED éteinte sur une plage horaire. Conçue pour les téléphones Sailfish OS dotés d'une LED de notification RGB (développée et testée sur le Jolla Phone 2026).

### Fonctions

- Une couleur par événement : appels manqués, SMS, e-mails, autres notifications
- Une couleur par application (Signal, WhatsApp, Element, Twitch…), choisie dans la liste des apps installées
- Écran éteint : les notifications en attente clignotent à tour de rôle, chacune dans sa couleur ; le déverrouillage les efface
- Mode nuit : une plage horaire (qui peut passer minuit) sans LED de notification. Les notifications reçues pendant ce temps sont soit affichées ensuite si elles sont toujours non lues, soit ignorées. Les voyants de charge et de batterie peuvent aussi être éteints
- Un seul interrupteur rétablit le comportement d'origine du téléphone
- Anglais, français, allemand, finnois

Les couleurs se limitent aux sept que la LED sait faire clignoter correctement : rouge, vert, bleu, jaune, cyan, magenta, blanc.

### Installation

Ni ordinateur, ni terminal, ni mode développeur :

1. Sur le téléphone, ouvrez *Paramètres > Logiciels non fiables* et autorisez-les (Sailfish le demande une seule fois pour toute app qui ne vient pas du Jolla Store).
2. Dans le navigateur du téléphone, ouvrez https://github.com/Alzareus/harbour-ledcolor/releases/latest/download/harbour-ledcolor.noarch.rpm
3. Une fois le téléchargement terminé, touchez-le (ou ouvrez-le depuis l'app *Fichiers*) et confirmez l'installation.

La mise à jour se fait de la même façon : téléchargez la dernière version et installez-la par-dessus l'actuelle.

En SSH, pour les développeurs : `devel-su pkcon install-local harbour-ledcolor.noarch.rpm`

L'app n'est pas dans le Jolla Store : elle doit installer un fichier de motifs LED pour mce et un service utilisateur, ce que les règles du Store n'autorisent pas.

### Fonctionnement

Rien n'est jamais réécrit sur le téléphone, et l'app ne redémarre jamais de service système d'elle-même.

- À l'installation, le paquet ajoute un seul fichier statique, `/etc/mce/89-harbour-ledcolor.ini`, contenant 14 motifs LED fixes (7 pour l'aperçu, 7 couleurs de notification). Le script d'installation recharge ensuite mce une fois et vérifie qu'il répond dans les 15 secondes. Sinon, le fichier est retiré, mce est rétabli et le service n'est pas activé.
- Un service **utilisateur** (`harbour-ledcolor-notifywatch`, jamais root) surveille les notifications et allume ou éteint le motif de couleur correspondant via D-Bus.
- Pour que les motifs d'origine du téléphone (SMS, e-mail…) n'affichent pas leur couleur en même temps, le service les désactive via le réglage par motif de mce lui-même. Il note ceux qu'il a désactivés et les réactive quand il s'arrête, plante, est désactivé depuis l'app ou quand le paquet est désinstallé.
- Le service ne fait rien pendant les deux premières minutes après le démarrage, et systemd abandonne après 5 échecs en 10 minutes.

Journal : `journalctl -t harbour-ledcolor -f`

### Arrêt d'urgence

```sh
touch ~/.config/harbour-ledcolor/disabled
systemctl --user restart harbour-ledcolor-notifywatch
```

Le service rétablit alors le comportement d'origine de la LED et reste inactif. Supprimez le fichier pour le réactiver. Pour retirer le seul fichier système ajouté par le paquet : `devel-su rm /etc/mce/89-harbour-ledcolor.ini`.

### Compilation

Le paquet ne contient que du QML et du shell, le SDK Sailfish n'est donc pas nécessaire :

```sh
sudo apt install rpm      # ou : sudo dnf install rpm-build
./build.sh                # -> build/harbour-ledcolor-<version>-1.noarch.rpm
```

Chaque push est compilé par GitHub Actions. Pour publier une nouvelle version, incrémentez `Release:` (ou `Version:`) dans `rpm/harbour-ledcolor.spec` puis lancez `./publish.sh "ce qui change"` : le script committe, pousse et crée le tag `v<Version>-<Release>`, et le workflow publie une release avec le RPM en pièce jointe.

### Limites connues

- mce n'a qu'un seul motif e-mail : deux boîtes mail ne peuvent pas avoir des couleurs différentes.
- Les SMS, appels et e-mails sont reconnus grâce à la catégorie de la notification. Si l'un d'eux n'est pas détecté sur votre appareil, le journal indique la catégorie reçue ; ouvrez une issue avec cette ligne.

### Licence

GPL-3.0 ou ultérieure, voir [LICENSE](LICENSE).
