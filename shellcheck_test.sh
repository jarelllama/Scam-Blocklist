#!/bin/bash
## Example: ShellCheck can detect many different kinds of quoting issues

if ! grep -q backup=true.* "~/.myconfig"
then
  echo 'Backup not enabled in $HOME/.myconfig, exiting'
  exit 1
fi

if [[ $1 =~ "-v(erbose)?" ]]
then
  verbose='-printf "Copying %f\n"'
fi

find backups/ \
  -iname *.tar.gz \
  $verbose \
  -exec scp {}  “myhost:backups” +
