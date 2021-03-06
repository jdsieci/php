#!/usr/bin/env bash
set -Eeuo pipefail

# https://secure.php.net/gpg-keys.php
declare -A gpgKeys=(
	# https://wiki.php.net/todo/php73
	# cmb & stas
	# https://secure.php.net/gpg-keys.php#gpg-7.3
	[7.3]='CBAF69F173A0FEA4B537F470D66C9593118BCCB6 F38252826ACD957EF380D39F2F7956BC5DA04B5D'

	# https://wiki.php.net/todo/php72
	# pollita & remi
	# https://secure.php.net/downloads.php#gpg-7.2
	# https://secure.php.net/gpg-keys.php#gpg-7.2
	[7.2]='1729F83938DA44E27BA0F4D3DBDB397470D12172 B1B44D8F021E4E2D6021E995DC9FF8D3EE5AF27F'

	# https://wiki.php.net/todo/php71
	# davey & krakjoe
	# pollita for 7.1.13 for some reason
	# https://secure.php.net/downloads.php#gpg-7.1
	# https://secure.php.net/gpg-keys.php#gpg-7.1
	[7.1]='A917B1ECDA84AEC2B568FED6F50ABC807BD5DCD0 528995BFEDFBA7191D46839EF9BA0ADA31CBD89E 1729F83938DA44E27BA0F4D3DBDB397470D12172'

	# https://wiki.php.net/todo/php70
	# ab & tyrael
	# https://secure.php.net/downloads.php#gpg-7.0
	# https://secure.php.net/gpg-keys.php#gpg-7.0
	[7.0]='1A4E8B7277C42E53DBA9C7B9BCAA30EA9C0D5763 6E4F6AB321FDC07F2C332E3AC2BF0BC433CFC8B3'

	# https://wiki.php.net/todo/php56
	# jpauli & tyrael
	# https://secure.php.net/downloads.php#gpg-5.6
	# https://secure.php.net/gpg-keys.php#gpg-5.6
	[5.6]='0BD78B5F97500D450838F95DFE857D9A90D90EC1 6E4F6AB321FDC07F2C332E3AC2BF0BC433CFC8B3'

        # https://wiki.php.net/todo/php55
	# jpauli & tyrael
	# https://secure.php.net/downloads.php#gpg-5.5
	[5.5]='0B96609E270F565C13292B24C13C70B87267B52D 0BD78B5F97500D450838F95DFE857D9A90D90EC1'

        # https://wiki.php.net/todo/php54
	# jpauli & tyrael
	# https://secure.php.net/downloads.php#gpg-5.4
	[5.4]='F38252826ACD957EF380D39F2F7956BC5DA04B5D'

        # https://wiki.php.net/todo/php53
	# jpauli & tyrael
	# https://secure.php.net/downloads.php#gpg-5.3
	[5.3]='0A95E9A026542D53835E3F3A7DEC4E69FC9C83D7 0B96609E270F565C13292B24C13C70B87267B52D'
)
# see https://secure.php.net/downloads.php

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

generated_warning() {
	cat <<-EOH
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#

	EOH
}


verlte() {
  [  "$1" = "$(echo -e "$1\n$2" | sort -V | head -n1)" ]
}

verlt() {
  [ "$1" = "$2" ] && return 1 || verlte $1 $2
}

