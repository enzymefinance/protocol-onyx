SHELL := /bin/bash

ALL_NETWORKS := mainnet arbitrum base ethereum_sepolia mega_eth plume

.PHONY: help deploy _deploy-one

help:
	@echo "Multi-network single-contract deployment"
	@echo ""
	@echo "Usage:"
	@echo "  make deploy NETWORK=<spec> CONTRACT=<Name> [ACCOUNT=<keystore>]"
	@echo ""
	@echo "NETWORK forms:"
	@echo "  NETWORK=arbitrum                single network"
	@echo "  NETWORK=arbitrum,base           comma-separated subset"
	@echo "  NETWORK=all                     all 6 networks"
	@echo ""
	@echo "Supported networks: $(ALL_NETWORKS)"
	@echo ""
	@echo "Required env (read from .env by forge, not by make):"
	@echo "  ETHERSCAN_API_KEY               Etherscan v2 unified key (mainnet, arbitrum, base, ethereum_sepolia), resolved via foundry.toml [etherscan]"
	@echo "  ETHEREUM_NODE_<NETWORK>         RPC URL per .env.example, resolved via foundry.toml [rpc_endpoints]"
	@echo ""
	@echo "Verification:"
	@echo "  Etherscan v2:  mainnet, arbitrum, base, ethereum_sepolia"
	@echo "  Blockscout:    mega_eth, plume (no API key required)"
	@echo ""
	@echo "Default keystore: <chain>-deployer (override with ACCOUNT=...)"
	@echo "Constructor args: optional deploy/<CONTRACT>/.args.<chain>.txt"
	@echo "                  (omit the file if the contract has no constructor args)"
	@echo "Deployment log:   deploy/logs/log.<chain>.txt (appended on success)"
	@echo "Concurrency:      multi-network parallel deploys prompt for each keystore password sequentially upfront,"
	@echo "                  then run forge create concurrently; output is line-prefixed with [<chain>]"

deploy:
	@if [ -z "$(NETWORK)" ]; then \
	  echo "NETWORK is required (e.g., NETWORK=arbitrum, NETWORK=arbitrum,base, NETWORK=all)" >&2; \
	  exit 1; \
	fi
	@if [ -z "$(CONTRACT)" ]; then \
	  echo "CONTRACT is required (e.g., CONTRACT=FeeHandler)" >&2; \
	  exit 1; \
	fi
	@if [ "$(NETWORK)" = "all" ]; then \
	  nets="$(ALL_NETWORKS)"; \
	else \
	  nets="$$(echo '$(NETWORK)' | tr ',' ' ')"; \
	fi; \
	for net in $$nets; do \
	  case " $(ALL_NETWORKS) " in \
	    *" $$net "*) ;; \
	    *) echo "unsupported network: $$net (allowed: $(ALL_NETWORKS))" >&2; exit 1 ;; \
	  esac; \
	done; \
	mkdir -p deploy/logs; \
	nets_arr=(); accounts_arr=(); \
	for net in $$nets; do \
	  nets_arr+=("$$net"); \
	  if [ -n "$(ACCOUNT)" ]; then \
	    accounts_arr+=("$(ACCOUNT)"); \
	  else \
	    accounts_arr+=("$$net-deployer"); \
	  fi; \
	done; \
	umask 077; \
	unique_accounts=(); unique_pwfiles=(); \
	cleanup() { for f in "$${unique_pwfiles[@]}"; do [ -n "$$f" ] && rm -f "$$f"; done; }; \
	trap cleanup EXIT INT TERM; \
	for acc in "$${accounts_arr[@]}"; do \
	  seen=0; \
	  for u in "$${unique_accounts[@]}"; do \
	    if [ "$$u" = "$$acc" ]; then seen=1; break; fi; \
	  done; \
	  if [ "$$seen" = "0" ]; then \
	    pwf="$$(mktemp)"; \
	    unique_accounts+=("$$acc"); \
	    unique_pwfiles+=("$$pwf"); \
	    read -s -p "Password for keystore $$acc: " pw </dev/tty; echo; \
	    printf '%s' "$$pw" > "$$pwf"; \
	    unset pw; \
	  fi; \
	done; \
	pwfiles_per_net=(); \
	for acc in "$${accounts_arr[@]}"; do \
	  for i in "$${!unique_accounts[@]}"; do \
	    if [ "$${unique_accounts[$$i]}" = "$$acc" ]; then \
	      pwfiles_per_net+=("$${unique_pwfiles[$$i]}"); \
	      break; \
	    fi; \
	  done; \
	done; \
	echo ">>> Deploying $(CONTRACT) in parallel to:$$nets" | tr -s ' '; \
	use_color=1; \
	if [ -n "$$NO_COLOR" ] || [ ! -t 1 ]; then use_color=0; fi; \
	color_for() { \
	  case "$$1" in \
	    mainnet)          echo "38;5;33" ;; \
	    arbitrum)         echo "38;5;208" ;; \
	    base)             echo "38;5;51" ;; \
	    ethereum_sepolia) echo "38;5;141" ;; \
	    mega_eth)         echo "38;5;213" ;; \
	    plume)            echo "38;5;245" ;; \
	  esac; \
	}; \
	pids_arr=(); \
	for i in "$${!nets_arr[@]}"; do \
	  net="$${nets_arr[$$i]}"; \
	  acc="$${accounts_arr[$$i]}"; \
	  pwf="$${pwfiles_per_net[$$i]}"; \
	  c=""; \
	  if [ "$$use_color" = "1" ]; then c="$$(color_for "$$net")"; fi; \
	  ( set -o pipefail; $(MAKE) --no-print-directory _deploy-one NETWORK="$$net" CONTRACT=$(CONTRACT) ACCOUNT="$$acc" KEYSTORE_PASSWORD_FILE="$$pwf" 2>&1 | awk -v net="$$net" -v c="$$c" '{ if (c != "") printf "\033[%sm[%s] %s\033[0m\n", c, net, $$0; else print "[" net "] " $$0; fflush() }' ) & \
	  pids_arr+=($$!); \
	done; \
	failed=""; succeeded=""; \
	for i in "$${!nets_arr[@]}"; do \
	  net="$${nets_arr[$$i]}"; \
	  pid="$${pids_arr[$$i]}"; \
	  if wait $$pid; then \
	    succeeded="$$succeeded $$net"; \
	  else \
	    failed="$$failed $$net"; \
	  fi; \
	done; \
	echo; echo "=== Summary ==="; \
	echo "OK:   $${succeeded:- (none)}"; \
	echo "FAIL: $${failed:- (none)}"

