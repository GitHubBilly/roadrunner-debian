#!/usr/bin/env bash
set_window_title ()
{
    test ."$1" != .'' && printf "\e]0;$@\a\n"
}

set_window_title "$(id -nu)@$HOSTNAME"
