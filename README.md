# Shareview — MoneyMoney Extension
Plugin Homepage: https://github.com/rosch100/Shareview-MoneyMoney
Bank/Portal: https://portfolio.shareview.co.uk
Version: **1.02**
Status: Username/Passwort + DOB + MFA; Cookie-Import optional
Hub (gemeinsame Tools/Doku): https://github.com/rosch100/moneymoney-extensions
## Installation
Unsignierte Datei: [Shareview.lua](https://raw.githubusercontent.com/rosch100/Shareview-MoneyMoney/main/Shareview.lua)
Datei nach `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions` kopieren, oder im Klon `./link_ext.sh` ausführen.
Unsignierte Plugins: MoneyMoney-**Beta**, Signaturprüfung in den Erweiterungseinstellungen aus.
## Tests
`sh
python3 tests/test_conformance.py
luajit tests/test_shareview.lua

`
Aus dem Repo-Root ausführen.

