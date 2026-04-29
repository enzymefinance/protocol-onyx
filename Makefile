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
	@echo "Per-network short names (used by keystore default and args file):"
	@echo "  mainnet=mainnet  arbitrum=arbitrum  base=base"
	@echo "  ethereum_sepolia=sepolia  mega_eth=megaeth  plume=plume"
	@echo ""
	@echo "Default keystore: <short>-deployer (override with ACCOUNT=...)"
	@echo "Constructor args: optional .args.<short>.txt at repo root"
	@echo "                  (omit the file if the contract has no constructor args)"
	@echo "Deployment log:   deploy/log.<network>.txt (appended on success)"

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
	mkdir -p deploy; \
	failed=""; succeeded=""; \
	for net in $$nets; do \
	  echo; echo ">>> Deploying $(CONTRACT) to $$net"; \
	  if $(MAKE) --no-print-directory _deploy-one NETWORK=$$net CONTRACT=$(CONTRACT) ACCOUNT="$(ACCOUNT)"; then \
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
	  mainnet)          short=mainnet;  verify_flags="--verify" ;; \
	  arbitrum)         short=arbitrum; verify_flags="--verify" ;; \
	  base)             short=base;     verify_flags="--verify" ;; \
	  ethereum_sepolia) short=sepolia;  verify_flags="--verify" ;; \
	  mega_eth)         short=megaeth;  verify_flags="--verify --verifier blockscout --verifier-url https://megaeth.blockscout.com/api/" ;; \
	  plume)            short=plume;    verify_flags="--verify --verifier blockscout --verifier-url https://explorer-plume-mainnet-1.t.conduit.xyz/api/" ;; \
	  *) echo "internal error: unknown network $$net" >&2; exit 1 ;; \
	esac; \
	account="$(ACCOUNT)"; \
	if [ -z "$$account" ]; then account="$$short-deployer"; fi; \
	args_flag=""; \
	if [ -f ".args.$$short.txt" ]; then \
	  args_flag="--constructor-args-path .args.$$short.txt"; \
	fi; \
	mkdir -p deploy; \
	logfile="deploy/log.$$net.txt"; \
	tmpout="$$(mktemp)"; \
	set -o pipefail; \
	if forge create \
	    --rpc-url $$net \
	    --account $$account \
	    --broadcast \
	    --delay 10 \
	    --retries 10 \
	    $$args_flag \
	    $$verify_flags \
	    $(CONTRACT) 2>&1 | tee "$$tmpout"; then \
	  addr=$$(grep -E '^Deployed to:' "$$tmpout" | awk '{print $$NF}' | tail -n1); \
	  txh=$$(grep -E '^Transaction hash:' "$$tmpout" | awk '{print $$NF}' | tail -n1); \
	  echo "$$(date -u +%FT%TZ) $(CONTRACT) $$addr $$txh" >> "$$logfile"; \
	  rm -f "$$tmpout"; \
	else \
	  rc=$$?; rm -f "$$tmpout"; exit $$rc; \
	fi
