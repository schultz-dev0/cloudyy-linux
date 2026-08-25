#!/usr/bin/env bash

# Post-promotion reconciliation and explicit previous-stage recovery.

# Internal transaction paths are process-local. Never trust exported values.
unset CLOUDYY_ACTIVATION_DRAFT CLOUDYY_ACTIVATION_STAGE

_activation_action_allowed() {
  local candidate="$1" action
  for action in "${CLOUDYY_THEME_RECONCILE_ACTIONS[@]}"; do
    [[ "$candidate" == "$action" ]] && return 0
  done
  return 1
}

_owned_activation_draft_file() {
  local path="$1" state_root base
  state_root="$(theme_state_root)" || return 1
  [[ -d "$state_root" && ! -L "$state_root" ]] || return 1
  state_root="$(readlink -f -- "$state_root")" || return 1
  base="${path##*/}"
  [[ "$base" =~ ^\.activation-draft\.[[:alnum:]]{8}$ ||
    "$base" =~ ^\.activation-draft-update\.[[:alnum:]]{8}$ ]] || return 1
  [[ "$path" == "$state_root/$base" && -f "$path" && ! -L "$path" ]]
}

_remove_activation_draft_file() {
  local path="$1"
  _owned_activation_draft_file "$path" || return 1
  rm -f -- "$path"
}

_cleanup_stale_activation_drafts() {
  local state_root path cleanup_failed=false
  state_root="$(theme_state_root)" || return 1
  [[ -d "$state_root" && ! -L "$state_root" ]] || return 1
  state_root="$(readlink -f -- "$state_root")" || return 1
  while IFS= read -r -d '' path; do
    _owned_activation_draft_file "$path" || continue
    _remove_activation_draft_file "$path" || cleanup_failed=true
  done < <(find -P "$state_root" -mindepth 1 -maxdepth 1 -type f -print0)
  [[ "$cleanup_failed" == false ]]
}

_discard_activation_draft() {
  if [[ -n "${CLOUDYY_ACTIVATION_DRAFT:-}" ]]; then
    _remove_activation_draft_file "$CLOUDYY_ACTIVATION_DRAFT" || true
  fi
  unset CLOUDYY_ACTIVATION_DRAFT CLOUDYY_ACTIVATION_STAGE
}

begin_activation_results() {
  local stage="$1" draft
  _discard_activation_draft
  _cleanup_stale_activation_drafts || return 1
  draft="$(mktemp "$(theme_state_root)/.activation-draft.XXXXXXXX")" || return 1
  if ! printf '{"prepare":{"status":"success"},"reconcile":{"status":"success","actions":{}}}\n' >"$draft" ||
    ! chmod 600 -- "$draft"; then
    _remove_activation_draft_file "$draft" || true
    return 1
  fi
  CLOUDYY_ACTIVATION_DRAFT="$draft"
  CLOUDYY_ACTIVATION_STAGE="$stage"
}

_activation_draft_write() {
  local filter="$1"
  shift
  local temporary
  [[ -n "${CLOUDYY_ACTIVATION_DRAFT:-}" ]] && _owned_activation_draft_file "$CLOUDYY_ACTIVATION_DRAFT" || return 1
  temporary="$(mktemp "$(theme_state_root)/.activation-draft-update.XXXXXXXX")" || return 1
  if ! jq "$@" "$filter" "$CLOUDYY_ACTIVATION_DRAFT" >"$temporary" ||
    ! chmod 600 -- "$temporary" ||
    ! mv -Tf -- "$temporary" "$CLOUDYY_ACTIVATION_DRAFT"; then
    _remove_activation_draft_file "$temporary" || true
    return 1
  fi
}

write_activation_result() {
  local action="$1" status="$2"
  _activation_action_allowed "$action" || return 1
  case "$status" in
  success | skip | failure) ;;
  *) return 1 ;;
  esac
  _activation_draft_write '
    .reconcile.actions[$action] = {"status":$status}
    | .reconcile.status = (if ([.reconcile.actions[].status] | any(. == "failure")) then "failure" else "success" end)
  ' --arg action "$action" --arg status "$status"
}

_commit_activation_draft() {
  local stage="$1" current
  _owned_activation_draft_file "${CLOUDYY_ACTIVATION_DRAFT:-}" || return 1
  current="$(_theme_pointer_stage "$(theme_state_root)/current" 2>/dev/null)" || return 1
  [[ "$current" == "$stage" && -f "$stage/activation.json" && ! -L "$stage/activation.json" ]] || return 1
  mv -Tf -- "$CLOUDYY_ACTIVATION_DRAFT" "$stage/activation.json"
}

finalize_activation_results() {
  local stage="$1"
  [[ "${CLOUDYY_ACTIVATION_STAGE:-}" == "$stage" ]] || return 1
  _owned_activation_draft_file "${CLOUDYY_ACTIVATION_DRAFT:-}" || return 1
  _activation_document_is_valid "$CLOUDYY_ACTIVATION_DRAFT" || {
    _discard_activation_draft
    return 1
  }
  if ! _commit_activation_draft "$stage"; then
    _discard_activation_draft
    return 1
  fi
  unset CLOUDYY_ACTIVATION_DRAFT CLOUDYY_ACTIVATION_STAGE
}

