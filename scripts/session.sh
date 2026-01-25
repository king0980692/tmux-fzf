#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/.envs"

if [[ -z "$TMUX_FZF_SESSION_FORMAT" ]]; then
    sessions=$(tmux list-sessions)
else
    sessions=$(tmux list-sessions -F "#S: $TMUX_FZF_SESSION_FORMAT")
fi

if [[ -z "$TMUX_FZF_SWITCH_CURRENT" ]]; then
    current_session=$(tmux display-message -p | sed -e 's/^\[//' -e 's/\].*//')
    sessions=$(echo "$sessions" | grep -v "^$current_session: ")
fi

single_select_opts="$TMUX_FZF_OPTIONS"
single_select_opts=$(echo "$single_select_opts" | sed -E 's/(^|[[:space:]])(-m|--multi)([[:space:]]|$)/\1/g')
single_select_opts=$(echo "$single_select_opts" | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^ //; s/ $//')
multi_select_opts="$TMUX_FZF_OPTIONS"
if ! echo "$multi_select_opts" | grep -Eq '\\b(-m|--multi)( |=|$)'; then
    if [ -z "$multi_select_opts" ]; then
        multi_select_opts="-m"
    else
        multi_select_opts="$multi_select_opts -m"
    fi
fi

FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS --header='Select an action.'"
if [[ -z "$1" ]]; then
    action=$(printf "switch\nnew\nrename\ndetach\nkill\n[cancel]" | eval "$TMUX_FZF_BIN $single_select_opts")
else
    action="$1"
fi

[[ "$action" == "[cancel]" || -z "$action" ]] && exit
if [[ "$action" != "detach" ]]; then
    if [[ "$action" == "kill" ]]; then
        FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS --header='Select target session(s). Press TAB to mark multiple items.'"
    else
        FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS --header='Select target session.'"
    fi
    if [[ "$action" == "switch" ]]; then
        target_origin=$(printf "%s\n[cancel]" "$sessions" | eval "$TMUX_FZF_BIN $single_select_opts $TMUX_FZF_PREVIEW_SESSION_OPTIONS")
    elif [[ "$action" != "new" ]]; then
        target_origin=$(printf "[current]\n%s\n[cancel]" "$sessions" | eval "$TMUX_FZF_BIN $single_select_opts $TMUX_FZF_PREVIEW_SESSION_OPTIONS")
        target_origin=$(echo "$target_origin" | sed -E "s/\[current\]/$current_session:/")
    fi
    if [[ "$action" == "new" ]]; then
        tmux command-prompt -p "New session name:" "new-session -d -s '%%' \\; switch-client -t '%%'"
        exit
    fi
else
    tmux_attached_sessions=$(tmux list-sessions | grep 'attached' | grep -o '^[[:alpha:][:digit:]_-]*:' | sed 's/.$//g')
    sessions=$(echo "$sessions" | grep "^$tmux_attached_sessions")
    FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS --header='Select target session(s). Press TAB to mark multiple items.'"
    target_origin=$(printf "[current]\n%s\n[cancel]" "$sessions" | eval "$TMUX_FZF_BIN $multi_select_opts $TMUX_FZF_PREVIEW_SESSION_OPTIONS")
    target_origin=$(echo "$target_origin" | sed -E "s/\[current\]/$current_session:/")
fi
[[ "$target_origin" == "[cancel]" || -z "$target_origin" ]] && exit
target=$(echo "$target_origin" | sed -e 's/:.*$//')
if [[ "$action" == "switch" ]]; then
    tmux switch-client -t "$target"
elif [[ "$action" == "detach" ]]; then
    echo "$target" | xargs -I{} tmux detach -s "{}"
elif [[ "$action" == "kill" ]]; then
    echo "$target" | sort -r | xargs -I{} tmux kill-session -t "{}"
elif [[ "$action" == "rename" ]]; then
    tmux command-prompt -I "$target" -p "Rename session:" "rename-session -t '$target' '%%'"
fi
