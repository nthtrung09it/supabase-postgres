#!/usr/bin/env bash
# Image tags of the PG 18 fork builds (build-supabase-postgres-18.yml, build-cnpg-supabase-postgres-18.yml).
#
# Scheme (owner decision 2026-09-27): <release>-rc<N>-up<upstream sha8>-<commit sha8>
#   release  postgres18 in ansible/vars.yml without its -rcN (18.6.0.001-rc1 -> 18.6.0.001)
#   N        every build takes the next free rc of that release, counted over BOTH repos
#   base     supabase-postgres:18.6.0.001-rc1-up07c75511-76be8da8
#   cnpg     cnpg-supabase-postgres:<exactly the tag of the base it is built on>
#            — a CNPG-only rebuild (that tag exists in the cnpg repo already) takes the next rc
#              and the SAME base image is tagged with it too (Harbor add-tag, same digest)
#
#   image-tag.sh release                      -> 18.6.0.001
#   image-tag.sh next-rc <release>            -> next free N
#   image-tag.sh exists <repo> <tag>          -> exit 0 if the tag exists
#   image-tag.sh add-tag <repo> <tag> <new>   -> tag the artifact <repo>:<tag> as <new> as well
#
# Needs HARBOR_USERNAME / HARBOR_PASSWORD, curl, jq. HARBOR (harbor.trungnguyen.dev), PROJECT (elearning).
set -euo pipefail
HARBOR=${HARBOR:-harbor.trungnguyen.dev}; PROJECT=${PROJECT:-elearning}
REPOS=(supabase-postgres cnpg-supabase-postgres)
api() { curl -fsS --retry 4 --retry-all-errors -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" "$@"; }
tags() { # every tag of a repo (paged)
  local page=1 out
  while :; do
    out=$(api "https://$HARBOR/api/v2.0/projects/$PROJECT/repositories/$1/artifacts?with_tag=true&with_label=false&page_size=100&page=$page") || return 1
    [ "$(jq length <<<"$out")" -gt 0 ] || break
    jq -r '.[].tags[]?.name' <<<"$out"
    page=$((page + 1))
  done
}

case "${1:-}" in
  release)
    rel=$(sed -n -E 's/^[[:space:]]*postgres18:[[:space:]]*"([^"]+)".*/\1/p' "${VARS:-ansible/vars.yml}")
    [ -n "$rel" ] || { echo "no postgres_release.postgres18 in ansible/vars.yml" >&2; exit 1; }
    echo "${rel%-rc*}" ;;
  next-rc)
    rel=${2:?release}; max=0
    for r in "${REPOS[@]}"; do   # a failed listing must stop the build: counting too few tags reuses an rc
      all=$(tags "$r") || { echo "cannot list the tags of $PROJECT/$r" >&2; exit 2; }
      while read -r n; do [ "$n" -gt "$max" ] && max=$n; done \
        < <(sed -n -E "s/^${rel//./\\.}-rc([0-9]+)(-.*)?$/\1/p" <<<"$all")
    done
    echo $((max + 1)) ;;
  exists)   # 0 = exists, 1 = does not, 2 = cannot tell
    all=$(tags "${2:?repo}") || { echo "cannot list the tags of $PROJECT/$2" >&2; exit 2; }
    grep -q -x -F "${3:?tag}" <<<"$all" ;;
  add-tag)
    repo=${2:?repo}; ref=${3:?tag}; new=${4:?new tag}
    api -X POST -H 'Content-Type: application/json' -d "{\"name\": \"$new\"}" \
      "https://$HARBOR/api/v2.0/projects/$PROJECT/repositories/$repo/artifacts/$ref/tags" >/dev/null ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