_record_activation_result() {
  local stage="$1" action="$2" status="$3"
  [[ "${CLOUDYY_ACTIVATION_STAGE:-}" == "$stage" ]] && write_activation_result "$action" "$status" || {
    theme_error "could not record reconciliation action: $action"
    CLOUDYY_RECONCILE_FAILED=true
    return 1
  }
  [[ "$status" == failure ]] && CLOUDYY_RECONCILE_FAILED=true
  return 0
}

print_reconcile_summary() {
  local stage="$1" counts failures
  counts="$(jq -r '
    [.reconcile.actions[].status] as $statuses
    | "\($statuses | map(select(. == "success")) | length) success, "
      + "\($statuses | map(select(. == "skip")) | length) skipped, "
      + "\($statuses | map(select(. == "failure")) | length) failed"
  ' "$stage/activation.json")" || return 1
  printf 'cloudyy-theme: reconcile: %s\n' "$counts"
  failures="$(jq -r '
    [.reconcile.actions | to_entries[] | select(.value.status == "failure") | .key]
    | sort | join(", ")
  ' "$stage/activation.json")" || return 1
  [[ -z "$failures" ]] || printf 'cloudyy-theme: failed actions: %s\n' "$failures"
}

reconcile_theme() {
  local apply_theme_wallpaper="${1:-false}" stage wallpaper wallpaper_result
  stage="$(active_stage)" || {
    theme_error 'active theme state is uninitialized or corrupt'
    return "$CLOUDYY_THEME_EXIT_ACTIVE_STATE"
  }
  begin_activation_results "$stage" || {
    theme_error 'could not initialize activation results'
    return "$CLOUDYY_THEME_EXIT_RECONCILE"
  }
  CLOUDYY_RECONCILE_FAILED=false

  if [[ "$apply_theme_wallpaper" == true ]]; then
    wallpaper="$(theme_wallpaper_one)" || {
      _discard_activation_draft
      return "$CLOUDYY_THEME_EXIT_RECONCILE"
    }
  else
    wallpaper="$(saved_wallpaper 2>/dev/null || true)"
    [[ -n "$wallpaper" ]] || wallpaper="$(theme_wallpaper_one)" || {
      _discard_activation_draft
      return "$CLOUDYY_THEME_EXIT_RECONCILE"
    }
  fi

  if apply_wallpaper "$wallpaper"; then
    _record_activation_result "$stage" wallpaper success || true
    if write_compatibility_state "$wallpaper"; then
      _record_activation_result "$stage" compatibility-state success || true
    else
      theme_error 'wallpaper applied but compatibility state could not be updated'
      _record_activation_result "$stage" compatibility-state failure || true
    fi
  else
    wallpaper_result=$?
    if [[ "$wallpaper_result" -eq "$CLOUDYY_WALLPAPER_BACKEND_UNAVAILABLE" ]]; then
      _record_activation_result "$stage" wallpaper skip || true
    else
      theme_error "wallpaper daemon rejected: $wallpaper"
      _record_activation_result "$stage" wallpaper failure || true
    fi
    _record_activation_result "$stage" compatibility-state skip || true
  fi

  if declare -F reconcile_integrations >/dev/null 2>&1; then
    reconcile_integrations "$stage" || CLOUDYY_RECONCILE_FAILED=true
  fi

  if ! finalize_activation_results "$stage"; then
    theme_error 'could not atomically finalize activation results'
    CLOUDYY_RECONCILE_FAILED=true
  elif ! print_reconcile_summary "$stage"; then
    theme_error 'could not summarize reconciliation results'
    CLOUDYY_RECONCILE_FAILED=true
  fi

  [[ "$CLOUDYY_RECONCILE_FAILED" == false ]] || return "$CLOUDYY_THEME_EXIT_RECONCILE"
}

recover_previous_theme() {
  local state_root current previous
  theme_state_layout_safe || return "$CLOUDYY_THEME_EXIT_ACTIVE_STATE"
  state_root="$(theme_state_root)"
  current="$(_theme_pointer_stage "$state_root/current" 2>/dev/null)" || {
    theme_error 'current theme recovery state is absent or corrupt'
    return "$CLOUDYY_THEME_EXIT_ACTIVE_STATE"
  }
  previous="$(_theme_pointer_stage "$state_root/previous" 2>/dev/null)" || {
    theme_error 'previous theme recovery state is absent or corrupt'
    return "$CLOUDYY_THEME_EXIT_ACTIVE_STATE"
  }
  _stage_is_valid "$current" && _stage_is_valid "$previous" || {
    theme_error 'theme recovery state is corrupt'
    return "$CLOUDYY_THEME_EXIT_ACTIVE_STATE"
  }

  if ! mv --exchange --no-copy -T -- "$state_root/current" "$state_root/previous"; then
    theme_error 'could not atomically exchange current and previous theme pointers'
    return "$CLOUDYY_THEME_EXIT_PROMOTION"
  fi

  reconcile_theme false
}
