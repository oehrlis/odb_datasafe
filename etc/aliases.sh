#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: aliases.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.17
# Revision...: 0.11.2
# Purpose....: Optional odb_datasafe alias hook
# Notes......: Sourced by OraDBA when:
#              - ORADBA_EXTENSIONS_SOURCE_ETC=true
#              - .extension contains load_aliases: true
# ------------------------------------------------------------------------------

alias dshelp='odb_datasafe_help.sh'
alias dsversion='ds_version.sh'
alias dsconcheck='ds_connector_update.sh --check-all'
