#!/usr/bin/env bash
# 09-final-status.sh — print human-readable installation summary
# Reads from the global _STATUS_LINES array populated by all prior steps.
# Called last by install.sh and validate.sh.
#
# Standalone: sudo bash scripts/09-final-status.sh
# Sourced by: install.sh, validate.sh

set -euo pipefail

# print_summary — formats _STATUS_LINES into a clean aligned table
print_summary() {
    local W=72  # inner width of the box

    # ── Box characters ────────────────────────────────────────────────────────
    local top_border="+"
    local mid_border="+"
    local bot_border="+"
    for (( i=0; i<W+2; i++ )); do
        top_border="${top_border}-"
        mid_border="${mid_border}-"
        bot_border="${bot_border}-"
    done
    top_border="${top_border}+"
    mid_border="${mid_border}+"
    bot_border="${bot_border}+"

    local section_line="  $(printf '%.0s-' $(seq 1 68))"

    echo ""
    echo "$top_border"
    printf "|  %-${W}s  |\n" "RustDesk Server OSS — Installation Summary"
    echo "$mid_border"
    printf "|  %-${W}s  |\n" "Completed : $(date)"
    printf "|  %-${W}s  |\n" "Server IP : ${SERVER_IP:-<not set>}"
    echo "$bot_border"
    echo ""

    local current_cat=""

    for entry in "${_STATUS_LINES[@]+"${_STATUS_LINES[@]}"}"; do
        IFS='|' read -r cat label result detail <<< "$entry"

        # Print category header when it changes
        if [[ "$cat" != "$current_cat" ]]; then
            [[ -n "$current_cat" ]] && echo ""
            printf "  ${BOLD}%s${RESET}\n" "$cat"
            echo "$section_line"
            current_cat="$cat"
        fi

        # Colour code by result
        local color="$RESET"
        local icon=" "
        case "$result" in
            PASS) color="$GREEN";  icon="+" ;;
            FAIL) color="$RED";    icon="!" ;;
            WARN) color="$YELLOW"; icon="~" ;;
            INFO) color="$CYAN";   icon="i" ;;
        esac

        printf "  ${color}[%s]${RESET}  %-34s %s\n" "$icon" "$label" "$detail"
    done

    # ── Totals ────────────────────────────────────────────────────────────────
    echo ""
    echo "  $(printf '%.0s-' $(seq 1 68))"
    printf "  "
    printf "${GREEN}%d passed${RESET}   " "$PASS_COUNT"
    printf "${YELLOW}%d warnings${RESET}   " "$WARN_COUNT"
    printf "${RED}%d failed${RESET}\n" "$FAIL_COUNT"
    echo ""

    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        echo -e "  ${RED}${BOLD}Installation completed with failures. Review the items above.${RESET}"
    elif [[ "$WARN_COUNT" -gt 0 ]]; then
        echo -e "  ${YELLOW}${BOLD}Installation completed with warnings. Review the items above.${RESET}"
    else
        echo -e "  ${GREEN}${BOLD}All checks passed. RustDesk Server OSS is ready.${RESET}"
    fi

    echo ""
    echo "  Next steps:"
    printf "  %s\n" "1. Test SSH in a new terminal:   ssh -p ${SSH_PORT:-2222} ${ADMIN_USER:-rdadmin}@${SERVER_IP:-<IP>}"
    printf "  %s\n" "2. Run validation:               sudo bash validate.sh"
    printf "  %s\n" "3. Back up keys now:             sudo bash backup/backup-rustdesk-keys.sh"
    printf "  %s\n" "4. Configure clients:            see docs/CLIENT-CONFIG.md"
    echo ""
}

step_09_final_status() {
    step "Final summary"
    print_summary
}

# ── Standalone execution ───────────────────────────────────────────────────────
# STANDALONE_ONLY_BEGIN
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/lib-common.sh"
    load_env "$SCRIPT_DIR"
    add_status "Info" "Standalone mode" INFO "run install.sh for full summary"
    step_09_final_status
fi
# STANDALONE_ONLY_END
