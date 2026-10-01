---
title: 智慧停车数字孪生的三维渲染与移动端工程实践
excerpt: 从大模型资产和固定大屏入手，重构三维停车前端的数据、渲染与移动交互，把园区模型缩减约96%，形成可验证、可部署的数字孪生演示。
---

一个三维停车项目的价值，来自用户能顺利打开园区、看懂泊位状态，并快速找到需要关注的区域。漂亮的场景只是起点，模型资源、业务一致性、触控体验和发布可靠性共同决定它是否可以长期维护。

这次整理的项目是一个基于 Angular 和 Babylon.js 的智慧停车前端。原工程已有园区建模、停车位、监控入口和告警面板，适合展示医院场景。我把它改造成独立、脱敏的交互演示，并增加了专门的手机页面。

[桌面演示](/smartParking/) · [手机演示](/smartParking/mobile) · [GitHub 源码](https://github.com/caibinice/3dSmartParking)

![智慧停车三维工作台](/images/project-parking.png)

## 从资源审计确定优先级

最初的资源目录约616 MB。三个园区模型合计约479 MB，默认加载的GLB为164,807,820字节，另有开场视频、监控视频、字体和动画序列。两个停车组件各接近58 KB，复制了模型加载、摄像头、图表、鼠标事件和定时逻辑。

如果只更换颜色或者把3D引擎版本升级，首屏下载和重复资源问题仍然存在。因此先按“加载成本、运行成本、维护成本”排序：整理资产，统一数据，再重构渲染生命周期和页面布局。

| 维度 | 原工程 | 本次实现 |
|---|---|---|
| 框架 | Angular18、Babylon.js7 | Angular21.2.25、Babylon.js9.29.0 |
| 默认园区模型 | 164.8 MB | 7.09 MB，减少约95.7% |
| 手机模型 | 与大屏思路共用大模型 | 程序化低面数园区，0个GLB请求 |
| 页面结构 | 多个大组件重复实现 | 纯函数数据、signals状态、场景类、展示组件 |
| 数据口径 | 指标和分区各自硬编码 | 容量、在场、空位、推荐和三维比例同源 |
| 发布方式 | 本地开发入口 | HTTPS子路径、静态release、失败回滚 |

## 模型精简同时处理名称和纹理

医院名称既出现在网页标题，也出现在模型招牌几何中。把HTML改成“某某医院”并不会改变楼顶的字；纹理里还可能包含车辆或供应商标记。

我的处理分成三层：界面统一使用某某公司和某某医院；转换GLB时移除实体招牌、高面数车辆、原图像纹理和动画，并清理节点及材质元数据；加载后用DynamicTexture生成“某某中医院”的通用招牌。旧开场、监控视频和固定监控地址不再打包发布。

资产转换使用glTF Transform的dedup、weld、simplify和prune。先去掉高成本且不影响园区主体表达的车辆，再使用较小几何误差简化楼体，避免为了压缩而破坏建筑轮廓。原资产放在外部备份，不进入公开仓库。

```javascript
await document.transform(
  dedup(),
  weld(),
  simplify({ simplifier: MeshoptSimplifier, ratio: 0.15, error: 0.001 }),
  prune()
);
```

最终公开园区为7,089,576字节，没有内嵌图像纹理。场景中的重复车辆由程序化实例替代。这里保留了一个直接可读的GLB，没有引入需要额外远程解码器的运行依赖，Nginx通过预压缩gzip减少传输成本。

## 数据状态和三维对象保持同一口径

数字孪生界面容易出现“总泊位一个值，分区相加又是另一个值”的问题。为此，把分区容量和占用数定义在纯TypeScript模块中，用signals维护当前状态，再由computed派生总量和推荐区域。

```typescript
const capacity = zones.reduce((sum, zone) => sum + zone.capacity, 0);
const occupied = zones.reduce((sum, zone) => sum + zone.occupied, 0);
const free = capacity - occupied;
```

总容量是300。每五秒生成一条模拟出入记录，仅修改对应分区，并保证占用数在0与容量之间。测试运行3000次变化，检查每次只改变一辆车，空位加在场始终等于容量。

三维泊位表达占用比例，而非逐个复刻300个真实车位。业务数值以面板为准，页面明确提示这一点。这样手机可以减少几何数量，同时仍与桌面共享一致的状态语义。

交互也围绕这份状态展开：分区卡片和场景定位点切换区域视角；告警支持定位与确认；出入记录支持车牌/区域搜索和CSV导出；空位最多的区域提供快速导航。页面始终标注交互演示，未接入真实门禁、摄像头或计费设备。

## 把绘制循环和业务更新分开

3D场景由独立ParkingScene类管理，引擎只在动态导入后初始化。Angular采用无Zone模式，业务每五秒更新，逐帧渲染不触发全页面业务计算。

停车位与车辆各使用一个thin-instance源网格。占用变化时重新提交实例矩阵，渲染循环只画场景，不遍历创建一批新的业务对象。实例化的价值是降低重复对象管理与绘制开销，前提是几何和材质可以共享。

生命周期同样重要。ResizeObserver跟踪画布尺寸；页面不可见时暂停绘制和数据推进；离开路由时释放场景、引擎、定时器、观察器和触控监听。异步加载结束时也检查是否已销毁，避免用户切页后旧模型继续更新已离开的页面。

## WebGPU和画质策略

默认使用WebGL，兼顾浏览器覆盖。添加`?renderer=webgpu`可选择WebGPU，引擎能力检测和初始化发生在任何场景资源创建之前；不满足条件时采用WebGL路径。

这次没有把WebGPU当成所有性能问题的解答。大文件仍要下载，重复对象仍有成本，资源泄漏也仍然存在。新后端应该和资产预算、实例化、按需加载以及生命周期一起设计。

画质有自动、高清、均衡和低功耗四档。对devicePixelRatio设置上限，避免高像素密度设备按物理分辨率消耗过多GPU预算。桌面目标60帧、手机目标30帧；自动模式检测实际渲染帧率，持续偏低时降分辨率。

FPS用真正执行的scene.render次数统计，而不是直接使用浏览器RAF回调频率。本机浏览器检查是验收记录的一部分，具体手机仍应按GPU、热量和电池状态实测。

## 手机页的横屏与触控

手机页位于独立的`/mobile`路由，不请求桌面的园区GLB。楼体由盒体和楼层条带构成，车位和车辆保留实例化。业务分区不变，模型细节有意减少，主要按钮提供至少44像素触控高度。

横屏有两条路径：用户点击全屏后尝试Screen Orientation锁定；浏览器限制方向锁定时，竖屏设备通过CSS自动旋转为横向工作台。页面旋转以后，触控坐标还要逆变换，否则旋转和拾取方向会与屏幕不一致。

```typescript
const point = portrait
  ? { x: event.clientY - rect.top, y: rect.right - event.clientX }
  : { x: event.clientX - rect.left, y: event.clientY - rect.top };
```

单指拖动调整相机角度，双指间距变化调整半径。相机有距离和俯仰边界；分区抽屉和底部视角按钮为精确操作提供补充。手机横屏和竖屏均检查滚动边界、按钮可见性和0个GLB请求的资源契约。

## 发布和验证形成闭环

项目部署在`/smartParking/`，Angular生产base href与Nginx路径保持一致，`/smartParking/mobile`支持直接访问和刷新。构建产物进入带时间戳的release，再原子切换`www`软链接。配置先备份并执行nginx -t，失败时恢复原配置和release链接。

HTML重新验证，带指纹的JS/CSS长期缓存，模型使用短期缓存和gzip。模型返回404时不会误返回博客HTML；加载失败仍可使用轻量场景，引擎初始化失败则提供重试说明。

发布前执行类型检查、数据测试、名称/纹理审计和生产构建，之后再在真实HTTPS入口检查桌面、手机和控制台。博客同步加入项目入口、三语文章和实际页面截图。

这轮改造最值得保留的经验，是把资产、状态、绘制和发布看作四个独立但有契约的层次。每一层都能单独检查，三维页面才能在丰富内容的同时保持稳定和可维护。

## 参考资料

- [Angular版本支持与兼容性](https://angular.dev/reference/versions)
- [Babylon.js实例化](https://doc.babylonjs.com/features/featuresDeepDive/mesh/copies/instances)
- [Babylon.js场景优化](https://doc.babylonjs.com/features/featuresDeepDive/scene/optimize_your_scene)
- [Babylon.js WebGPU](https://doc.babylonjs.com/setup/support/webGPU)
- [glTF Transform](https://gltf-transform.dev/)
- [项目优化记录与实现](https://github.com/caibinice/3dSmartParking/blob/main/docs/optimization-plan.md)
