#!/bin/sh
## Example: The shebang says 'sh' so shellcheck warns about portability
##          Change it to '#!/bin/bash' to allow bashisms
for n in {1..$RANDOM}
do
  str=""
  if (( n % 3 == 0 ))
  then
    str="fizz"
  fi
  if [ $[n%5] == 0 ]
  then
    str="$strbuzz"
  fi
  if [[ ! $str ]]
  then
    str="$n"
  fi
  echo "$str"
done