travisEnv=
for version in "${versions[@]}"; do
	rcVersion="${version%-rc}"

	# "7", "5", etc
	majorVersion="${rcVersion%%.*}"
	# "2", "1", "6", etc
	minorVersion="${rcVersion#$majorVersion.}"
	minorVersion="${minorVersion%%.*}"

	# scrape the relevant API based on whether we're looking for pre-releases
	apiUrl="https://secure.php.net/releases/index.php?json&max=500&version=${rcVersion}"
        archive='.xz'
        verlte $rcVersion '5.4' && archive='.bz2'
	apiJqExpr='
		(keys[] | select(startswith("'"$rcVersion"'."))) as $version
		| [ $version, (
			.[$version].source[]
                        | select ( .filename != null )
		        | select(.filename | endswith("'"$archive"'"))
			|
				"https://secure.php.net/get/" + .filename + "/from/this/mirror",
				"https://secure.php.net/get/" + .filename + ".asc/from/this/mirror",
				.sha256 // "",
				.md5 // ""
		) ]
	'
	if [ "$rcVersion" != "$version" ]; then
		apiUrl='https://qa.php.net/api.php?type=qa-releases&format=json'
		apiJqExpr='
			.releases[]
			| select(.version | startswith("'"$rcVersion"'."))
			| [
				.version,
				.files.xz.path // "",
				"",
				.files.xz.sha256 // "",
				.files.xz.md5 // ""
			]
		'
	fi
	IFS=$'\n'
	possibles=( $(
		curl -fsSL "$apiUrl" \
			| jq --raw-output "$apiJqExpr | @sh" \
			| sort -rV
	) )
	unset IFS

	if [ "${#possibles[@]}" -eq 0 ]; then
		echo >&2
		echo >&2 "error: unable to determine available releases of $version"
		echo >&2
		exit 1
	fi

	# format of "possibles" array entries is "VERSION URL.TAR.XZ URL.TAR.XZ.ASC SHA256 MD5" (each value shell quoted)
	#   see the "apiJqExpr" values above for more details
	eval "possi=( ${possibles[0]} )"
	fullVersion="${possi[0]}"
	url="${possi[1]}"
	ascUrl="${possi[2]}"
	sha256="${possi[3]}"
	md5="${possi[4]}"

	gpgKey="${gpgKeys[$rcVersion]}"
	if [ -z "$gpgKey" ]; then
		echo >&2 "ERROR: missing GPG key fingerprint for $version"
		echo >&2 "  try looking on https://secure.php.net/downloads.php#gpg-$version"
		exit 1
	fi

	# if we don't have a .asc URL, let's see if we can figure one out :)
	if [ -z "$ascUrl" ] && wget -q --spider "$url.asc"; then
		ascUrl="$url.asc"
	fi

	dockerfiles=()

	for suite in stretch jessie alpine{3.9,3.8,3.7,3.6,3.4}; do
		[ -d "$version/$suite" ] || continue
		alpineVer="${suite#alpine}"
                alpine=false

		baseDockerfile=Dockerfile-debian.template
		if [ "${suite#alpine}" != "$suite" ]; then
		  baseDockerfile=Dockerfile-alpine.template
                  alpine=true
                  [[ -f "Dockerfile-${suite}.template" ]] && baseDockerfile=Dockerfile-${suite}.template
		fi

		for variant in cli apache fpm zts; do
			[ -d "$version/$suite/$variant" ] || continue
			{ generated_warning; cat "$baseDockerfile"; } > "$version/$suite/$variant/Dockerfile"

			echo "Generating $version/$suite/$variant/Dockerfile from $baseDockerfile + $variant-Dockerfile-block-*"
			tmpDockerfile=$(mktemp)
			gawk -v variant="$variant" '
				$1 == "##</autogenerated>##" { ia = 0 }
				!ia { print }
				$1 == "##<autogenerated>##" { ia = 1; ab++; ac = 0; if (system("test -f " variant "-Dockerfile-block-" ab) != 0) { ia = 0 } }
				ia { ac++ }
				ia && ac == 1 { system("cat " variant "-Dockerfile-block-" ab) }
			' "$version/$suite/$variant/Dockerfile" > ${tmpDockerfile}
			mv -f ${tmpDockerfile} "$version/$suite/$variant/Dockerfile"

			cp \
				docker-php-entrypoint \
				docker-php-ext-* \
				docker-php-source \
				"$version/$suite/$variant/"
			if [ "$variant" = 'apache' ]; then
				cp -a apache2-foreground "$version/$suite/$variant/"
			fi
			if [ "$majorVersion" = '5' ] || [ "$majorVersion" = '7' -a "$minorVersion" -lt '2' ] || [ "$suite" = 'jessie' ]; then
				# argon2 password hashing is only supported in 7.2+ and stretch+
				sed -ri \
					-e '/##<argon2>##/,/##<\/argon2>##/d' \
					-e '/argon2/d' \
					"$version/$suite/$variant/Dockerfile"
			fi
			if [ "$majorVersion" = '5' ] || [ "$majorVersion" = '7' -a "$minorVersion" -lt '2' ]; then
				# sodium is part of php core 7.2+ https://wiki.php.net/rfc/libsodium
				sed -ri '/sodium/d' "$version/$suite/$variant/Dockerfile"
			fi
			if [ "$variant" = 'fpm' -a "$majorVersion" = '7' -a "$minorVersion" -lt '3' ]; then
				# php-fpm "decorate_workers_output" is only available in 7.3+
				sed -ri \
					-e '/decorate_workers_output/d' \
					-e '/log_limit/d' \
					"$version/$suite/$variant/Dockerfile"
			fi

			# remove any _extra_ blank lines created by the deletions above
			awk '
				NF > 0 { blank = 0 }
				NF == 0 { ++blank }
				blank < 2 { print }
			' "$version/$suite/$variant/Dockerfile" > "$version/$suite/$variant/Dockerfile.new"
			mv "$version/$suite/$variant/Dockerfile.new" "$version/$suite/$variant/Dockerfile"

			# automatic `-slim` for stretch
			# TODO always add slim once jessie is removed
			sed -ri \
				-e 's!%%DEBIAN_TAG%%!'"${suite/stretch/stretch-slim}"'!' \
				-e 's!%%DEBIAN_SUITE%%!'"$suite"'!' \
				-e 's!%%ALPINE_VERSION%%!'"$alpineVer"'!' \
				"$version/$suite/$variant/Dockerfile"
			dockerfiles+=( "$version/$suite/$variant/Dockerfile" )

			if $alpine && verlte $alpineVer '3.8' && [ "$alpineVer" != '3.4' ]; then
				# Alpine 3.9+ uses OpenSSL, but 3.8 still uses LibreSSL
				sed -ri -e 's!(\s)openssl!\1libressl!g' "$version/$suite/$variant/Dockerfile"
				# (matching whitespace to avoid "--with-openssl" being replaced with the non-existent "--with-libressl" flag)
			fi
		done
                if [ -d "$version/$suite/fpm-full" ];then
                  dockerfile="Dockerfile-full.template"
                  if verlt $rcVersion '7.0';then
                    dockerfile="Dockerfile-full-5.template"
                  fi
                  { generated_warning; cat "${dockerfile}"; } > "$version/$suite/fpm-full/Dockerfile"
                  dockerfiles+=( "$version/$suite/fpm-full/Dockerfile" )
                fi
	done

	(
		set -x
		sed -ri \
			-e 's!%%PHP_VERSION%%!'"$fullVersion"'!' \
			-e 's!%%GPG_KEYS%%!'"$gpgKey"'!' \
			-e 's!%%PHP_URL%%!'"$url"'!' \
			-e 's!%%PHP_ASC_URL%%!'"$ascUrl"'!' \
			-e 's!%%PHP_SHA256%%!'"$sha256"'!' \
			-e 's!%%PHP_MD5%%!'"$md5"'!' \
			"${dockerfiles[@]}"
	)

	# update entrypoint commands
	for dockerfile in "${dockerfiles[@]}"; do
		cmd="$(awk '$1 == "CMD" { $1 = ""; print }' "$dockerfile" | tail -1 | jq --raw-output '.[0]')"
		entrypoint="$(dirname "$dockerfile")/docker-php-entrypoint"
                [[ -f "$entrypoint" ]] || continue
		sed -i 's! php ! '"$cmd"' !g' "$entrypoint"
	done

	newTravisEnv=
	for dockerfile in "${dockerfiles[@]}"; do
		dir="${dockerfile%Dockerfile}"
		dir="${dir%/}"
		variant="${dir#$version}"
		variant="${variant#/}"
		newTravisEnv+='\n  - VERSION='"$version VARIANT=$variant"
	done
	travisEnv="$newTravisEnv$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml
