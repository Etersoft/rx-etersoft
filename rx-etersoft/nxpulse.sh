. nxpulsefuncs

COMMAND_PA=pulseaudio
COMMAND_PACTL=pactl
#PA_CONF="$USER_FAKE_HOME/.nx/C-$sess_id/pulse"
PA_CONF=""
AGENT_STARTUP_TIMEOUT=15
#
# -----------------------------------------------------------------------------
# Node functions module
# -----------------------------------------------------------------------------
#

sess_lport_name() {
#arg: <svc_type>
	case $1 in
	smb-share|smb-prn) echo "smbport";;
	ipp-prn)	echo "cupsport";;
	media-pa)	echo "mmport";;
	esac
}

norm_dir() {
#args: <share_dir> [parent_dir]
# exclude potential parts to exec and set dir path from given parent_dir
	local r=${1//\`/}; r=${r//\$[(\{]*[)\}]/$2}; r=${r/\.\.\//$2\/};
	r=${r/\.\//$2\/}; r=${r/\~\//$2\/}
	[[ "${r:0:1}" =~ [[:alnum:]] ]] && r="$2/$r"
	echo "$r"
}

uservice_mounted() {
#args: <type> <service/sharename/mountpoint> [port]
	local rc=0 txt="" pattern  port=""
	local patt_addr="127.0.0.1"; [ -n "$4" ] && patt_addr=$4
	case $1 in
	smb-share)
		# output of mount cmd not contains mount.cifs port option value
		# because we need to port arg ($3)
		txt=$(env LC_ALL=C $COMMAND_MOUNT_LIST 2>/dev/null)
		if stringinstring "//" "$2"; then pattern="($2)"
		elif ! stringinstring "/" "$2"; then pattern="//$patt_addr/($2)"
		else pattern="($2)"
		fi
		[ -n "$(rematchfn "$pattern" "$txt")" ] || return 1
		if [ -n "$3" ]; then
			 port_is_listening $3 || rc=1
		fi
	;;
	smb-prn|ipp-prn)
		txt=$(env LC_ALL=C $COMMAND_LPSTAT -v 2>/dev/null)
		pattern=".*$2.*//$patt_addr:("
		[ -n "$3" ] && pattern+="$3)" || pattern+="$num_pattern)"
		port=$(rematchfn "$pattern" "$txt"); rc=$?
		[ -n "$port" ] || return $rc
		port_is_listening "$port" || rc=1
	;;
	media-pa)
		case $2 in
		pa) # tunneled pa
			#$COMMAND_PA --check || return 1
			txt=$(env LC_ALL=C $COMMAND_PACTL list short 2>/dev/null)
			pattern="server=$patt_addr:("
			[ -n "$3" ] && pattern+="$3)" || pattern+="[0-9]+)"
			port=$(rematchfn "$pattern" "$txt"); rc=$?
			#nxlog "$1 port=$port" #debug
			[ -n "$port" ] || return $rc
			port_is_listening "$port" || rc=1
		;;
		esac
	;;
	esac
	return $rc
}

