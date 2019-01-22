#!/usr/bin/env bash

set -eE

if [ "${BASH_VERSION:0:1}" -lt 4 ]; then
  echo -e "\\nYou are using a very old version of Bash. Please install"
  echo "version 4.1 or later. If this is an OSX host, see:"
  echo "https://apple.stackexchange.com/a/193413 or similar"
  exit 13
fi

# Strip all the cruft out of matching strings
# Requires two arguments:
# $1 is the variable name to set the return to
# $2 is the string to cleanse
function cleanse_matches() {
  [ -z "$1" ] && return 1
  [ -z "$2" ] && return 1
  local res res1 res2
  res1=$(sed -e "s|^\s*\(->\)*\s*class\s*{\s*['\"]*:*||" \
             -e "s|^\s*\(->\)*\s*include\s*['\"]*||" \
             -e "s|^\s*\(->\)*\s*contain\s*['\"]*||" \
             -e "s|['\"]\s*:*.*||" \
             -e "s|\s*#.*||" \
             <<< "$2")
  # This will remove all role::something and all role::$something. If anything
  # other than role modules are included in manifests/site.pp, it is an error
  # and for all role modules, we are processing them all anyway, so we don't
  # care if the are included.
  res2=$(grep -v 'role::[a-z$]' <<< "$res1") || : # No match is not an error
  res="$res2"
  unset -v "$1"
  printf -v "$1" '%s' "$res"
}

# Print msg on stderr and exit
function fail() {
  echo -e "\\n$*\\n" >&2
  exit 1
}

# Find all the matching patterns.
# Requires two arguments:
# $1 is the variable name to set the return to
# $2 is the file in which to find matches
function find_matches() {
  [ -z "$1" ] && return 1
  [ -z "$2" ] && return 1
  local res
  res=$(grep -Eh -e 'class[[:space:]]*{' \
    -e '^[[:space:]]*(->)?[[:space:]]*(contain |include )' "$2" | \
    grep -v -e '^[[:space:]]*#') || : # No matches is not a failure
  unset -v "$1"
  printf -v "$1" '%s' "$res"
}

# Print usage and optional warning message
function help() {
  local out err
  if [ -n "$1" ]; then
    out='/dev/stderr'
    err=1
    echo -e "\\n$1" >$out
  else
    out='/dev/stdout'
    err=0
  fi
  cat >$out <<-EOF

		Usage: $0 -r /path/to/control-repo [-c]
		  -r    Where the control-repo lives
		  -c    Disable color

	EOF
  exit $err
}

# Convenience function to couple find_matches() with cleanse_matches()
# Requires one argument: The file to be processed
function process_file() {
  # Ensure a clean slate
  match=
  match_cleansed=
  find_matches match "$1"
  if [ -n "$match" ]; then
    cleanse_matches match_cleansed "$match"
  fi
}

# Process args
set -- "$@" _eNd_OF_lisT_
while [ "$1" != "_eNd_OF_lisT_" ]; do
  case "$1" in
  -c) color='no'; shift;;
  -r) repos="$2"; shift 2;;
  -h) help;;
   *) help "Unknown option: $1";;
  esac
done

# For prettier output
if [ "$color" == 'no' ]; then
  normal=''
  grn="$normal"
  blue="$normal"
  whi="$normal"
else
  normal="\\e[0;00m"
  grn="\\e[1;32m"
  blue="\\e[1;34m"
  whi="\\e[1;37m"
fi

# Test args
if [ -z "$repos" ]; then
  help "Missing the path to the control-repo"
fi
if [ ! -d "$repos" ] || [ ! -r "$repos" ] || [ ! -x "$repos" ]; then
  fail "\"$repos\" is either missing or has bad permissions"
fi

# Now that all vars should be vetted, bail on unset vars
set -u

# These vars will be set/unset with each file parsed. To prevent a shellcheck
# error (SC2154) due to shellcheck not yet supporting "printf -v" style variable
# setting, we will declare them first.
declare match
declare match_cleansed

# Placeholders to aggregate and sort all found modules
allmods=()
uniqmods=()

# Now process all of the role modules
mapfile -t manifests < <(find "$repos" -type f -name \*.pp)

# Print the modules found in each role and print the file name. At the same
# time, collect all of the modules in an array for further processing.
for manifest in "${manifests[@]}"; do
  process_file "$manifest"
  if [ -n "$match_cleansed" ]; then
    line="${manifest//?/-}"
    echo -e "\\n${grn}${manifest}\\n${line}${normal}"
    echo -e "${whi}${match_cleansed}${normal}"
    # Save all found modules in an array for later use
    mapfile -t append <<<"$match_cleansed"
    allmods+=("${append[@]}")
    unset append
  fi
done

# Purge duplicates. If a subclass is referenced (like foo::bar or
# foo::bar::baz), strip all by the module name (foo). The first iteration, when
# uniqmods is empty, will trigger an unbound error due to set -u. Ignore that
# for this for loop as we know it is empty.
set +u
for mod in "${allmods[@]}"; do
  # If the module begins with :: it will expand to nothing, so strip the ::
  [ "${mod%%:*}" == '' ] && mod="${mod:2}"
  # Beginning of array
  [[ ${uniqmods[*]} =~ ^${mod%%:*}[[:space:]] ]] && continue
  # End of array
  [[ ${uniqmods[*]} =~ [[:space:]]${mod%%:*}$ ]] && continue
  # Only entry in array
  [[ ${uniqmods[*]} =~ ^${mod%%:*}$ ]] && continue
  # Anywhere else in the array
  [[ ${uniqmods[*]} =~ [[:space:]]${mod%%:*}[[:space:]] ]] && continue
  uniqmods+=("${mod%%:*}")
done
set -u

# Finally sort the array and print the collection
mapfile -t sortedmods < <(printf '%s\0' "${uniqmods[@]}" |sort -z |xargs -0n1)
echo -e "\\n\\n\\n${blue}##############################################"
echo "ALL unique compoenent modules being pulled in:"
echo -e "##############################################${normal}\\n"
for mod in "${sortedmods[@]}"; do
  echo "$mod"
done

# vim: set tw=80 ts=2 sw=2 sts=2 et:
