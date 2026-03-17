# closetapp

一款用于管理衣橱、保存搭配、记录穿搭日记的 iOS 应用。

## 当前版本

- `v0.1`

## 项目内容

- `closet/`: iOS App 源码
- `closet.xcodeproj/`: Xcode 工程
- `closetTests/`: 单元测试
- `closetUITests/`: UI 测试
- `Config/`: 本地配置示例

## 本地运行

1. 使用 Xcode 打开 [closet.xcodeproj](/Users/zhaojianhua/github/closet/closet.xcodeproj)
2. 按需补充 `Config/Secrets.xcconfig` 和 `Config/Server.env`
3. 选择模拟器或真机运行

### 豆包试穿图配置

应用内的 AI 搭配图/试穿图使用豆包图片生成接口，当前接入配置如下：

- Base URL: `https://ark.cn-beijing.volces.com/api/v3`
- Endpoint: `/images/generations`
- 鉴权: `Authorization: Bearer <DOUBAO_API_KEY>`
- 默认模型: `doubao-seedream-4-5-251128`

本地开发时请复制 `Config/Secrets.example.xcconfig` 为 `Config/Secrets.xcconfig`，并填写：

```xcconfig
DOUBAO_API_URL = https://ark.cn-beijing.volces.com/api/v3
DOUBAO_API_KEY = your-doubao-api-key
DOUBAO_MODEL = doubao-seedream-4-5-251128
```

当前项目里的试穿图生成入口：

- AI 搭配生成会调用 [closet/Services/DoubaoOutfitImageService.swift](/Users/zhaojianhua/github/closet/closet/Services/DoubaoOutfitImageService.swift)
- 手动选款保存搭配时，也会优先生成一张试穿封面图再保存
- 参考图来源于用户三视图和已选衣物图片，生成结果保存为本地封面图

### SiliconFlow 深度分析配置

分析页的“AI 深度报告”会将当前衣橱中的全部单品信息直接发送给 SiliconFlow 文本模型生成建议，当前接入配置如下：

- Base URL: `https://api.siliconflow.cn/v1`
- Endpoint: `/chat/completions`
- 鉴权: `Authorization: Bearer <SILICONFLOW_API_KEY>`
- 默认文本模型: `Qwen/Qwen2.5-72B-Instruct-128K`
- 默认视觉模型: `Qwen/Qwen2.5-VL-32B-Instruct`

本地开发时请在 `Config/Secrets.xcconfig` 中补充：

```xcconfig
SILICONFLOW_API_KEY = your-siliconflow-api-key
SILICONFLOW_MODEL = Qwen/Qwen2.5-72B-Instruct-128K
```

## 推送记录规范

从这次开始，每次推送都要在 README 的“更新记录”里补一条，至少写清楚：

- 这次新增了什么主要功能
- 修复了什么主要问题
- 当前对应的版本号或提交阶段

建议格式：

```md
## v0.x

- 新功能：
- 修复：
```

## 更新记录

## v0.1.7

- 新功能：
  - 衣橱分类标签收敛为 `上装 / 下装 / 外套 / 连衣裙 / 鞋子 / 帽子 / 饰品 / 包 / 未分类`，并支持基于单品名称与 AI 分析自动归类
  - 衣橱搜索支持命中 AI 分析维度，如风格、版型、季节、场景、材质与保暖度
  - 搭配页改为按场景分类浏览，新增 `日常 / 通勤 / 约会 / 聚会 / 出游 / 运动 / 正式 / 度假 / 未分类`
  - 搭配详情页新增标签选择与自定义标签输入，并重做详情页信息层级与视觉布局
  - 身体三视图上传接入本地一键抠图，处理完成后固定按 9:16 比例展示
- 修复：
  - 修复手动搭配保存后试穿封面生成状态不同步的问题，支持先保存搭配再后台补生成封面
  - 修复分析页、记录页与部分页面顶部按钮/入口冗余问题，统一为更简洁的交互
  - 回退本轮未完成的键盘避让实验，避免影响当前页面基础布局

## v0.1.6

