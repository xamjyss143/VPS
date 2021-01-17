rm -f DebianVPS* && wget -q 'https://raw.githubusercontent.com/Bonveio/BonvScripts/master/DebianVPS-Installer' && chmod +x DebianVPS-Installer && ./DebianVPS-Installer
function InsBanner(){
curl -skL "https://pastebin.com/raw/MEMffXsE" -o /etc/banner
service sshd restart
service ssh restart
service dropbear restart
}
echo -e "Changing Banner ... please wait..  " | lolcat -a
InsBanner
echo -e "Changing Banner Success !! " | lolcat -a