uservice_configure() {
#args:
# smb-share <svc> <port> <username> <password> <dir> <computername>
# 		*-prn <svc> <port> <username> <password> <opts> <computername> <share>
#				opts="model=;public=;defaultprinter="
# media-pa	<svc> <port> <""> <""> <opts>
	#local lp="$FUNCNAME ($$/$BASHPID):";
	local lp="$FUNCNAME ($$):";
	local cmdstr optstr comp rc=0 txt errstr uri
	case $1 in
	smb-share)
		# create/check mountpoint
		mkdir -p "$6" &>/dev/null
		[ -d "$6" ] || { nxlog "$lp unable to create dir='$6'"; return 1; }
		local egroup=$(id -gn "$USER") tmpopts=${SMB_MOUNT_OPTIONS//,/&}
		local dir_mode=$(getparam "$tmpopts" dir_mode)
		dir_mode=${dir_mode:(-3)}; [ -n "$dir_mode" ] || dir_mode="700"
		[ "$(stat -c %a "$6")" != "$dir_mode" ] && chown "0$dir_mode" "$6" &>/dev/null
		# mount options string
		optstr="uid=$USER,gid=$egroup,ip=127.0.0.1,port=$3,username=$4"
		[ -n "$5" ] && optstr+=",password=$5"
		[ -n "$SMB_MOUNT_OPTIONS" ] && optstr+=",$SMB_MOUNT_OPTIONS"
		cmdstr="$COMMAND_SUDO $COMMAND_SMBMOUNT $2 $6 -o $optstr"
		echo "$cmdstr"
	;;
	smb-prn|ipp-prn)
		local model=$(getparam "$6" "model" "" ';')
		[ "$model" = "NULL" ] && model=""
		local ppdn=${2#$USER}; ppdn=${ppdn:1}; ppdn=${ppdn%#[0-9]*}
		local ppdfn="$NX_PPD_DIR/$ppdn.ppd"
		[ -r "$ppdfn" ] || { # ppd is not found, search for driver in CUPS
			txt=$($COMMAND_LPINFO -m 2>/dev/null)
			local str drv=""
			[ -n "$model" ] && {
				while read str; do
					[[ "$str" =~ "$model" ]] && { drv="${str%% *}"; break; }
				done <<< "$txt"
			}
			[ -n "$drv" ] || {
				while read str; do
					[[ "$str" =~ "$ppdn" ]] && { drv="${str%% *}"; break; }
				done <<< "$txt"
			}
			[ -n "$drv" ] || {
				nxlog "$lp '$svc'; CUPS driver for service is not found";
				return 1; }
			$COMMAND_PPDCAT cat "$drv" > "$ppdfn" || {
				nxlog "$lp Can't save $ppdfn"; return 1; }
		}
		[ "${1:0:3}" = "smb" ] && \
			uri="nxsmb://$4:$5@127.0.0.1:$3/cifs/$8" || \
			uri="ipp://$4:$5@127.0.0.1:$3/printers/$8"
		cmdstr="$COMMAND_SUDO $COMMAND_LPADMIN -p $svc -P $ppdfn -v $uri -E"
		echo "$cmdstr"
	;;
	media-pa)
		case $2 in
		pa) # tunneled pa
			local uri="127.0.0.1:$3"
			# get sink and source from remote pa
			local rmods=$(env LC_ALL=C $COMMAND_PACTL -s $uri list short 2>/dev/null)
			[ -n "$rmods" ] || {
				nxlog "$lp '$svc'; can't get module list from remote PA ($uri)";
				return 1; }
			local rsink=$(rematchfn "(ts_receiver)" "$rmods") #"
			local rsource=$(rematchfn "(ts_sender.monitor)" "$rmods") #"
			[ -n "$rsink" -a -n "$rsource" ] || {
				local rinfo=$(env LC_ALL=C $COMMAND_PACTL -s $uri info 2>/dev/null)
				[ -n "$rsink" ] || \
					rsink=$(rematchfn "Default Sink:[[:blank:]]+(.+)" "$rinfo") #"
				[ -n "$rsource" ] || \
					rsource=$(rematchfn "Default Source:[[:blank:]]+(.+)" "$rinfo") #"
			}
			echo "$rsink $rsource"
		;;
		esac
	;;
	esac
	return $rc
}

