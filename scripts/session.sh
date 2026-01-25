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

single_select_opts="$TMUX_FZF_OPTIONS --no-multi"
multi_select_opts="$TMUX_FZF_OPTIONS"
if ! echo "$TMUX_FZF_OPTIONS" | grep -Eq '\\b(-m|--multi)( |=|$)'; then
    multi_select_opts="$TMUX_FZF_OPTIONS -m"
fi

FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS --header='Select an action.'"
if [[ -z "$1" ]]; then
    action=$(printf "switch\nnew\nrename\ndetach\nkill\n[cancel]" | eval "$TMUX_FZF_BIN $TMUX_FZF_OPTIONS")
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
    if [[ "$action" == "new" || "$action" == "rename" ]]; then
        # Create a unique temporary file for session name
        tmp_file=$(mktemp /tmp/tmux_fzf_session_name.XXXXXX)
        tmux display-popup -h 50% -w 50% -E "bash -c 'printf \"Session Name: \" && read session_name && echo \"\$session_name\" > $tmp_file'"
        session_name=$(cat "$tmp_file")
        rm -f "$tmp_file"
        if [ -z "$session_name" ]; then
            exit
        fi
        if [[ "$action" == "new" ]]; then
            tmux new-session -d -s "$session_name" && tmux switch-client -t "$session_name"
            exit
        fi
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
    tmux rename-session -t "$target" "$session_name"
fi
