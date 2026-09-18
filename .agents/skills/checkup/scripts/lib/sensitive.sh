#!/usr/bin/env bash

is_sensitive_path() {
  local nocasematch_was_set=false
  local result=1

  if shopt -q nocasematch; then
    nocasematch_was_set=true
  else
    shopt -s nocasematch
  fi

  case "/$1/" in
    */.env/*|*/credentials/*|*/credential/*|*/secrets/*|*/secret/*|*/cookies/*|*/cookie/*|*/browser-profile/*|*/.aws/*|*/.ssh/*|*/.gnupg/*)
      result=0
      ;;
  esac
  case "${1##*/}" in
    .env|.env.*|*credential*|*secret*|*cookie*|*.pem|*.key|*.p12|*.pfx|*.jks|*.keystore|*.kdbx|id_rsa|id_ed25519|id_ecdsa|id_dsa|.npmrc|.pypirc|.netrc|*.tfstate*)
      result=0
      ;;
  esac

  if [[ $nocasematch_was_set == false ]]; then
    shopt -u nocasematch
  fi
  return "$result"
}
