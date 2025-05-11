#!/bin/bash
set -eo pipefail

# ========== 自动配置区域 ==========
REMOTE="origin"                      # 远程仓库名称
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
echo "=========== 同步远程标签 ==========="
git fetch --tags
git tag --sort=-creatordate | while read tag; do
    git show --no-patch --no-notes --pretty='%ai' "$tag"
done
echo "=================================="

# 步骤2：获取最新 tag 和提交范围
if LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null); then
  # 解析版本号（兼容项目名称前缀）
  VERSION=$(echo "$LATEST_TAG" | grep -oP '(?<=_v)\d+\.\d+$')
  MAJOR=$(echo $VERSION | cut -d. -f1)
  MINOR=$(echo $VERSION | cut -d. -f2)
else
  LATEST_TAG=""
  # 初始化版本号
  MAJOR=1
  MINOR=0
fi

# 获取提交范围（直接输出格式化的提交信息）
if [ -z "$LATEST_TAG" ]; then
  # 无 tag 时获取所有提交的元数据
  COMMIT_RANGE_FILTERED=$(git log --date=format:'%Y-%m-%d' --pretty=format:"%s   # %ad" | awk '{print NR ". ", $0}')
else
  # 有 tag 时获取自 tag 之后的提交元数据
  COMMIT_RANGE_FILTERED=$(git log "$LATEST_TAG..HEAD" --date=format:'%Y-%m-%d' --pretty=format:"%s   # %ad" | awk '{print NR ". ", $0}')
fi

# 检查是否有新提交
if [ -z "$COMMIT_RANGE_FILTERED" ]; then
  echo -e "\n⚠️ 没有需要打包的新提交！"
  exit 0
fi

# 构建 commit 范围
COMMIT_RANGE="$COMMIT_RANGE_FILTERED"
echo "$COMMIT_RANGE"

VERSION_UPDATED=0
while IFS= read -r line; do
  # 匹配提交类型（忽略前缀编号，类型被尖括号包裹）
  if [[ "$line" =~ ^[0-9]+.\ *\<([a-z]+)\> ]]; then

    type=${BASH_REMATCH[1]}

    # 移除 scope 中的括号
    scope=${scope#$$}
    scope=${scope%$$}

    # 版本控制逻辑
    if [[ $type =~ ^(feat|refactor|perf|chore)$ ]] && [ $VERSION_UPDATED -eq 0 ]; then
      MAJOR=$((MAJOR + 1))
      MINOR=0
      VERSION_UPDATED=1
    fi
  fi

if [ ${#VERSION_UPDATED[@]} -eq 0 ];then
  MINOR=$((MINOR + 1))
fi

done <<< "$COMMIT_RANGE"

# 步骤4：生成 tag 和变更日志
if [ ${#COMMIT_RANGE[@]} -eq 0 ]; then
  echo -e "\n⚠️ 没有需要打包的新提交！"
  exit 0
fi

# 生成最终版本号
NEW_VERSION="${MAJOR}.${MINOR}"
NEW_TAG="${PROJECT_NAME}_v${NEW_VERSION}"

CHANGELOG=$(printf "%s\n" "${COMMIT_RANGE[@]}")
if [ -z "$LATEST_TAG" ]; then
  echo -e "\n=== 创建初始标签 $NEW_TAG ==="
  git tag -a "$NEW_TAG" -m "初始版本\n$CHANGELOG"
else
  echo -e "\n=== 生成新标签 $NEW_TAG ==="
  git tag -a "$NEW_TAG" -m "变更记录：\n$CHANGELOG"
fi

# 步骤5：生成 zip 包
ZIP_FILE="${NEW_TAG}.zip"
git archive --format=zip -o "$ZIP_FILE" "$NEW_TAG"
echo -e "\n将生成的 zip 包：$ZIP_FILE"

# 步骤6：推送远程
echo -e "\n=== 推送标签到远程仓库 ==="
git push "$REMOTE" "$NEW_TAG"
echo -e "\n✅ 操作完成！新版本 $NEW_TAG 已发布"
echo "变更记录："
echo "$CHANGELOG"