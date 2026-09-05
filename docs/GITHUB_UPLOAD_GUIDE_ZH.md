# GitHub 上传保姆级教程（Windows）

本教程用于发布研究代码，不用于发布患者级数据。正式上传前，请先完成本仓库自带的自动检查。

## 一、上传前准备

1. 安装 [Git for Windows](https://git-scm.com/download/win)。安装时保留默认选项即可。
2. 注册并登录 GitHub。
3. 确认待上传文件夹名称为 `intraoperative-map-phenotypes`。
4. 不要把 MOVER、INSPIRE 原始文件或任何患者级中间表复制到本文件夹。
5. 在 PowerShell 中进入仓库：

```powershell
cd "C:\你的路径\intraoperative-map-phenotypes"
```

6. 运行无需患者数据的检查：

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements-dev.txt
python -m pytest tests -q
python scripts\verify_reference_outputs.py
python scripts\audit_public_release.py
```

只有最后看到 `PASS` 且测试无报错，才继续上传。

## 二、修改仓库地址占位符

打开 `CITATION.cff`，把 `REPLACE_WITH_OWNER` 替换成你的 GitHub 用户名。例如用户名为 `1449648578Zyc`，则地址为：

```text
https://github.com/1449648578Zyc/intraoperative-map-phenotypes
```

Zenodo DOI 尚未生成时，先保留 Data Sharing Statement 中的 DOI 占位符。

## 三、在 GitHub 新建空仓库

1. 登录 GitHub，点击右上角 `+`，选择 **New repository**。
2. Repository name 填写 `intraoperative-map-phenotypes`。
3. Description 可填写：

```text
Reproducible analysis code and frozen classifier for intraoperative MAP phenotypes in MOVER and INSPIRE 1.0.
```

4. 选择 **Public**。
5. **不要**勾选 Add a README、Add .gitignore 或 Choose a license；本代码包已经包含这些文件。
6. 点击 **Create repository**，复制页面显示的仓库地址。

## 四、第一次上传

仍在代码包目录的 PowerShell 中，逐行执行：

```powershell
git init -b main
git add .
git status --short
```

认真查看 `git status --short`。不应出现以下内容：

- MOVER或INSPIRE原始CSV；
- `LOG_ID`、`MRN`、`subject_id`或`op_id`级结果表；
- `config.local.json`；
- `data`、`derived`、`work`或`outputs`目录；
- 密码、令牌、下载命令中的用户名。

确认无误后执行：

```powershell
git commit -m "Public analysis release v1.0.0"
git remote add origin https://github.com/你的用户名/intraoperative-map-phenotypes.git
git push -u origin main
```

首次推送通常会弹出浏览器登录。使用浏览器完成授权，不要把密码或访问令牌写入脚本。

如果提示 `remote origin already exists`，先检查现有地址：

```powershell
git remote -v
```

只有确认地址错误时才运行：

```powershell
git remote set-url origin https://github.com/你的用户名/intraoperative-map-phenotypes.git
```

## 五、检查线上仓库

在 GitHub 页面逐项确认：

1. 首页显示 README。
2. `Actions` 页面中的 `Validate public release` 为绿色通过。
3. `model/` 中有3个冻结模型CSV。
4. `results/` 中只有汇总结果。
5. 搜索其他INSPIRE版本标记、作者电脑绝对路径和本地盘符，结果应为空。
6. GitHub 自动识别 `CITATION.cff`，页面应出现 **Cite this repository**。

## 六、发布投稿对应的冻结版本

1. 进入仓库主页，点击右侧 **Releases**。
2. 点击 **Draft a new release**。
3. 点击 **Choose a tag**，输入 `v1.0.0`，选择创建新标签。
4. Release title 填写 `Submitted analysis release v1.0.0`。
5. Release notes 建议填写：

```text
Frozen public release for the submitted analysis. The repository contains the outcome-blind 91-to-20 MAP feature audit, MOVER-derived scaling and PCA parameters, the 3-centroid phenotype model, INSPIRE version 1.0 external-validation workflow, final BMI quality-control rules, outcome analyses, recognition analyses, synthetic examples, and aggregate reference outputs. No patient-level data are included.
```

6. 点击 **Publish release**。

投稿后不要修改或覆盖 `v1.0.0` 标签。若需更正，发布 `v1.0.1`；若改变分析方法，发布 `v1.1.0` 或更高版本。

## 七、使用Zenodo生成永久DOI

1. 登录 [Zenodo](https://zenodo.org/)。
2. 按照 [Zenodo官方GitHub连接说明](https://help.zenodo.org/docs/github/enable-repository/) 在账户设置中连接GitHub。
3. 在仓库列表中开启 `intraoperative-map-phenotypes`。
4. 按照 [Zenodo官方归档说明](https://help.zenodo.org/docs/github/archive-software/github-upload/) 在GitHub发布release，并等待Zenodo自动归档该版本。
5. 打开 Zenodo 记录，复制版本 DOI。
6. 将 DOI 写入论文 Data Sharing Statement、README 和 `CITATION.cff`。
7. 若 `v1.0.0` 已归档，不要移动或重写该标签；可在主分支补充 DOI 元数据，并发布仅含元数据更正的 `v1.0.1`。

## 八、后续更新的标准流程

每次修改后执行：

```powershell
python -m pytest tests -q
python scripts\verify_reference_outputs.py
python scripts\audit_public_release.py
git status --short
git add .
git commit -m "Describe the change"
git push
```

## 九、常见问题

### GitHub拒绝大文件

源数据库文件不应上传，也不应使用Git LFS绕过限制。把数据保留在本地受控目录，并在 `config.local.json` 中填写路径。

### PowerShell不允许激活虚拟环境

可在当前窗口临时执行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv\Scripts\Activate.ps1
```

### 想用GitHub Desktop

先在代码目录运行 `git init -b main`，再在GitHub Desktop选择 **File > Add Local Repository**，添加本目录，最后点击 **Publish repository**。发布前同样必须运行隐私检查。

### 数据应放在哪里

建议放在仓库外，例如 `D:\research_data\MOVER` 和 `D:\research_data\INSPIRE\1.0`。仓库只保存代码、冻结参数、合成示例和汇总结果。
