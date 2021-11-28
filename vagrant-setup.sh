#!/bin/bash

declare -A REPO=(
	# ISO subor s VBoxLinuxAdditions, ktory je urceny pre virtualny system.
	['VBOX_ISO']='VBoxGuestAdditions_6.1.26.iso'
	# Verejny kluc, ktory vagrant vyzaduje, aby sa mohol autentifikovat bez hesla.
	['VAGRANT_PUBKEY']='vagrant.pkey'
)

###################
## Kod aplikacie ##
###################

declare -A VAGRANT=(
	# Pouzivatelske meno, ktore vagrant vyzaduje pre prihlasenie.
	['USER']="vagrant"
	# Pouzivatelska skupina, do ktorej bude pouzivatel vagrant zaradeny.
	['GROUP']="vagrant"
	# Pouzivatelske heslo, ktore vagrant odporuca, aby bolo verejne zname.
	['PASSWORD']="vagrant"
	# Zdielany priecinok, ktory bude medzi virtualnym a hostitelskym systemom.
	['SHARE']="/vagrant"
	# Domovsky priecinok, ktore bude mat pouzivatel vagrant.
	['HOME']="/home/vagrant"
	# Priecinok, v ktorom bude Openssh server hladat verejny kluc pouzivatela.
	['PUBKEY_DIR']="/home/vagrant/.ssh"
	# Subor, v ktorom bude Openssh server hladat verejny kluc pouzivatela.
	['PUBKEY_FILE']="/home/vagrant/.ssh/authorized_keys"
)
declare -A SSHD=(
	# Konfiguracny subor pre Openssh server.
	['CONFIG']="/etc/ssh/sshd_config"
)
declare -A SSHD_CONFIG=(
	# Povolenie autentifikacie zadanim pouzivatelskeho mena a hesla.
	['PasswordAuthentication']="yes"
	# Povolenie autentifikacie pomocou verejneho kluca pouzivatela.
	['PubkeyAuthentication']="yes"
	# Zakazanie prekladu IP adries na domenove mena pocas prihlasovania kvoli rychlosti.
	['UseDNS']="no"
	# Povolenie prihlasenia pouzivatelovi root. Neplati pre distribuciu Ubuntu.
	['PermitRootLogin']="yes"
)
declare -A VBOX=(
	# Priecinok, do ktoreho sa pripoji ISO obraz s VBoxLinuxAdditions.
	['MOUNT']="/media/vbox"
	# Cesta k embedded instalatoru resp. instalovatelnemu archivu VBoxLinuxAdditions.
	['INSTALLER_BIN']="/media/vbox/VBoxLinuxAdditions.run"
	# Priecinok, do ktoreho sa extrahuju instalacne subory VBoxLinuxAdditions.
	['INSTALLER_DIR']="/opt/VBoxGuestAdditions"
	# Cesta uz k extrahovanemu instalatoru VBoxLinuxAdditions.
	['INSTALLER_EXE']="/opt/VBoxGuestAdditions/install.sh"
)
declare -A SUDO=(
	# Konfiguracny subor sudo.
	['CONFIG']="/etc/sudoers"
	# Konfiguracny subor sudo na povolenie spustania root prikazov pre vagrant bez hesla.
	['DROPIN_FILE']="/etc/sudoers.d/vagrant"
)

###############

if [ "$(whoami)" != 'root' ]; then
	echo "Pre spustenie su potrebne root opravnenia."
	exit 1
fi
declare -a PROG_CHECK=(
	"date" "dirname" "realpath" "getent" "cut" "grep" "ip" "groupadd" "useradd"
	"chpasswd" "install" "find" "mkdir" "mount" "umount" "sed" "lsmod" "readlink" "basename"
)
for PROG_NAME in "${PROG_CHECK[@]}"; do
	PROG_PATH=$(which $PROG_NAME 2>/dev/null)
	if [ ! -x "$PROG_PATH" ]; then
		echo "Nie je nainstalovany program $PROG_NAME."
		exit 1
	fi
done

###############

