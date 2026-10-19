#!/usr/bin/env bash
set -e

# bolt-legal-cz scaffold: appends the legal: block to theme.yaml from the intake answers
# (SKILL.md, Step 0) and copies the partials. Existing files and an existing legal: block are kept.

usage() {
    echo "Usage: scaffold.sh --operator=trade|company|profession|other --consumers|--no-consumers"
    echo "                   [--online-contracts] [--reviews] [--whistleblowing] [--not-microenterprise]"
    echo "                   [--adr=coi|eru|ctu|finarbitr|cak]"
    echo ""
    echo "  --operator           who operates the website (OP): trade = OSVČ – živnostník, company = in the"
    echo "                       Commercial Register, profession = advokát, lékař, architekt …, other = spolek …"
    echo "  --consumers          sells products or services to consumers (SP); --no-consumers: B2B only"
    echo "  --online-contracts   orders, paid bookings or subscriptions concluded on the website (EC)"
    echo "  --reviews            the site shows reviews or client testimonials (SP-06)"
    echo "  --whistleblowing     obliged entity under zákon č. 171/2023 Sb. (WB-01)"
    echo "  --not-microenterprise  10+ employees or turnover above EUR 2 M (EC-06, accessibility)"
    echo "  --adr                ADR body (SP-01); default coi (Česká obchodní inspekce)"
}

OPERATOR=""
CONSUMERS=""
ONLINE=false
REVIEWS=false
WHISTLEBLOWING=false
MICRO=true
ADR=coi
for arg in "$@"; do
    case "$arg" in
        --operator=*) OPERATOR="${arg#*=}" ;;
        --consumers) CONSUMERS=true ;;
        --no-consumers) CONSUMERS=false ;;
        --online-contracts) ONLINE=true ;;
        --reviews) REVIEWS=true ;;
        --whistleblowing) WHISTLEBLOWING=true ;;
        --not-microenterprise) MICRO=false ;;
        --adr=*) ADR="${arg#*=}" ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown argument: $arg"; usage; exit 1 ;;
    esac
done

case "$OPERATOR" in
    trade|company|profession|other) ;;
    *) echo "ERROR: --operator is required — ask who operates the website (AG-01)."; usage; exit 1 ;;
esac
if [ -z "$CONSUMERS" ]; then
    echo "ERROR: pass --consumers or --no-consumers — ask whether the operator sells to consumers (SP)."
    exit 1
fi
case "$ADR" in
    coi) ADR_CS="Česká obchodní inspekce"; ADR_EN="Czech Trade Inspection Authority"; ADR_URL="https://coi.gov.cz" ;;
    eru) ADR_CS="Energetický regulační úřad"; ADR_EN="Energy Regulatory Office"; ADR_URL="https://eru.gov.cz" ;;
    ctu) ADR_CS="Český telekomunikační úřad"; ADR_EN="Czech Telecommunication Office"; ADR_URL="https://ctu.gov.cz" ;;
    finarbitr) ADR_CS="Finanční arbitr"; ADR_EN="Financial Arbitrator"; ADR_URL="https://finarbitr.gov.cz" ;;
    cak) ADR_CS="Česká advokátní komora"; ADR_EN="Czech Bar Association"; ADR_URL="https://www.cak.cz" ;;
    *) echo "ERROR: unknown --adr=$ADR"; usage; exit 1 ;;
esac

# Detect Bolt CMS project root
if [ -f "./config/services.yaml" ]; then
    BASE_DIR="$(pwd)"
else
    DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    while [ "$DIR" != "/" ]; do
        if [ -f "$DIR/config/services.yaml" ]; then
            BASE_DIR="$DIR"
            break
        fi
        DIR="$(dirname "$DIR")"
    done
fi

if [ -z "$BASE_DIR" ] || [ ! -f "$BASE_DIR/config/services.yaml" ]; then
    echo "ERROR: Could not locate Bolt CMS project root (config/services.yaml not found)."
    exit 1
fi

cd "$BASE_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_DIR="$(cd "$SCRIPT_DIR/../examples" && pwd)"

echo "=========================================================="
echo " Bolt CMS Legal Information Scaffolder (Czech Republic)"
echo " Project root: $BASE_DIR"
echo "=========================================================="