uservice_mount() {
#args:
# smb-share <svc> <port> <username> <password> <dir> <computername>
# *-prn <svc> <port> <username> <password> <opts> <computername> <share>
# media-pa <svc> <port> "" "" <mode> <computername>
	local lp="$FUNCNAME ($$):" rc=0 cmdstr errstr
	local i ok="" step=0.25 timeo=28 #7sec
	for (( i=0; i<=timeo; i++ )); do
		port_is_listening $3 && { ok="1"; break; }
		sleep $step"s"
	done
	[ -n "$ok" ] || \
		 { nxlog "$lp '$svc'; port $3 is not listen after $((timeo/4))s";
		  return 1; }

	cmdstr=$(uservice_configure "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8") || return 1
	case $1 in
	smb-share)
		#nxlog "$lp share cmdstr='$cmdstr'" #debug
		errstr=$($cmdstr 2>&1) || \
			{ nxlog "$lp $2 ($3) share mount failed: $errstr"
				rmdir "$6" &>/dev/null; return 1; }
		nxlog "$lp $2 ($3) share mounted"
	;;
	smb-prn|ipp-prn)
		#nxlog "$lp add printer cmdstr='$cmdstr'" #debug
		errstr=$($cmdstr 2>&1) || \
			{ nxlog "$lp $2 ($3) printer installing failed: $errstr"; return 1; }
		# post-configure
		local public=$(getparam "$6" "public" "" ';')
		[ "$public" != "1" ] && {
		errstr=$($COMMAND_SUDO $COMMAND_LPADMIN -p $svc -u allow:$USER,guest,root 2>&1) || \
			{ nxlog "$lp $2 ($3) printer set permission failed: $errstr"; }
		}
		local defp=$(getparam "$6" "defaultprinter" "" ';')
		[ "$defp" = "1" ] && {
		errstr=$($COMMAND_SUDO $COMMAND_LPADMIN -d $svc 2>&1) || \
			{ nxlog "$lp $2 ($3) printer set to default failed: $errstr"; }
		}
		nxlog "$lp $2 ($3) printer installed"
	;;
	media-pa)
		nxlog "$FUNCNAME ($$): PULSE: setting Pulseadio"
		if  ! $COMMAND_PA --check &>/dev/null; then
			$COMMAND_PA --start --exit-idle-time=-1 &>/dev/null || {
			#--log-target=file:$nx_dir/pa-$3.log --log-level=4 || { #debug
				nxlog "$lp '$svc' can't start local pulseaudio server";
				return 1; }
			# automatic null-sink will be disabled
			# unload unnecessary local modules here too
			local rmmods="module-always-sink module-rescue-streams module-systemd-login \
module-device-restore module-stream-restore module-card-restore \
module-default-device-restore module-switch-on-port-available \
module-udev-detect module-suspend-on-idle module-console-kit"
			local txt=$($COMMAND_PACTL list short 2>/dev/null)
			local midpat="([0-9]+)[[:blank:]]+" mid rmod
			for rmod in $rmmods; do
				mid=$(rematchfn "$midpat$rmod" "$txt") && {
					$COMMAND_PACTL unload-module $mid &>/dev/null
					#nxlog "$lp ! $mid" #debug
				}
			done
		else nxlog "$lp '$svc' local pulseaudio server already started" #debug
		fi
		case $2 in
		pa) # tunneled pa
			nxlog "$FUNCNAME ($$): PULSE: tunneled Pulseadio"
			local rsink=$(cutfn "$cmdstr" 0) rsource=$(cutfn "$cmdstr" 1)
			local mname="module-tunnel-sink" opts="server=127.0.0.1:$3" oo args ok2=""
           local mutemic=$(cutfn "$6" 3 '-')
           oo=$(cutfn "$6" 1 '-'); [ -n "$oo" ] && opts+=" rate=$oo"
			oo=$(cutfn "$6" 2 '-'); [ -n "$oo" ] && opts+=" channels=$oo"
			[ "$oo" = "1" ] && opts+=" channel_map=mono"
			if [ "$rsink" != "(null)" ]; then
				args="sink_name=tcl_out sink=$rsink $opts"
				errstr=$($COMMAND_PACTL load-module $mname $args 2>&1)
				[ $? -eq 0 ] && ok="tcl_out" || \
					nxlog "$FUNCNAME ($$): $2 ($3) can't load $mname $args; '$errstr'"
				[ -n "$ok" ] && $COMMAND_PACTL set-default-sink "tcl_out" &>/dev/null
			else nxlog "$lp $2 ($3) can't load $name with rsink=$rsink"
			fi
			mname="module-tunnel-source"
			if [ "$rsource" != "(null)" ]; then
				args="source_name=tcl_in source=$rsource $opts"
				errstr=$($COMMAND_PACTL load-module $mname $args 2>&1)
				[ $? -eq 0 ] && ok2="tcl_in" || \
					nxlog "$FUNCNAME ($$): $2 ($3) can't load $mname $args; '$errstr'"
				[ -n "$ok2" ] && $COMMAND_PACTL set-default-source "tcl_in" &>/dev/null
				[ -n "$mutemic" ] \
                   && $COMMAND_PACTL set-source-mute "tcl_in" 1 \
                   || $COMMAND_PACTL set-source-mute "tcl_in" 0
			else nxlog "$lp $2 ($3) can't load $name with rsource=$rsource"
			fi
			if [ -n "$ok" -o  -n "$ok2" ]; then 
				nxlog "$lp $2 ($3) tunnel modules loaded: $ok $ok2"
			else rc=1
			fi
		;;
		esac
	;;
	esac
	return $rc
}

