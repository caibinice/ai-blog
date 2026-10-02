---
title: 智慧停车数字孪生的三维渲染与移动端工程实践
excerpt: 保留全屏沉浸体验和精细园区，通过车辆实例化、保守 LOD、清晰度预算与按需浮层，让桌面和手机共享可探索的三维停车场。
---

更新于 2026-10-03：精细园区与全屏交互保留，补齐三车自动巡行、四轮转动、固定尾随和原电路开场动画。

三维停车场的核心体验，是在完整园区里自由旋转、缩放和探索。数据、图表和记录应当在需要时出现，而不是长期占据主界面。这轮工程改造围绕这个目标展开：保留原始建模的精致程度，再降低重复几何、资源传输和页面维护的成本。

[桌面演示](/smartParking/) · [手机演示](/smartParking/mobile) · [GitHub 源码](https://github.com/caibinice/3dSmartParking)

![默认全屏精细园区](/images/project-parking.png)

## 用体验约束资产优化

原工程使用 Angular 18 和 Babylon.js 7，资源目录约 616 MB，默认园区 GLB 为 164,807,820 字节。两个主组件各接近 58 KB，混合了模型、相机、鼠标事件、图表和业务定时器。

首轮重构的压缩力度过大：剥离纹理、用盒体搭建手机园区，虽然减少了文件体积，却损失了辨识度与近景质量。因此重新回到原始资产，以建筑轮廓、道路标线、窗户层次和车辆材质为视觉约束，针对真正重复的部分优化。

| 资源 | 桌面版 | 手机版 |
|---|---:|---:|
| 园区 GLB | 18,953,916 字节 | 16,444,988 字节 |
| 车辆模板 GLB | 1,420,956 字节 | 1,350,928 字节 |
| 园区图像纹理 | 18 | 18 |
| 车辆图像纹理 | 7 | 7 |
| 停放车辆实例 | 126 | 126 |

园区与车辆合计约 20.37 MB / 17.80 MB，相对原默认园区单文件减少约 87.6% / 89.2%。客户端只加载对应的一套 LOD。体积不再是唯一指标，模型在近景中仍保留车身曲面、轮毂、车窗和建筑细部。

## 共享精细车辆与静态合批

原园区把大量车辆顶点合并存放。改造时从重复车牌几何恢复停放车辆的位置与方向，再用一个精细车辆模板共享几何和材质。模板保留七种精细材质；拆出四个轮胎与轮毂后，每个几何部件通过 thin instances 提交 126 个变换矩阵。

```typescript
// partTransform 包含轮胎部件的局部位移；TypedArray 需显式展开。
const matrices = new Float32Array(placements.matrices.flatMap(matrix =>
  Array.from(partTransform.multiply(Matrix.FromArray(matrix)).asArray())));
mesh.thinInstanceSetBuffer('matrix', matrices, 16, true);
mesh.thinInstanceEnablePicking = true;
```

实例化保留精细外观，并让鼠标拾取返回实际车辆的实例编号。点击车辆后，镜头平滑进入对应位置；演示巡行车则沿原动画提取的道路轨迹运动，并支持镜头跟随。轨迹复用减少了手写路径穿越建筑的风险。

园区静态几何按材质合批，再执行去重、焊接和保守减面。桌面与手机控制不同的减面比例和纹理尺寸，保留同一组建筑与材质层次。

```javascript
await document.transform(
  flatten({ cleanup: false }),
  join({ cleanup: false }),
  dedup({ keepUniqueNames: true }),
  weld(),
  simplify({ simplifier: MeshoptSimplifier, ratio, error: 0.00015 }),
  textureCompress({ encoder: sharp, resize: [textureSize, textureSize] }),
  prune()
);
```

静态世界矩阵和不变材质可冻结，动态车辆与相机继续更新。增加三辆巡行车和独立轮胎后，完整场景包含 121 个 Mesh，而不是为每辆车创建一整套独立资源。

![车辆实例的近景检查](/images/project-parking-detail.png)

## 车辆运动与固定尾随

导入车模的前向轴并不一定与引擎默认一致。源车模朝向为 -Y，向上为 -Z，且几何带有倾斜角度；直接把道路方向当作 +Z 使用，会让车辆倒着走。资产管线根据四轮位置建立正交基，将车模规范为 +Z 前向、+Y 向上，停放矩阵同时应用逆变换，保留原布局。

四个轮胎和轮毂保留为独立节点。每帧累加 `行驶距离 / 轮胎半径` 得到滚动角度，暂停、路线跳转时分别处理，避免静止空转或大跨度跳帧。三条轨迹复用源动画，并错开起始时间与速度，让进入场景后的园区自然有车运行。

尾随相机每帧依据当前车头方向计算车后固定距离和固定高度，而不是只移动目标点：

```typescript
eye.set(x - Math.sin(yaw) * distance,
  y + height, z - Math.cos(yaw) * distance);
target.set(x, y + lookHeight, z);
```

进入尾随时关闭轨道相机的拖拽惯性，退出后恢复手动探索。开场则保留原电路动画，替换旧名称并压缩到 1080p；模型加载期间循环，准备完成后自然结束，也提供跳过与媒体失败回退。

## 信息界面按需浮现

主画布始终占满浏览器视口。底部圆形菜单提供数据、分区、记录、提醒、视角和设置入口，点击后才打开玻璃质感浮层。关闭浮层不会触发画布缩放，也不会改变用户刚刚调整的镜头。

区域定位点、告警区域和泊位推荐共用相机飞行逻辑，采用缓动插值，避免突然跳转。全景、俯视、自动巡航与车辆特写构成不同的探索路径。纯净模式隐藏标题、菜单和定位点，保留明确的恢复按钮；Esc 也可以关闭信息层。

业务状态独立于渲染：分区容量、在场数量和推荐区域由同一份 signals 数据派生，每五秒更新模拟记录，逐帧绘制不触发业务重新计算。3000 次变化测试检查每次只改变一辆车，且空位加在场始终等于总容量。

演示统计容量为 300，模型中的 126 辆停放车辆保留原始布局，两者不做逐个实时映射。图表、告警、出入记录和车辆行为都明确标注模拟，未接入真实设备。

## 清晰度预算与移动端一致性

画布看起来模糊，常见原因是内部渲染分辨率低于 CSS 显示尺寸。新版默认使用 2× CSS 像素，并为手机/桌面分别设置 400 万/800 万像素预算。1600×900 桌面视口实际渲染为 3200×1800；844×390 手机视口渲染为 1688×780。

```typescript
const ratio = Math.max(1, Math.min(desiredRatio,
  Math.sqrt(pixelBudget / Math.max(1, width * height))));
engine.setHardwareScalingLevel(1 / ratio);
```

持续低帧率时，自动策略先关闭额外光效并降低绘制频率，保留至少原生分辨率；节能档由用户主动选择。FPS 来自实际执行的 `scene.render()` 次数，不用 RAF 回调数代替。

手机版使用保守 LOD，不把园区换成盒体，也不删除窗户和车辆纹理。单指旋转、双指缩放，主要底栏按钮为 44 像素。竖屏通过 CSS 转换为横向场景，触控坐标同步做逆变换：

```typescript
const point = portrait
  ? { x: event.clientY - rect.top, y: rect.right - event.clientX }
  : { x: event.clientX - rect.left, y: event.clientY - rect.top };
```

![手机横屏的精细园区](/images/project-parking-mobile.png)

全屏按钮尝试系统横屏锁定；页面级横向布局同时覆盖浏览器不支持方向锁定的情况。默认使用 WebGL2，`?renderer=webgpu` 可显式选择新后端，能力检测与初始化在任何模型加载之前完成。

## 脱敏、生命周期与发布

脱敏既检查网页名称，也检查模型招牌、楼体内嵌文字、供应商水印和车牌纹理。原实体招牌和两处文字几何单独清理，楼顶生成可双向阅读的“某某中医院”招牌。其他精细纹理保留，旧监控视频和固定设备地址不发布。

`ParkingScene` 管理引擎与资产生命周期，`ResizeObserver` 处理画布尺寸变化。页面隐藏时暂停绘制和业务推进，路由离开时释放场景、引擎、监听、观察器和定时器；异步加载结束前检查销毁状态。加载中断提供精细场景重试入口，避免悄悄显示低精度替代物。

生产站点位于 `/smartParking/`，手机深链接 `/smartParking/mobile` 可直接刷新。静态文件进入带时间戳的 release，备份 Nginx 配置后原子切换软链接；配置检查或自检失败时恢复旧版本。HTML 重新验证，指纹脚本长期缓存，版本化模型使用 gzip 和短期缓存。

验收包括类型检查、八项数据与运动学测试、四个 GLB/轮胎/轨迹契约审计，以及图表隐藏、实例拾取、固定尾随、三车切换、慢网开场和手机横竖屏等四十六项本地浏览器断言。生产 HTTPS 入口发布后另行复测。

这轮实践的关键，是先确定用户想保留的体验，再寻找成本最集中的部分。精细建模与移动性能可以通过资产复用、适度 LOD、像素预算和按需信息层共同平衡。

## 参考资料

- [Babylon.js 实例化](https://doc.babylonjs.com/features/featuresDeepDive/mesh/copies/instances)
- [Babylon.js 场景优化](https://doc.babylonjs.com/features/featuresDeepDive/scene/optimize_your_scene)
- [Babylon.js WebGPU](https://doc.babylonjs.com/setup/support/webGPU)
- [glTF Transform](https://gltf-transform.dev/)
- [项目优化记录](https://github.com/caibinice/3dSmartParking/blob/main/docs/optimization-plan.md)