BOLT_CONFIG="config/bolt/config.yaml"
ACTIVE_THEME="default"
if [ -f "$BOLT_CONFIG" ]; then
    FOUND_THEME=$(grep -E "^theme:" "$BOLT_CONFIG" | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'")
    [ -n "$FOUND_THEME" ] && ACTIVE_THEME="$FOUND_THEME"
fi
THEME_DIR="public/theme/$ACTIVE_THEME"
if [ ! -d "$THEME_DIR" ]; then
    echo "Error: Theme directory '$THEME_DIR' not found."
    exit 1
fi
echo "Target Theme: $ACTIVE_THEME ($THEME_DIR)"
THEME_YAML="$THEME_DIR/theme.yaml"

# 1. theme.yaml legal: block
if [ -f "$THEME_YAML" ] && grep -qE "^legal:" "$THEME_YAML"; then
    echo "Existing: $THEME_YAML already has a legal: block — preserved."
else
    case "$OPERATOR" in
        trade) REGISTRY="    office: ~                           # optional: the trade licensing office, e.g. 'Úřad městské části Praha 1'" ;;
        company) REGISTRY="    court: '[DOPLNIT rejstříkový soud, např. Městský soud v Praze]'
    section: '[DOPLNIT oddíl]'
    insert: '[DOPLNIT vložka]'" ;;
        *) REGISTRY="    text: { cs: '[DOPLNIT zápis v evidenci, např. Advokát zapsaný v seznamu advokátů ČAK pod ev. č. …]' }" ;;
    esac
    REGULATED="  regulated: ~"
    if [ "$OPERATOR" = "profession" ]; then
        REGULATED="  regulated:
    chamber: { cs: '[DOPLNIT profesní komora]' }
    title: { cs: '[DOPLNIT profesní označení a stát, kde bylo uděleno]' }
    rules_url: ~"
    fi
    WB_URL="~"
    [ "$WHISTLEBLOWING" = true ] && WB_URL="'[DOPLNIT URL stránky s informacemi o oznamování]'"
    TERMS="~"; COMPLAINTS="~"; WITHDRAWAL="~"
    if [ "$ONLINE" = true ]; then
        TERMS="'/obchodni-podminky'"
        COMPLAINTS="'/reklamacni-rad'"
        WITHDRAWAL="'/odstoupeni-od-smlouvy'"
    fi
    touch "$THEME_YAML"
    [ -s "$THEME_YAML" ] && [ -n "$(tail -c 1 "$THEME_YAML")" ] && echo "" >> "$THEME_YAML"
    cat >> "$THEME_YAML" <<YAML

# Legal identity and consumer information (bolt-legal-cz, references/requirements.cs.md).
# Name, seat and IČO live in contact: above. Fill every [DOPLNIT] from ARES or the operator.
legal:
  operator: $OPERATOR
  registry:
$REGISTRY
  dic: ~                                # 'CZ…' when a VAT payer (ID-07)
  consumers: $CONSUMERS
  adr:
    name: { cs: '$ADR_CS', en: '$ADR_EN' }
    url: '$ADR_URL'
  complaints_url: $COMPLAINTS
  online_contracts: $ONLINE
  terms_url: $TERMS
  withdrawal_url: $WITHDRAWAL
  microenterprise: $MICRO
  reviews:
    shown: $REVIEWS
    verification: ~                     # how reviews are verified (localized), ~ = "not verified" notice
$REGULATED
  whistleblowing: $WHISTLEBLOWING
  whistleblowing_url: $WB_URL
YAML
    echo "Added: legal: block to $THEME_YAML"
fi

copy_if_missing() {
    local src="$1"
    local dest="$2"
    mkdir -p "$(dirname "$dest")"
    if [ ! -f "$dest" ]; then
        cp "$src" "$dest"
        echo "Created: $dest"
    else
        echo "Existing: $dest preserved."
    fi
}

# 2. Partials
copy_if_missing "$EXAMPLES_DIR/_legal-identity.twig" "$THEME_DIR/partials/_legal-identity.twig"
[ "$REVIEWS" = true ] && copy_if_missing "$EXAMPLES_DIR/_reviews-notice.twig" "$THEME_DIR/partials/_reviews-notice.twig"

# 3. Footer wiring (bolt-menu's footer includes the partial; older footers need the include)
FOOTERS=$(grep -rlE "_legal-identity\.twig" "$THEME_DIR" --include="*.twig" 2>/dev/null | grep -v "partials/_legal-identity.twig" || true)
if [ -n "$FOOTERS" ]; then
    echo "Verified: partials/_legal-identity.twig included in: $(echo "$FOOTERS" | tr '\n' ' ')"
else
    echo "Note: include the identity in the footer of every page (ID-05), e.g. above the copyright line:"
    echo "        {% include 'partials/_legal-identity.twig' %}"
fi

# 4. Translations and next steps
echo "----------------------------------------------------------"
echo "Translations: merge the legal.* units into every catalog:"
echo "  php <bolt-skills>/scripts/merge-xliff.php $EXAMPLES_DIR/translations.cs.xlf translations/messages.cs.xlf"
echo "  php <bolt-skills>/scripts/merge-xliff.php $EXAMPLES_DIR/translations.en.xlf translations/messages.en.xlf"
[ "$REVIEWS" = true ] && echo "Reviews: include partials/_reviews-notice.twig below every block that shows reviews (SP-06)."
[ "$ONLINE" = true ] && echo "Online contracts: create the pages under terms_url, complaints_url and withdrawal_url with the operator's texts (EC-01–EC-05); the withdrawal button is mandatory from 1. 1. 2027."
[ "$WHISTLEBLOWING" = true ] && echo "Whistleblowing: publish the page with the § 9 odst. 2 písm. b) information and set whistleblowing_url (WB-01)."
echo "Next: fill every [DOPLNIT], clear the cache (bin/console cache:clear), then run"
echo "  bash $SCRIPT_DIR/verify.sh --draft --ares"
echo "----------------------------------------------------------"
