#!/usr/bin/env bash

set -euo pipefail

START_DIR="${1:-$PWD}"

info() {
  echo "check-systemd-trigger-services: $*"
}

err() {
  echo "check-systemd-trigger-services: $*" >&2
  exit 1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

read_unit_property() {
  local unit_file="$1"
  local property_name="$2"
  local value

  value="$(sed -n "s/^[[:space:]]*${property_name}=[[:space:]]*//p" "${unit_file}" | tail -n 1 || true)"
  trim "${value}"
}

normalize_service_unit() {
  local unit_name

  unit_name="$(trim "$1")"
  if [ -z "${unit_name}" ]; then
    printf '%s' ""
    return 0
  fi

  case "${unit_name}" in
    *.service)
      printf '%s' "${unit_name}"
      ;;
    *.*)
      printf '%s' ""
      ;;
    *)
      printf '%s.service' "${unit_name}"
      ;;
  esac
}

default_service_unit_for() {
  local unit_file="$1"
  local base_name

  base_name="$(basename "${unit_file}")"
  printf '%s.service' "${base_name%.*}"
}

resolve_service_file() {
  local source_unit="$1"
  local service_unit_name="$2"
  local unit_dir service_file container_file service_base

  unit_dir="$(dirname "${source_unit}")"
  service_file="${unit_dir}/${service_unit_name}"
  if [ -f "${service_file}" ]; then
    printf '%s' "${service_file}"
    return 0
  fi

  service_base="${service_unit_name%.service}"
  case "${unit_dir}" in
    */home/.config/systemd/user)
      container_file="${START_DIR}/home/.config/containers/systemd/${service_base}.container"
      if [ -f "${container_file}" ]; then
        printf '%s' "${container_file}"
        return 0
      fi
      ;;
    */home/.config/containers/systemd)
      container_file="${unit_dir}/${service_base}.container"
      if [ -f "${container_file}" ]; then
        printf '%s' "${container_file}"
        return 0
      fi
      ;;
  esac

  return 1
}

validate_trigger_unit() {
  local trigger_unit="$1"
  local service_unit_name target_file property_name explicit_target

  case "${trigger_unit}" in
    *.path|*.timer)
      property_name="Unit"
      ;;
    *.socket)
      property_name="Service"
      ;;
    *)
      err "unsupported trigger unit: ${trigger_unit}"
      ;;
  esac

  explicit_target="$(read_unit_property "${trigger_unit}" "${property_name}")"
  if [ -n "${explicit_target}" ]; then
    service_unit_name="$(normalize_service_unit "${explicit_target}")"
    if [ -z "${service_unit_name}" ]; then
      err "${trigger_unit}: ${property_name}= が service unit ではないため検証できません: ${explicit_target}"
    fi
  else
    service_unit_name="$(default_service_unit_for "${trigger_unit}")"
  fi

  target_file="$(resolve_service_file "${trigger_unit}" "${service_unit_name}" || true)"
  if [ -z "${target_file}" ]; then
    err "${trigger_unit}: 参照先 service が見つかりません: ${service_unit_name}"
  fi

  # Trigger unit 配下の参照先 service には通常 #NOSTART を要求します。
  # ただし、deploy 直後の起動も許可したい unit は #FORCESTART で例外扱いにします。
  if ! grep -q '^#NOSTART' "${target_file}" && ! grep -q '^#FORCESTART' "${target_file}"; then
    err "${trigger_unit}: 参照先 ${target_file} に #NOSTART または #FORCESTART が必要です"
  fi

  info "ok: ${trigger_unit} -> ${target_file}"
}

while IFS= read -r trigger_unit; do
  validate_trigger_unit "${trigger_unit}"
done < <(
  find \
    "${START_DIR}/home/.config/systemd/user" \
    "${START_DIR}/home/.config/containers/systemd" \
    "${START_DIR}/systemd" \
    \( -name '*.path' -o -name '*.socket' -o -name '*.timer' \) \
    -type f ! -name '*~' 2>/dev/null | sort
)
