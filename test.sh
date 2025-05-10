#!/bin/bash
set -eo pipefail

# ========== 自动配置区域 ==========
REMOTE="origin"                      # 远程仓库名称
INITIAL_VERSION="1.0"                # 初始版本号
PROJECT_NAME=$(basename $(git rev-parse --show-toplevel) 2>/dev/null)  # 自动获取项目名称
# =================================

# 检查是否为 Git 仓库
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "错误：当前目录不是 Git 仓库！"
  exit 1
fi

# 确保 PROJECT_NAME 不为空
if [ -z "$PROJECT_NAME" ]; then
  echo "错误：无法获取项目名称！"
  exit 1
fi

# 步骤1：获取远程所有tags并打印
echo "=== 同步远程标签 ==="
git fetch --tags
echo -e "当前所有标签："
git tag --sort=-creatordate | while read tag; do
    git show --no-patch --no-notes --pretty='%ai' $tag
done

echo "=================================="

# 步骤2：获取最新tag后的commit
echo "$LATEST_TAG"
  
  if [ -z "$COMMIT_RANGE_FILTERED" ]; then
    echo -e "\n⚠️ 没有需要打包的新提交！"
    exit 0
  fi
  COMMIT_RANGE=$(echo "$COMMIT_RANGE_FILTERED" | xargs)
fi

# 步骤3：过滤符合规范的commit
declare -a COMMIT_LIST
INDEX=0
VERSION_UPDATED=0

while IFS= read -r commit_hash; do
  line=$(git log -1 --pretty=format:"%s" "$commit_hash")
  ((INDEX++)) || true
  # 解析提交类型
  if [[ "$line" =~ ^([a-z]+)(\$[^)]+\$)?:\ (.+)$ ]]; then
    type=${BASH_REMATCH[1]}
    scope=${BASH_REMATCH[2]:-""}
    subject=${BASH_REMATCH[3]}

    # 移除 scope 可能包含的括号
    scope=${scope#\$}  # 删除左括号
    scope=${scope%\$}   # 删除右括号

    # 版本控制逻辑
    if [[ $type =~ ^(feat|refactor|perf)$ ]] && [ $VERSION_UPDATED -eq 0 ]; then
      MAJOR=$((MAJOR + 1))
      MINOR=0
      VERSION_UPDATED=1
    elif [ $VERSION_UPDATED -eq 0 ]; then
      MINOR=$((MINOR + 1))
    fi

    # 生成带序号的提交记录
    printf -v entry "%-4s [%-7s] %s" "$INDEX." "${type^^}" "$subject"
    COMMIT_LIST+=("$entry")
  else
    COMMIT_LIST+=("$INDEX.   [INVALID] 不符合规范的提交: $line")
  fi
done <<< "$COMMIT_RANGE"

# 生成最终版本号
NEW_VERSION="${MAJOR}.${MINOR}"
NEW_TAG="${PROJECT_NAME}_v${NEW_VERSION}"

# 步骤4：生成tag和变更日志
if [ ${#COMMIT_LIST[@]} -eq 0 ]; then
  echo -e "\n⚠️ 没有需要打包的新提交！"
  exit 0
fi

CHANGELOG=$(printf "%s\n" "${COMMIT_LIST[@]}")
if [ -z "$LATEST_TAG" ]; then
  echo -e "\n=== 创建初始标签 $NEW_TAG ==="
  git tag -a "$NEW_TAG" -m "初始版本\n$CHANGELOG"
else
  echo -e "\n=== 生成新标签 $NEW_TAG ==="
  git tag -a "$NEW_TAG" -m "变更记录：\n$CHANGELOG"
fi

# 步骤5：生成zip包
ZIP_FILE="${NEW_TAG}.zip"
git archive --format=zip -o "$ZIP_FILE" "$NEW_TAG"
echo -e "\n将生成的zip包：$ZIP_FILE"

# 步骤6：推送远程
echo -e "\n=== 推送标签到远程仓库 ==="
git push "$REMOTE" "$NEW_TAG"
echo -e "\n✅ 操作完成！新版本 $NEW_TAG 已发布"
echo "变更记录："
echo "$CHANGELOG"