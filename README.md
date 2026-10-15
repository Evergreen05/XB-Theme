# XB-Theme

基于 EZ THEME 改造的 Xboard 前端主题，使用 Vue 3 + Vite 构建，支持在 Xboard 后台直接配置站点名称、主题颜色、入口开关、客户端下载链接等 20+ 项参数。

## 使用

```bash
npm install      # 安装依赖
npm run dev      # 本地开发预览
npm run build    # 构建生产包
```

## 打包上传

```bash
powershell -ExecutionPolicy Bypass -File scripts\build-xboard-package.ps1
```

构建后在项目根目录生成 `EZTheme.zip`，直接上传到 Xboard 后台「主题管理」即可（每次发布需递增脚本中的 `$Version`）。