declare -A DIST=(
	# Nazov distribucie.
	['NAME']=""
	# Verzia distribucie.
	['VERSION']=""
	# Format, ktory maju softverove baliky v distribucii.
	['PKG_FORMAT']=""
	# Cesta k programu, ktory sa pouziva v distribucii na spravu balikov.
	['PKG_MANAGER']=""
	# Nazov sietoveho rozhrania, ktore je v distribucii urcene pre Vagrant.
	['IFNAME']=""
)
function vagrant_iface()
{
	local IF_NAME=""
	local IF_LIST="$(ip link show |grep -o -P '^[1-9]+\:\s\K[a-z0-9]+(?=\:)' 2>/dev/null)"
	declare -a IF_FILTERED
	for IF_NAME in $IF_LIST; do
		if [[ "$IF_NAME" =~ enp*s*|eth* ]]; then
			IF_FILTERED=("${IF_FILTERED[@]}" "$IF_NAME")
		fi
	done
	if [ ${#IF_FILTERED[@]} -ge 1 ]; then
		echo "${IF_FILTERED[0]}"
		return 0
	else
		echo ""
		return 1
	fi
}
function DISTDETECT_debian()
{
	local DIST_FILE="/etc/debian_version"
	if [ ! -f "$DIST_FILE" ]; then
		return 1
	else
		local VER="$(grep -P -o '[0-9]+((\.[0-9]+)?)+' $DIST_FILE 2>/dev/null)"
		if [ -z "$VER" ]; then
			return 1
		fi
	fi
	DIST['NAME']='debian'
	DIST['VERSION']="$VER"
	return 0
}
function DISTCONFIG_debian()
{
	DIST['PKG_FORMAT']="deb"
	DIST['PKG_MANAGER']="$(which dpkg 2>/dev/null)"
	if [ ! -x "${DIST[PKG_MANAGER]}" ]; then
		return 1
	fi
	DIST['IFNAME']="$(vagrant_iface)"
	if [ -z "${DIST[IFNAME]}" ]; then
		return 1
	fi
	return 0
}
function DISTDETECT_ubuntu()
{
	local DIST_FILE1="/etc/debian_version"
	if [ ! -f "$DIST_FILE1" ]; then
		return 1
	else
		local VER1="$(grep -P -o '[a-z]+\/[a-z]+' $DIST_FILE1 2>/dev/null)"
		if [ -z "$VER1" ]; then
			return 1
		fi
	fi
	local DIST_FILE2="/etc/lsb-release"
	if [ ! -f "$DIST_FILE2" ]; then
		return 1
	else
		local VER2="$(grep -P 'DISTRIB_DESCRIPTION=\"Ubuntu' $DIST_FILE2 )"
		if [ -z "$VER2" ]; then
			return 1
		fi
		VER2="$(echo $VER2 |grep -P -o '[0-9]+((\.[0-9]+)?)+(\sLTS)?' 2>/dev/null)"
		VER2="$(echo $VER2 |tr ' ' '-' |tr '[:upper:]' '[:lower:]')"
		if [ -z "$VER2" ]; then
			return 1
		fi
	fi
	DIST['NAME']='ubuntu'
	DIST['VERSION']="$VER2"
	return 0
}
function DISTCONFIG_ubuntu()
{
	DISTCONFIG_debian
	return $?
}
function DISTDETECT_centos()
{
	local DIST_FILE="/etc/centos-release"
	if [ ! -f "$DIST_FILE" ]; then
		DIST_FILE="/etc/redhat-release"
	fi
	if [ ! -f "$DIST_FILE" ]; then
		return 1
	else
		local VER="$(grep 'CentOS Linux release' $DIST_FILE 2>/dev/null)"
		if [ -z "$VER" ]; then
			VER="$(grep 'CentOS release' $DIST_FILE 2>/dev/null)"
		fi
		if [ -z "$VER" ]; then
			return 1
		fi
		VER="$(echo $VER |grep -P -o '[0-9]+((\.[0-9]+)?)+' 2>/dev/null)"
		if [ -z "$VER" ]; then
			return 1
		fi
	fi
	DIST['NAME']='centos'
	DIST['VERSION']="$VER"
	return 0
}
function DISTCONFIG_centos()
{
	DIST['PKG_FORMAT']="rpm"
	DIST['PKG_MANAGER']="$(which rpm 2>/dev/null)"
	if [ ! -x "${DIST[PKG_MANAGER]}" ]; then
		return 1
	fi
	DIST['IFNAME']="$(vagrant_iface)"
	if [ -z "${DIST[IFNAME]}" ]; then
		return 1
	fi
	return 0
}
function dist_support()
{
	local DIST_SUPPORT
	DIST_SUPPORT="$(set)"
	DIST_SUPPORT="$(echo $DIST_SUPPORT)"
	DIST_SUPPORT="$(echo $DIST_SUPPORT |grep -P -o 'DISTDETECT_[a-z]+\s\(\)' 2>/dev/null)"
	DIST_SUPPORT="$(echo $DIST_SUPPORT |grep -P -o '[a-z]+' 2>/dev/null)"
	echo "$DIST_SUPPORT"
	return 0
}
for DIST_NAME in $(dist_support); do
	DISTDETECT_$DIST_NAME
	if [ $? -eq 0 ]; then
		break
	fi
done
if [ -z "${DIST[NAME]}" ] || [ -z "${DIST[VERSION]}" ]; then
	echo "Nie je mozne identifikovat distribuciu a jej verziu."
	exit 1
fi
DISTCONFIG_${DIST[NAME]}
if [ $? -ne 0 ]; then
	echo "Nie je mozne nastavit specifika pre distribuciu ${DIST[NAME]}."
	exit 1
fi

###############

if [ -n "$1" ]; then
	REPO['VBOX_ISO']="$1"
fi
WORK_DIRECTORY="$(dirname $0)"
REPO_DIRECTORY="$(realpath $WORK_DIRECTORY/repo)"
for REPO_ITEM in "${!REPO[@]}"; do
	REPO_FILE="$(realpath $REPO_DIRECTORY/${REPO[$REPO_ITEM]})"
	if [ ! -f "$REPO_FILE" ]; then
		echo "Subor $REPO_FILE sa v repozitari nenachadza."
		exit 1
	fi
	REPO[$REPO_ITEM]="$REPO_FILE"
done
REPO['PACKAGES']="$REPO_DIRECTORY/packages/${DIST[NAME]}-${DIST[VERSION]}"
REPO['IFCONFIG']="$REPO_DIRECTORY/ifconfig/${DIST[NAME]}-${DIST[VERSION]}"
for REPO_ITEM in "PACKAGES" "IFCONFIG"; do
	if [ ! -d "${REPO[PACKAGES]}" ]; then
		echo "Priecinok ${REPO[PACKAGES]} sa v repozitari nenachadza."
		exit 1
	fi
done
REPO['IFCONFIG_TPL']="${REPO[IFCONFIG]}/ifconfig.tpl"
REPO['IFCONFIG_DPL']="${REPO[IFCONFIG]}/ifconfig.deploy"
for REPO_ITEM in "IFCONFIG_TPL" "IFCONFIG_DPL"; do
	if [ ! -f "${REPO[$REPO_ITEM]}" ]; then
		echo "Subor ${REPO[$REPO_ITEM]} sa nenachadza v repozitari."
		exit 1
	fi
done
declare -a CONF_CHECK=(
	"REPO" "VAGRANT" "SSHD" "SSHD_CONFIG" "VBOX" "SUDO"
)
for CONF in "${CONF_CHECK[@]}"; do
	if [[ "$(declare -p $CONF 2>/dev/null)" != "declare -A $CONF"* ]]; then
		echo "Skupina s konfiguraciou $CONF neexistuje."
		exit 1
	fi
	for CONF_NAME in $(eval echo \${!${CONF}[@]}); do
		CONF_VALUE="$(eval echo \${$CONF[$CONF_NAME]})"
		if [ -z "$CONF_VALUE" ]; then
			echo "Konfiguracia $CONF[$CONF_NAME] ma prazdnu hodnotu."
			exit 1
		fi
	done
done

###############

function package_install()
{
	declare -a PKG_LIST
	declare -A PKG_ORDER
	readarray -t PKG_LIST < <(find ${REPO[PACKAGES]} -name *.${DIST[PKG_FORMAT]} -type f 2>/dev/null)
	if [ ${#PKG_LIST[@]} -eq 0 ]; then
		ERRMSG="Priecinok ${REPO[PACKAGES]} neobsahuje ziadne baliky."
		return 1
	fi
	local PKG_FILE; local PKG_STAGE;
	for PKG_FILE in "${PKG_LIST[@]}"; do
		PKG_STAGE="$(echo $PKG_FILE |grep -P -o 'stage[0-9]+' 2>/dev/null)"
		if [ -z "$PKG_STAGE" ]; then
			PKG_STAGE="unordered"
		fi
		if [ -z "${PKG_ORDER[$PKG_STAGE]}" ]; then
			PKG_ORDER[$PKG_STAGE]="$PKG_FILE"
		else
			PKG_ORDER[$PKG_STAGE]="${PKG_ORDER[$PKG_STAGE]} $PKG_FILE"
		fi
	done
	for PKG_STAGE in `echo ${!PKG_ORDER[@]} |tr ' ' '\n' |sort -n`; do
		${DIST['PKG_MANAGER']} --install ${PKG_ORDER[$PKG_STAGE]}
		if [ $? -ne 0 ]; then
			ERRMSG="Pri instalacii balikov pomocou ${DIST[PKG_MANAGER]} vznikol problem."
			return 1
		fi
	done
	return 0
}
function ifconfig_deploy()
{
	declare -a DEPLOY_FILE
	declare -A DEPLOY=(
		# Cesta k suboru s konfiguraciou sietoveho rozhrania.
		['PATH']=""
		# Premenna ci sa ma vytvorit rodicovsky priecinok ak neexistuje.
		['MKDIR']=""
	)
	readarray DEPLOY_FILE < <(cat ${REPO[IFCONFIG_DPL]} 2>/dev/null)
	if [ ${#DEPLOY_FILE[@]} -le 0 ]; then
		ERRMSG="Subor ${REPO[IFCONFIG_DPL]} neobsahuje ziadne data."
		return 1
	fi
	local LINE; local KEY; local VAL;
	for LINE in "${DEPLOY_FILE[@]}"; do
		KEY="$(echo $LINE |tr -d '[:space:]' |cut -d ':' -f 1)"
		VAL="$(echo $LINE |tr -d '[:space:]' |cut -d ':' -f 2)"
		if [ ${DEPLOY[$KEY]+exists} ]; then
			DEPLOY[$KEY]="$VAL"
		fi
	done
	for KEY in "${!DEPLOY[@]}"; do
		if [ -z "${DEPLOY[$KEY]}" ]; then
			ERRMSG="Nekorektne instrukcie pre nasadenie konfiguracie sietoveho rozhrania."
			return 1
		fi
	done
	DEPLOY[PATH]=$(echo ${DEPLOY[PATH]} |sed -e "s/__IFNAME__/${DIST[IFNAME]}/" 2>/dev/null)
	grep "$(basename $0)" ${DEPLOY[PATH]} 2>/dev/null 1>&2
	if [ $? -eq 0 ]; then
		return 2
	fi
	local DIR="$(dirname ${DEPLOY[PATH]})"
	if [ ! -d "$DIR" ]; then
		if [ "${DEPLOY[MKDIR]}" == "yes" ]; then
			mkdir -p $DIR
			if [ $? -ne 0 ]; then
				ERRMSG="Pri vytvarani priecinka $DIR nastala chyba."
				return 1
			fi
		else
			ERRMSG="Priecinok $DIR pre sablonu neexistuje a nebude ani vytvoreny?"
			return 1
		fi
	fi
	install -g root -o root -m 600 \
		-T ${REPO[IFCONFIG_TPL]} ${DEPLOY[PATH]} 2>/dev/null 1>&2
	if [ $? -ne 0 ]; then
		ERRMSG="Pri kopirovani sablony ${REPO[IFCONFIG_TPL]} vznikla chyba."
		return 1
	fi
	sed -i -r \
		-e "1i# vytvoril $(basename $0)" \
		-e "s/__IFNAME__/${DIST[IFNAME]}/" ${DEPLOY[PATH]} 2>/dev/null
	if [ $? -ne 0 ]; then
		ERRMSG="Pri uprave ${DEPLOY[PATH]} nastala chyba."
		return 1
	fi
	return 0
}
function sshd_config()
{
	if [ ! -f "${SSHD[CONFIG]}" ]; then
		ERRMSG="Konfiguracny subor ${SSHD[CONFIG]} neexistuje. Je nainstalovany balik?"
		return 1
	fi
	local CHR=""
	local OPT=""
	local OPT_VALUE="[a-zA-Z0-9\/\.\:\-]+"
	local NEW_VALUE=""
	for OPT in "${!SSHD_CONFIG[@]}"; do
		case "$OPT" in
			"PermitRootLogin")
			if [ "${DIST[NAME]}" == "ubuntu" ]; then break; fi
			;;
		esac
		grep -P -o "^$OPT\s+$OPT_VALUE" ${SSHD[CONFIG]} 2>/dev/null 1>&2
		case "$?" in
			0) CHR="" ;;
			1) CHR="#" ;;
		esac
		NEW_VALUE=${SSHD_CONFIG[$OPT]}
		sed -r -i -e "s/^$CHR$OPT\s+$OPT_VALUE/$OPT $NEW_VALUE/" ${SSHD[CONFIG]} 2>/dev/null
		if [ $? -ne 0 ]; then
			ERRMSG="Pri zmene nastavenia $OPT v ${SSHD[CONFIG]} nastala chyba."
			return 1
		fi
	done
	return 0
}
function sudo_requiretty()
{
	if [ ! -f "${SUDO[CONFIG]}" ]; then
		ERRMSG="Konfiguracny subor ${SUDO[CONFIG]} neexistuje. Je nainstalovany balik?"
		return 1
	fi
	local SEARCH='^[^#]*\s*Defaults\s*[\:\!]*\s*[a-zA-Z0-9]*\s+requiretty'
	grep -P -o $SEARCH ${SUDO[CONFIG]} 2>/dev/null 1>&2
	if [ $? -ne 1 ]; then
		ERRMSG="V subore ${SUDO[CONFIG]} sa nachadza nastavenie requiretty."
		return 1
	fi
	return 0
}
function iso_mount()
{
	if [ -z "$1" ] || [ -z "$2" ]; then
		return 1
	fi
	local MOUNT="$2"
	if [ -h "$MOUNT]" ]; then
		MOUNT="$(readlink $MOUNT)"
	fi
	if [ ! -d "$MOUNT" ]; then
		mkdir -p $MOUNT 2>/dev/null 1>&2
		if [ $? -ne 0 ]; then
			return 1
		fi
	fi
	mount -o loop $1 $2 2>/dev/null 1>&2
	local RET=$?
	if [ $RET -ne 0 ] && [ $RET -ne 1 ]; then
		return 1
	fi
	return 0
}
function iso_umount()
{
	if [ -z "$1" ]; then
		return 1
	fi
	umount $1 2>/dev/null 1>&2
	local RET=$?
	if [ $RET -ne 0 ]; then
		return 1
	fi
	return 0
}
function vbox_extract()
{
	local FORCE=0
	if [ -n "$1" ]; then
		if [ "$1" == "force" ]; then FORCE=1; fi
	fi
	if [ $FORCE -eq 0 ]; then
		if [ -x "${VBOX[INSTALLER_EXE]}" ]; then
			return 2
		fi
	fi
	iso_mount "${REPO[VBOX_ISO]}" "${VBOX[MOUNT]}"
	if [ $? -ne 0 ]; then
		ERRMSG="Pripojenie ISO obrazu ${REPO[VBOX_ISO]} do ${VBOX[MOUNT]} zlyhalo."
		return 1
	else
		${VBOX[INSTALLER_BIN]} --noexec --target ${VBOX[INSTALLER_DIR]}
		if [ $? -ne 0 ]; then
			ERRMSG="Extrakcia VBOX softveru do ${VBOX[INSTALLER_DIR]} zlyhala."
			return 1
		fi
		iso_umount "${VBOX[MOUNT]}"
		if [ $? -ne 0 ]; then
			ERRMSG="Odpojenie ISO obrazu z ${VBOX[MOUNT]} zlyhalo."
			return 1
		fi
	fi
	return 0
}
function vbox_install()
{
	local FORCE=0
	if [ -n "$1" ]; then
		if [ "$1" == "force" ]; then FORCE=1; fi
	fi
	local KMODULE="$(lsmod |grep vboxguest 2>/dev/null)"
	if [ $FORCE -eq 0 ]; then
		if [ -n "$KMODULE" ]; then
			return 2
		fi
	fi
	# Instalator vola jednotlive funkcie, ktore obsahuje relativne. Musime byt preto
	# v instalacnom priecinku, kde sa nachadzaju extrahovane VBoxLinuxAdditions.
	cd ${VBOX[INSTALLER_DIR]} 2>/dev/null 1>&2
	if [ $? -ne 0 ]; then
		ERRMSG="Zmena pracovneho priecinka do ${VBOX[INSTALLER_DIR]} zlyhala."
		return 1
	else
		${VBOX[INSTALLER_EXE]} install --force
		local RET=$?
		if [ $RET -ne 0 ] ; then
			# Ak pouzivatel vboxadd uz v passwd existuje vracia navratovy kod 2.
			# V pripade force rezimu potlacime toto spravanie.
			if [ $RET -eq 2 ] && [ $FORCE -eq 1 ]; then
				return 0
			fi
			ERRMSG="Instalacia VBOX softveru z ${VBOX[INSTALLER_DIR]} zlyhala."
			return 1
		fi
	fi
	return 0
}
function vagrant_group()
{
	getent group ${VAGRANT[GROUP]} 2>/dev/null 1>&2
	if [ $? -eq 0 ]; then
		return 2
	else
		groupadd ${VAGRANT[GROUP]} 2>/dev/null 1>&2
		if [ $? -ne 0 ]; then
			ERRMSG="Vytvorenie pouzivatelskej skupiny ${VAGRANT[GROUP]} zlyhalo."
			return 1
		fi
	fi
	return 0
}
function vagrant_user()
{
	getent passwd ${VAGRANT[USER]} 2>/dev/null 1>&2
	if [ $? -eq 0 ]; then
		return 2
	else
		useradd -g ${VAGRANT[GROUP]} -s /bin/bash -d ${VAGRANT[HOME]} -m \
			-c ${VAGRANT[USER]} ${VAGRANT[USER]} 2>/dev/null 1>&2
		if [ $? -ne 0 ]; then
			ERRMSG="Vytvorenie pouzivatelskeho uctu ${VAGRANT[USER]} zlyhalo."
			return 1
		fi
		echo ${VAGRANT[USER]}:${VAGRANT[PASSWORD]} |chpasswd 2>/dev/null 1>&2
		if [ $? -ne 0 ]; then
			ERRMSG="Nastavenie hesla pre pouzivatelsky ucet ${VAGRANT[USER]} zlyhalo."
			return 1
		fi
	fi
	return 0
}
function vagrant_share()
{
	if [ -d "${VAGRANT[SHARE]}" ]; then
		return 2
	else
		install -g ${VAGRANT[GROUP]} -o ${VAGRANT[USER]} -m 0755 \
			-d ${VAGRANT[SHARE]} 2>/dev/null 1>&2
		if [ $? -ne 0 ]; then
			ERRMSG="Vytvorenie zdielaneho priecinka ${VAGRANT[SHARE]} zlyhalo."
			return 1
		fi
	fi
	return 0
}
function vagrant_pubkey()
{
	if [ ! -d "${VAGRANT[PUBKEY_DIR]}" ]; then
		install -g ${VAGRANT[GROUP]} -o ${VAGRANT[USER]} -m 0700 \
			-d ${VAGRANT[PUBKEY_DIR]} 2>/dev/null 1>&2
		if [ $? -ne 0 ]; then
			ERRMSG="Vytvorenie priecinka ${VAGRANT[PUBKEY_DIR]} pre verejny kluc zlyhalo."
			return 1
		fi
	fi
	if [ -f "${VAGRANT[PUBKEY_FILE]}" ]; then
		return 2
	else
		install -g ${VAGRANT[GROUP]} -o ${VAGRANT[USER]} -m 0600 \
			-T ${REPO[VAGRANT_PUBKEY]} ${VAGRANT[PUBKEY_FILE]} 2>/dev/null 1>&2
		if [ $? -ne 0 ]; then
			ERRMSG="Kopirovanie ${REPO[VAGRANT_PUBKEY]} do ${VAGRANT[PUBKEY_DIR]} zlyhalo."
			return 1
		fi
	fi
	return 0
}
function vagrant_sudo()
{
	if [ -f "${SUDO[DROPIN_FILE]}" ]; then
		return 2
	else
		local LINE="${VAGRANT[USER]} ALL=(ALL) NOPASSWD: ALL"
		echo $LINE > ${SUDO[DROPIN_FILE]} 2>/dev/null
		if [ $? -ne 0 ]; then
			ERRMSG="Vytvorenie suboru ${SUDO[DROPIN_FILE]} zlyhalo."
			return 1
		fi
		chown root:root ${SUDO[DROPIN_FILE]} 2>/dev/null 1>&2
		if [ $? -ne 0 ]; then
			ERRMSG="Nastavenie vlastnika pre ${SUDO[DROPIN_FILE]} zlyhalo."
			return 1
		fi
		chmod 0440 ${SUDO[DROPIN_FILE]} 2>/dev/null 1>&2
		if [ $? -ne 0 ]; then
			ERRMSG="Nastavenie opravneni pre ${SUDO[DROPIN_FILE]} zlyhalo."
			return 1
		fi
	fi
	return 0
}
function root_password()
{
	case "${DIST[NAME]}" in
		"ubuntu") return 3 ;;
		*) ;;
	esac
	getent shadow root 2>/dev/null 1>&2
	if [ $? -eq 0 ]; then
		echo root:${VAGRANT[PASSWORD]} |chpasswd 2>/dev/null 1>&2
		if [ $? -ne 0 ]; then
			ERRMSG="Nastavenie rootovskeho hesla na ${VAGRANT[PASSWORD]} zlyhalo."
			return 1
		fi
	fi
	return 0
}

###############

SETUP_ANSWER=""
function print_question()
{
	while : ; do
		echo -n "   "
		echo -n "$1 [y/n] "
		read SETUP_ANSWER
		if [[ "$SETUP_ANSWER" =~ [yY] ]]; then
			SETUP_ANSWER="y"
			break
		fi
		if [[ "$SETUP_ANSWER" =~ [nN] ]]; then
			SETUP_ANSWER="n"
			break
		fi
	done
}
echo "************************************************"
echo "** Nastavenie operacneho systemu pre VAGRANT! **"
echo "************************************************"
echo "** Distribucia: ${DIST[NAME]}-${DIST[VERSION]}"
echo "** Vbox: $(basename ${REPO[VBOX_ISO]})"
echo "** Cas: $(date +'%Y-%m-%d %H:%M:%S')"
echo "************************************************"
print_question "Prajete si spustit tento proces?"
if [ "$SETUP_ANSWER" == "n" ]; then
	exit 0
fi
echo "************************************************"

SETUP_TIME="no"
function print_header()
{
	if [ -n "$1" ]; then
		echo ""
		echo "*** ""$1"
		if [ "$SETUP_TIME" == "yes" ]; then
			echo "*** ""$(date +"%H:%M:%S.%N")"
		fi
	fi
}
function print_result()
{
	if [ -n "$1" ]; then
		local STEP_RESULT;
		case "$1" in
			0) STEP_RESULT="OK" ;;
			1) STEP_RESULT="CHYBA" ;;
			2) STEP_RESULT="EXISTUJE" ;;
			3) STEP_RESULT="PRESKOCENE" ;;
			*) STEP_RESULT="???" ;;
		esac
		if [ "$SETUP_TIME" == "yes" ]; then
			echo "*** ""$(date +"%H:%M:%S.%N")"
		fi
		echo "*** ""Stav: ""[ $STEP_RESULT ]"
	fi
}
function print_step()
{
	local STEP_NAME=""
	local STEP_TIME="no"; SETUP_TIME="no"
	case "$1" in
		'package_install')
		STEP_NAME="Instalovanie balikov z ${REPO[PACKAGES]}"
		STEP_TIME="yes"
		;;
		'vbox_extract')
		STEP_NAME="Extrahovanie VBOX softveru z $(basename ${REPO[VBOX_ISO]})"
		STEP_TIME="yes"
		;;
		'vbox_install')
		STEP_NAME="Instalovanie VBOX softveru z ${VBOX[INSTALLER_DIR]}"
		STEP_TIME="yes"
		;;
	##########
		'ifconfig_deploy')
		STEP_NAME="Nastavovanie sietoveho rozhrania ${DIST[IFNAME]}" ;;
		'sshd_config')
		STEP_NAME="Upravovanie konfiguracneho suboru ${SSHD[CONFIG]}" ;;
		'sudo_requiretty')
		STEP_NAME="Kontrolovanie ${SUDO[CONFIG]} na pritomnost requiretty" ;;
	##########
		'vagrant_group')
		STEP_NAME="Vytvaranie pouzivatelskej skupiny ${VAGRANT[GROUP]}" ;;
		'vagrant_user')
		STEP_NAME="Vytvaranie pouzivatelskeho uctu ${VAGRANT[USER]}" ;;
		'vagrant_share')
		STEP_NAME="Vytvaranie zdielaneho priecinka ${VAGRANT[SHARE]}" ;;
		'vagrant_pubkey')
		STEP_NAME="Nasadzovanie verejneho kluca $(basename ${REPO[VAGRANT_PUBKEY]})" ;;
		'vagrant_sudo')
		STEP_NAME="Povolovanie root prikazov v ${SUDO[DROPIN_FILE]}" ;;
	##########
	'root_password')
		STEP_NAME="Nastavovanie rootovskeho hesla na ${VAGRANT[PASSWORD]}" ;;
	##########
		*)
		STEP_NAME="???" ;;
	esac
	if [ "$STEP_TIME" == "yes" ]; then
		SETUP_TIME="yes"
	fi
	print_header "$STEP_NAME"
}

declare -a SETUP_ORDER=(
	'package_install' 'vbox_extract' 'vbox_install'
	'ifconfig_deploy' 'sshd_config' 'sudo_requiretty'
	'vagrant_group' 'vagrant_user' 'vagrant_share' 'vagrant_pubkey' 'vagrant_sudo'
	'root_password'
)
for STEP in "${SETUP_ORDER[@]}"; do
	print_step "$STEP"
	$STEP
	RET=$?
	print_result "$RET"
	if [ $RET -eq 2 ]; then
		case "$STEP" in
			'vbox_extract') ;;
			'vbox_install') ;;
			*) continue ;;
		esac
		print_question " ""Prajete si vynutit tento krok?"
		if [ "$SETUP_ANSWER" == "n" ]; then
			continue
		fi
		print_step "$STEP"
		$STEP "force"
		RET=$?
		print_result "$RET"
	fi
	if [ $RET -eq 1 ]; then
		echo "    ""$ERRMSG"
		print_question " ""Prajete si preskocit tento krok?"
		if [ "$SETUP_ANSWER" == "n" ]; then
			exit 1
		fi
	fi
done
exit 0