uservice_umount() {
#args: <type> <svc/mountpoint> [data] [port]
	local lp="$FUNCNAME ($$/):" errstr=""
	local i ok="" step="0.5" ct=4
	case $1 in
	smb-share)
		local mdir=$3 res ffl=""
		if stringinstring "//" "$2"; then res="$2" # svc
		elif ! stringinstring "/" "$2"; then res="//127.0.0.1/$2" # sharename
		else mdir="$2" res="$2" # dir
		fi
		#[ -z "$mdir" ] && { # get mount dir directly
		#	local txt=$(LC_ALL=C mount 2>/dev/null)
		#	pattern="$res""[[:blank:]]+on[[:blank:]]+([^[:blank:]]+)"
		#	mdir=$(remathfn "$pattern" "$txt")
		#	nxlog "$lp share $res: given empty mount dir, loaded mdir='$mdir' "
		#}
		for (( i=1; i<=ct; i++ )); do
			(( i>=ct/2 )) && ffl="-f"
			errstr+=$($COMMAND_SUDO $COMMAND_SMBUMOUNT $ffl "$res" 2>&1) && \
				{ ok="1"; break; }
			sleep $step"s"
		done
		[ -n "$ok" ] || \
			 { nxlog "$lp $res share umount failed: $errstr"; return 1; }
		[ -n "$mdir" ] && [ -d "$mdir" ] && rmdir "$mdir" &>/dev/null
		nxlog "$lp $res share umounted"
	;;
	smb-prn|ipp-prn)
		for (( i=1; i<=ct; i++ )); do
			errstr+=$($COMMAND_SUDO $COMMAND_LPADMIN -x "$2" 2>&1) && \
				{ ok="1"; break; }
			sleep $step"s"
		done
		[ -n "$ok" ] || \
			 { nxlog "$lp $2 printer deleting failed: $errstr"; return 1; }
		nxlog "$lp $2 printer deleted"
	;;
	media-pa)
		case $2 in
		pa) # tunneled pa
			nxlog "$FUNCNAME ($$): PULSE: umount PulseAudio"
			local midpat="([0-9]+)[[:blank:]]+module-" uri="127.0.0.1"
			[ -n "$4" ] && uri+=":$4"
			txt=$(env LC_ALL=C $COMMAND_PACTL list short 2>/dev/null)
			[ -n "$txt" ] || {
				nxlog "$lp '$svc'; local PA already stopped";	return 0; }
			local mid es mids=$(rematchfn "$midpat.+server=$uri" "$txt" all);
			#nxlog "$lp '$2'; rmids: "$mids; #debug
			for mid in $mids; do
				es=$($COMMAND_PACTL unload-module $mid 2>&1)
				[ $? -ne 0 ] && errstr+="\n$es"
			done
			[ -n "$errstr" ] && {
				nxlog "$lp '$2'; unload some local PA modules failed: $errstr";
			}
			nxlog "$lp $2 remote tunnel disconnected"
			#nxlog "$lp $2 remote tunnel: $($COMMAND_PACTL list short 2>/dev/null)" #debug
		;;
		esac
		[ -n "$3" ] && {
			$COMMAND_PA --kill || {
				nxlog "$lp '$2'; unable to kill local PA";	return 0; }
		}
	;;
	esac
	return 0
}

