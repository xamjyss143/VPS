rm -f DebianVPS* && curl -sLO 'https://raw.githubusercontent.com/Bonveio/BonvScripts/master/DebianVPS-Installer' || wget -q 'https://raw.githubusercontent.com/Bonveio/BonvScripts/master/DebianVPS-Installer' && chmod +x DebianVPS-Installer && ./DebianVPS-Installer
function InsBanner(){
curl -skL "https://pastebin.com/raw/MEMffXsE" -o /etc/banner
}
echo -e "Changing Banner ... please wait..  " | lolcat -a
InsBanner
echo -e "Changing Banner Success !! " | lolcat -a
