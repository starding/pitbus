#!/bin/zsh
# Copy PitBus without its company packs into another git checkout, for the open-source repository:
#   ./export-oss.sh ~/Documents/pitbus-oss
# Only committed files go, minus org/ (.gitattributes marks it export-ignore). The copy is then tested, which
# also checks that no word a company pack calls private is left. Committing and pushing stay with the person.
set -euo pipefail

ROOT=${0:A:h}
DEST=${1:?usage: ./export-oss.sh <folder of the open-source checkout>}
mkdir -p "$DEST"
[[ -z $(git -C "$ROOT" status --porcelain) ]] || { echo "先提交改动：导出只取已提交的文件" >&2; exit 1; }

# the company's private words, checked here because the copy no longer has org/ to read them from
TERMS=$(python3 -c 'import glob,json; print("\n".join(t for p in glob.glob("'"$ROOT"'/org/*/org.json") for t in json.load(open(p)).get("private_terms", [])))')

find "$DEST" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
git -C "$ROOT" archive HEAD | tar -x -C "$DEST"
if [[ -n $TERMS ]] && grep -rIil -F -f <(print -r -- "$TERMS") "$DEST" --exclude-dir=.git; then
  echo "上面这些文件里还有公司内部的词，没有导出完成" >&2
  exit 1
fi
(cd "$DEST" && python3 -m unittest discover -s tests -q)
echo "已导出到 $DEST，检查 git diff 后再提交、推送"