_deploy-one:
	@net="$(NETWORK)"; \
	case "$$net" in \
	  mainnet)          verify_flags="--verify";                                                                                            explorer="https://etherscan.io" ;; \
	  arbitrum)         verify_flags="--verify";                                                                                            explorer="https://arbiscan.io" ;; \
	  base)             verify_flags="--verify";                                                                                            explorer="https://basescan.org" ;; \
	  ethereum_sepolia) verify_flags="--verify";                                                                                            explorer="https://sepolia.etherscan.io" ;; \
	  mega_eth)         verify_flags="--verify --verifier blockscout --verifier-url https://megaeth.blockscout.com/api/";                   explorer="https://megaeth.blockscout.com" ;; \
	  plume)            verify_flags="--verify --verifier blockscout --verifier-url https://explorer-plume-mainnet-1.t.conduit.xyz/api/";   explorer="https://explorer.plume.org" ;; \
	  *) echo "internal error: unknown network $$net" >&2; exit 1 ;; \
	esac; \
	account="$(ACCOUNT)"; \
	if [ -z "$$account" ]; then account="$$net-deployer"; fi; \
	args_flag=""; \
	if [ -f "deploy/$(CONTRACT)/.args.$$net.txt" ]; then \
	  args_flag="--constructor-args-path deploy/$(CONTRACT)/.args.$$net.txt"; \
	fi; \
	pw_flag=""; \
	if [ -n "$(KEYSTORE_PASSWORD_FILE)" ] && [ -f "$(KEYSTORE_PASSWORD_FILE)" ]; then \
	  pw_flag="--password-file $(KEYSTORE_PASSWORD_FILE)"; \
	fi; \
	mkdir -p deploy/logs; \
	logfile="deploy/logs/log.$$net.txt"; \
	tmpout="$$(mktemp)"; \
	set -o pipefail; \
	if forge create \
	    --rpc-url $$net \
	    --account $$account \
	    $$pw_flag \
	    --broadcast \
	    --delay 10 \
	    --retries 10 \
	    $$args_flag \
	    $$verify_flags \
	    $(CONTRACT) 2>&1 | tee "$$tmpout"; then \
	  addr=$$(grep -E '^Deployed to:' "$$tmpout" | awk '{print $$NF}' | tail -n1); \
	  txh=$$(grep -E '^Transaction hash:' "$$tmpout" | awk '{print $$NF}' | tail -n1); \
	  echo "$$(date -u +%FT%TZ) $(CONTRACT) $$explorer/address/$$addr $$explorer/tx/$$txh" >> "$$logfile"; \
	  rm -f "$$tmpout"; \
	else \
	  rc=$$?; rm -f "$$tmpout"; exit $$rc; \
	fi