- 新功能：
  - 分析页的 AI 深度报告改为直接整理当前衣橱全部单品数据，并调用 SiliconFlow 的 `Qwen/Qwen2.5-72B-Instruct-128K` 生成中文深度建议
  - 分析弹窗新增生成中和失败态展示，点击分析页 AI 入口会立即触发最新报告生成
  - 新增 `SILICONFLOW_MODEL` 配置项，并在 README 与示例配置中补充文本模型接入说明
- 修复：
  - 修复分析页 AI 按钮此前只弹窗、不实际触发深度分析的问题

## v0.1.5

- 新功能：
  - 支持在项目目录内保存本地 GitHub token 配置，并通过 `.gitignore` 避免误提交
- 修复：
  - 修复穿搭日记日历打点与当日详情展示不一致的问题，按实际可展示的照片和搭配状态决定是否显示彩色标记
  - 修复记录页当日实拍优先显示关联搭配封面图的逻辑，并统一记录页图片展示比例为 9:16

## v0.1.4

- 新功能：
  - AI 搭配会先根据用户需求、天气和衣物 AI 分析筛选单品，再生成搭配，并在命中已保存同款搭配时直接复用现有结果
  - 手动搭配与 AI 搭配统一新增搭配分类、场景标签和 AI 解读，便于在“我的搭配”中搜索和浏览
  - 搭配详情页支持三种图源切换：幕布底稿、AI 试穿图、真实照片，并可手动设置任意一种为封面
  - 搭配详情页新增“记录”入口，可弹出当月日历选择任意日期，将当前搭配保存为当天穿搭记录
  - 批量导入衣物改为直接回到衣橱页后台识别，识别完成后自动回填分类、名称、颜色和 AI 分析
- 修复：
  - 修复运行时 `DOUBAO_API_URL` 配置异常时生成请求地址错误的问题，并补强豆包与硅基流动的配置校验
  - 修复“我的搭配”标签沿用单品标签导致语义不准确的问题，改为输出搭配层面的场景和风格标签
  - 修复记录页当日实拍/当日搭配展示逻辑，支持关联搭配后默认显示封面图，并统一相关图片为 9:16 比例
  - 修复搭配详情、封面切换、真实照片导入和试穿图保存相关的数据结构兼容问题

## v0.1.3

- 新功能：
  - 接入豆包图片生成配置，统一使用 `https://ark.cn-beijing.volces.com/api/v3/images/generations` 生成 AI 搭配图和试穿图
  - 手动保存搭配时新增试穿封面生成链路，使用人物三视图和所选衣物图生成保存封面
  - README 新增豆包接入说明与本地配置示例，方便直接落地配置 `DOUBAO_API_URL`、`DOUBAO_API_KEY` 和 `DOUBAO_MODEL`
- 修复：
  - 补齐 `Secrets.example.xcconfig` 中缺失的豆包 URL 与模型示例，避免本地接入时只填 API Key 仍无法完整对齐环境

## v0.1.2

- 新功能：
  - 继续统一主页面页头结构，改为共享的标题组件骨架，支持统一的标题后缀和按钮区布局
- 修复：
  - 修复衣橱、搭配、分析、穿搭日记、身体档案等页面标题行未完全对齐的问题
  - 修复衣橱页 badge 字重与其他页面不一致的问题
  - 调整衣橱页右侧按钮区样式，去掉外层白色背景容器
  - 统一标题下搜索框、标签区与分析页 tab 的顶部节奏和样式

## v0.1.1

- 新功能：
  - 新增项目 `README.md`，补充项目简介、目录结构和本地运行说明
  - 建立固定的推送记录规范，后续每次推送都会在 README 记录主要新功能和修复
- 修复：
  - 补齐首个公开仓库版本的发布说明，方便后续版本追踪和 GitHub 展示

## v0.1

- 新功能：
  - 完成衣橱、搭配、穿搭日记、身体档案、分析页等主要页面骨架
  - 支持本地单品录入、搭配保存、穿搭日记记录与关联搭配
  - 接入本地抠图、自动标签、搭配预览与图片存储能力
  - 完成基础的本地数据存储、备份与恢复能力
- 修复：
  - 修复记录页关联搭配展示、点击区域、编辑保存后关联丢失等问题
  - 修复穿搭日记二次编辑时图片和当日穿搭可能被清空的问题
  - 修复多页面标题、badge、按钮区、搜索框与标签区样式不一致的问题
  - 优化白底图片抠图流程与透明图导出逻辑
