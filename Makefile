# Root-level shortcuts for the reproducible SAURIA experiment flows.
# EDA targets are intended for the persistent Paxos checkout inside tmux.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

PYTHON ?= python3
PROFILE ?= int16_6x6
RUN_ID ?= $(shell date -u +%Y%m%dT%H%M%SZ)-$(shell git rev-parse --short HEAD)
CASE ?=
REPORT ?= experiments/asic_notebook_power/reports/int16_ppa_energy_20261009.csv
SYNTH_REPORT ?= experiments/asic_notebook_power/reports/int16_synthesis_internal_500mhz_20261009.csv
PPA_INPUT ?= experiments/asic_notebook_power/reports/int16_ppa_energy_20261009.json
SYNTH_INPUT ?= experiments/asic_notebook_power/reports/int16_synthesis_internal_500mhz_20261009.json

PROFILE_ROOT = experiments/asic_notebook_power/$(PROFILE)
LOGICAL_RESULTS_ROOT = $(abspath $(PROFILE_ROOT)/logical/results/$(RUN_ID))

ifeq ($(PROFILE),int16_2x2)
DEFAULT_CASE = conv-x2-y2
else ifeq ($(PROFILE),int16_3x3)
DEFAULT_CASE = conv-x3-y3
else ifeq ($(PROFILE),int16_4x4)
DEFAULT_CASE = conv-x4-y3
else ifeq ($(PROFILE),int16_5x5)
DEFAULT_CASE = conv-x4-y5
else ifeq ($(PROFILE),int16_6x6)
DEFAULT_CASE = conv-x6-y6
endif
SELECTED_CASE = $(if $(strip $(CASE)),$(CASE),$(DEFAULT_CASE))

.PHONY: help report list-profiles require-profile require-paxos require-tmux \
	rtl-sim sim synth gate-sim power flow

help:
	@printf '%s\n' \
	  'SAURIA common tasks' \
	  '' \
	  'Reports:' \
	  '  make report [REPORT=path/to/ppa-energy.csv] [SYNTH_REPORT=path/to/synthesis.csv]' \
	  '  make list-profiles' \
	  '' \
	  'Simulation and ASIC flow (run on Paxos inside tmux):' \
	  '  make rtl-sim PROFILE=int16_6x6 [CASE=conv-x6-y6] [RUN_ID=id]' \
	  '  make synth PROFILE=int16_6x6 [RUN_ID=id]' \
	  '  make gate-sim PROFILE=int16_6x6 [CASE=conv-x6-y6] [RUN_ID=id]' \
	  '  make power PROFILE=int16_6x6 [CASE=conv-x6-y6] [RUN_ID=id]' \
	  '  make flow PROFILE=int16_6x6 [CASE=conv-x6-y6] [RUN_ID=id]'

report:
	$(PYTHON) scripts/generate_int16_ppa_csv.py --input "$(PPA_INPUT)" --output "$(REPORT)"
	$(PYTHON) scripts/generate_int16_synthesis_csv.py --input "$(SYNTH_INPUT)" --output "$(SYNTH_REPORT)"

list-profiles:
	@find experiments/asic_notebook_power -mindepth 1 -maxdepth 1 -type d -name 'int16_*' -printf '%f\n' | sort

require-profile:
	@case "$(PROFILE)" in int16_2x2|int16_3x3|int16_4x4|int16_5x5|int16_6x6) ;; \
	  *) echo 'PROFILE must be one of int16_2x2, int16_3x3, int16_4x4, int16_5x5, or int16_6x6.' >&2; exit 2 ;; esac
	@test -d "$(PROFILE_ROOT)" || { echo 'Profile not found: $(PROFILE_ROOT)' >&2; exit 2; }
	@test -n "$(SELECTED_CASE)" || { echo 'CASE is not defined for PROFILE=$(PROFILE).' >&2; exit 2; }

require-paxos:
	@test "$$(hostname -f)" = paxos.inf.pucrs.br || { echo 'EDA targets must run on paxos.inf.pucrs.br.' >&2; exit 2; }
	@test "$$(git rev-parse --show-toplevel)" = /sim/tarsio/sauria || { echo 'Use the persistent checkout /sim/tarsio/sauria on Paxos.' >&2; exit 2; }

require-tmux:
	@test -n "$${TMUX:-}" || { echo 'Start or attach to a tmux session on Paxos before running EDA targets.' >&2; exit 2; }

rtl-sim: require-profile require-paxos require-tmux
	SIM_STAGE=rtl SIM_CASES="$(SELECTED_CASE)" RUN_ID="$(RUN_ID)" \
	  LOGICAL_RESULTS_ROOT="$(LOGICAL_RESULTS_ROOT)" bash "$(PROFILE_ROOT)/sim/run.sh"

sim: rtl-sim

synth: require-profile require-paxos require-tmux
	RUN_ID="$(RUN_ID)" LOGICAL_RESULTS_ROOT="$(LOGICAL_RESULTS_ROOT)" \
	  bash "$(PROFILE_ROOT)/logical/run.sh"

gate-sim: require-profile require-paxos require-tmux
	SIM_STAGE=gate SIM_CASES="$(SELECTED_CASE)" RUN_ID="$(RUN_ID)" \
	  LOGICAL_RESULTS_ROOT="$(LOGICAL_RESULTS_ROOT)" bash "$(PROFILE_ROOT)/sim/run.sh"

power: require-profile require-paxos require-tmux
	POWER_CASE="$(SELECTED_CASE)" POWER_RUN_ID="$(RUN_ID)" \
	  LOGICAL_RESULTS_ROOT="$(LOGICAL_RESULTS_ROOT)" bash "$(PROFILE_ROOT)/power/run.sh"

flow: require-profile require-paxos require-tmux
	SIM_CASES="$(SELECTED_CASE)" RUN_ID="$(RUN_ID)" \
	  bash experiments/asic_notebook_power/run_campaign.sh "$(PROFILE)"
