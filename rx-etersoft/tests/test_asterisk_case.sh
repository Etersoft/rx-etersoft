#!/bin/sh

CMD="set auth_mode kerberos"

bash --version | head -n1

case $CMD in
    "set auth_mode*"|"SET AUTH_MODE*")
        echo 'WORKS: 078d0bb5        (   gwright     2008-03-07 17:19:07 +0000       795)            "set auth_mode*"|"SET AUTH_MODE*")'
        ;;
    *)
        echo "Old variant is broken"
        ;;
esac

case $CMD in
    "set auth_mode"*|"SET AUTH_MODE"*)
        echo 'WORKS new variant: "set auth_mode"*|"SET AUTH_MODE"*)'
        ;;
    *)
        echo "New variant is broken"
        ;;
esac

echo_x()
{
	echo "$*"
}

case $CMD in
		"set auth_mode"*|"SET AUTH_MODE"*)
			AUTH_MODE="$(echo $CMD | sed 's/set auth_mode \(.*\)/\1/gi' | tr '[A-Z]' '[a-z]')" #'
			case "$AUTH_MODE" in
				password|sshkey|pcsc|kerberos)
					echo_x "Set auth_mode: $AUTH_MODE"
					;;
				*)
					echo_x "NX> 500 ERROR: unknown auth mode '$AUTH_MODE'"
					;;
			esac
esac