uservice_start() {
#args:
# <svc> [port] [type] [sharename] [username] [password] [data] [comp]
# [addr=127.0.0.1]
# if type is empty try to operate params from usess db
#	if port not empty try to start on him
# Used config vars: COMMAND_HIDE COMMAND_UNHIDE
	PA_CONF="$USER_FAKE_HOME/.nx/C-$9/pulse"
	local lp="$FUNCNAME ($$/):" errstr="" qs svcport
	local st startfl="" checkfl="" updvars="" updvals="" hpass
	local svc="$1"  port="$2" type="$3" share="$4"
	local username="$5" pass="$6" data="$7" comp="$8"
	local addr="$9"; [ -z "$addr" ] && addr="127.0.0.1";
	[ "$type" = "smb-share" -a -n "$data" ] && data=$(norm_dir "$data" $HOME)

	local i ok="" step="0.25" timeo="28" #4sec
	[ -n "$type" -a -z "$port" ] && {
		# starting no restarting - we wait for session listening port just in case
		local lport_name=$(sess_lport_name $type)
		local wstr="session_id='$session_id' AND $lport_name>0"
		port=44714
		for (( i=0; i<=timeo; i++ )); do
            #FIXME
			#port=$(q_vals_str_get "usess" "$wstr" "$lport_name") && break
			sleep $step"s"
		done
		[ -n "$port" ] || {
			nxlog "$lp $svc session $lport_name no declared after $((timeo/4)) s";
			return 1; }
	}

	# waiting for suitable service status: on/off/""
	ok="" step="0.25" timeo="28" #7sec
	for (( i=0; i<=timeo; i++ )); do
        #FIXME
		st=$(usvcs_get $PA_CONF "status") || { ok="1"; break; }
		stringinstring "$st" "starting|stopping" || { ok="1"; break; }
		sleep $step"s"
	done
	[ -n "$ok" ] || {
		nxlog "$lp service $svc ($port) still set in \"$st\" state after $((timeo/4)) s";
		# FIXME!
		[ "$st" = "stopping" ] || return 1;
		nxlog "$lp service $svc ($port) set state 'off' ultimately";
		usvcs_set $PA_CONF "status" "off"; st="off"
	}

	[ -z "$type" -a -z "$st" ] && {
		nxlog "$lp '$svc': params for service are not found in usess db";
		return 1; }
	[ -z "$type" ] && { #load params from usess db
		qs="$(usvcs_get_list $PA_CONF "type,port,share,username,pass,data,comp,addr")" || {
			nxlog "$lp '$svc': can't get service params from usess db"; return 1; }
		type=$(cutfn "$qs" 0 '&');
		[ -z "$port" ] && port=$(cutfn "$qs" 1 '&');
		share=$(cutfn "$qs" 2 '&'); username=$(cutfn "$qs" 3 '&');
		pass=$(cutfn "$qs" 4 '&'); pass=$(echo "$pass" | $COMMAND_UNHIDE);
		data=$(cutfn "$qs" 5 '&'); comp=$(cutfn "$qs" 6 '&');
		addr=$(cutfn "$qs" 7 '&');
		#nxlog "$lp service $svc ($st) load qs='$qs'" #debug
	}

	if [ "$st" = "on" ]; then
		if uservice_mounted $type $svc; then
			nxlog "$lp service $svc is allready mounted, skipping"; return 0
		else
			nxlog "$lp $svc service status is \"$st\", but it's not mounted. Try to start again";
			startfl=1; [ -n "$type" ] && checkfl="";
			st="starting"; usvcs_set $PA_CONF "status" $st
		fi
	else
		if uservice_mounted $type $svc; then
			usvcs_set $PA_CONF "status" "stopping"
			nxlog "$lp $svc service status is \"$st\", but it's mounted. Try to stop";
			uservice_umount $type $svc $data || {	return 1; }
		fi
		if [ "$st" = "off" ]; then
			startfl=1; [ -n "$type" ] && checkfl="";
			st="starting"; usvcs_set $PA_CONF "status" $st
		else # svc is not found in usess table
			hpass=$(echo $pass | $COMMAND_HIDE)
			#usvcs_add "svc,type,status,port,share,comp,addr,username,pass,data" \
            #	"$svc&$type&starting&$port&$share&$comp&$addr&$username&$hpass&$data"
			usvcs_add "$PA_CONF" "svc=$svc,type=$type,status=$status,port=$port,share=$share,comp=$comp,addr=$addr,username=$username,pass=$pass,data=$data"
			startfl=1;
		fi
	fi

	[ -n "$startfl" ] && {
		[ -n "$checkfl" ] && {
			local s_share s_username s_pass s_data s_comp s_addr
                qs="$(usvcs_get_list $PA_CONF "share,username,pass,data,comp,addr")" || {
				nxlog "$lp can't get service $svc params from usess _db"; return 1; }
			s_share=$(cutfn "$qs" 0 '&'); s_username=$(cutfn "$qs" 1 '&');
			s_pass=$(cutfn "$qs" 2 '&'); s_pass=$(echo $s_pass | $COMMAND_UNHIDE);
			s_data=$(cutfn "$qs" 3 '&'); s_comp=$(cutfn "$qs" 4 '&');
			s_addr=$(cutfn "$qs" 5 '&');
			[ "$share" != "$s_share" ] && {
				nxlog "$lp $svc share strings are different '$s_share' > '$share'"
				updvars+=",share"; updvals+="&$share"; }
			[ "$username" != "$s_username" ] && {
				nxlog "$lp $svc username strings are different '$s_username' > '$username'"
				updvars+=",username"; updvals+="&$username"; }
			[ "$pass" != "$s_pass" ] && {
				nxlog "$lp $svc password strings are different"
				hpass=$(echo $pass | $COMMAND_HIDE)
				updvars+=",pass"; updvals+="&$hpass"; }
			[ "$data" != "$s_data" ] && {
				nxlog "$lp $svc share strings are different '$s_data' > '$data'"
				updvars+=",data"; updvals+="&$data"; }
			[ "$comp" != "$s_comp" ] && {
				nxlog "$lp $svc comp strings are different '$s_comp' > '$comp'"
				updvars+=",comp"; updvals+="&$comp"; }
			[ "$addr" != "$s_addr" ] && {
				nxlog "$lp $svc addr strings are different '$s_addr' > '$addr'"
				updvars+=",addr"; updvals+="&$addr"; }

		}

		#nxlog "$lp _$st _$type _$svc _$port _$username _$pass _$data _$comp" _$share" #debug
		if uservice_mount $type $svc $port "$(echo -e "${username//\%/\\x}")" \
			 "$pass" "$data" "$(echo -e "${comp//\%/\\x}")" "$share";
		then {
			usvcs_set $PA_CONF "status" "on"
			usvcs_set $PA_CONF "port" $port
			usvcs_set $PA_CONF "$updvars" $updvals
			return 0
        }
		else { 
            usvcs_set $PA_CONF "status" "off" 
            usvcs_set $PA_CONF "port" "off";
        }
		fi
	}
	return 1
}

uservice_stop() {
#arg: svc [type] [norestart]
# Used gvars: session_id
	local lp="$FUNCNAME ($$/):"
	local i ok="" st type=$2 lport_name lport="" data="" hardstop=$3
	# waiting for suitable service status: on
	local step=0.25 timeo=28 #7sec
	for (( i=0; i<=timeo; i++ )); do
		st=$(usvcs_get $PA_CONF "status")
		[ "$st" = "on" ] && { ok="1"; break; }
		sleep $step"s"
	done
	[ -n "$ok" ] || {
		nxlog "$lp service $svc still set in \"$st\" state after $((timeo/4))s waitng";
		return 1; }
	[ -z "$type" ] && type=$(usvcs_get $PA_CONF "type")
	usvcs_set $PA_CONF "status" "stopping"
	[ -n "$hardstop" ] || { # get suitable session first
		lport_name=$(sess_lport_name $type)
		local wstr="status='Running' AND session_id!='$session_id' AND $lport_name>0"
		#nxlog "$lp $svc wstr='$wstr'" #debug
		#lport=$(q_vals_str_get "usess" "$wstr" "$lport_name") || {
        lport=$(usvcs_get $PA_CONF "port") || {
			hardstop=1
			nxlog "$lp '$svc': other suitable listening port is not found" #; wstr='$wstr'" #debug
		}
	}
	[ -n "$hardstop" ] && { # if unable to restart we must known data
		data=$(usvcs_get $PA_CONF "data"); }
	#nxlog "$lp '$svc': hs=$hardstop; data=$data" #debug
	uservice_umount $type $svc "$data" "$port" || return 1
	[ -n "$hardstop" ] && {
		if [ "$SESSION_LOG_CLEAN" = "1" ]; then
			q_dbe "DELETE FROM usvcs WHERE svc='$1';"
		else { usvcs_set $PA_CONF "status" "off&0";
               usvcs_set $PA_CONF "port" "off&0";}

		fi
		return 0;
	}
	usvcs_set $PA_CONF "status" "off&0"
	usvcs_set $PA_CONF "port" "off&0"
	uservice_start $svc $lport #|| return 1
	return 0
}

node_pulse_stop(){
    uservice_stop $PA_CONF;
}
